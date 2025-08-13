Shader "Custom/RayTracing"
{
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            // --- Estruturas de Dados ---

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };
            
            struct Ray
            {
                float3 origin;
                float3 dir;
            };
            
            struct RayTracingMaterial
            {
                float4 colour;
                float4 emissionColour;
                float4 specularColour;
                float emissionStrength;
                float smoothness;
                float specularProbability;
                int flag;
            };

            struct Sphere
            {
                float3 position;
                float radius;
                RayTracingMaterial material;
                float massa;
            };

            struct Triangle
            {
                float3 posA, posB, posC;
                float3 normalA, normalB, normalC;
            };

            struct MeshInfo
            {
                uint firstTriangleIndex;
                uint numTriangles;
                RayTracingMaterial material;
                float3 boundsMin;
                float3 boundsMax;
            };

            struct HitInfo
            {
                bool didHit;
                float dst;
                float3 hitPoint;
                float3 normal;
                RayTracingMaterial material;
            };

            // --- Buffers e Parâmetros ---

            StructuredBuffer<Sphere> Spheres;
            int NumSpheres;

            StructuredBuffer<Triangle> Triangles;
            StructuredBuffer<MeshInfo> AllMeshInfo;
            int NumMeshes;

            float3 ViewParams;
            float4x4 CamLocalToWorldMatrix;
            float3 _LightDirection;
            float _DirectionalLightIntensity;
            float _HyperbolicCurvature;
            int _UseHyperbolicView;

            const float G = 6.67430e-11;

            // --- Funções de Interseção de Raio ---

            // Função para aplicar curvatura hiperbólica ao raio
            float3 ApplyHyperbolicCurvature(float3 rayDir, float2 screenPos)
            {
                if (_UseHyperbolicView == 0) 
                    return rayDir;
                
                // Calcular a distância do centro da tela
                float2 centeredPos = screenPos - 0.5; // Centralizar coordenadas (-0.5 a 0.5)
                float distanceFromCenter = length(centeredPos);
                
                // Aplicar transformação hiperbólica contínua e suave
                float curvatureFactor = _HyperbolicCurvature;
                
                float hyperbolicScale = 1.0;
                if (distanceFromCenter > 0.001) // Evitar divisão por zero
                {
                    float scaledDistance = distanceFromCenter * curvatureFactor;
                    
                    // Usar uma única função contínua para toda a faixa
                    // Combinar exponencial com sinh para progressão suave
                    float baseScale = exp(scaledDistance * 0.3) - 1.0; // Componente exponencial
                    float hyperbolicComponent = sinh(scaledDistance * 0.8); // Componente hiperbólico
                    
                    // Misturar baseado na intensidade da curvatura
                    float mixFactor = saturate(curvatureFactor / 5.0);
                    hyperbolicScale = lerp(
                        1.0 + baseScale * 0.5, // Baixa curvatura - mais suave
                        hyperbolicComponent,    // Alta curvatura - mais dramático
                        mixFactor
                    ) / scaledDistance;
                    
                    // Garantir que sempre seja >= 1.0 para evitar inversão
                    hyperbolicScale = max(hyperbolicScale, 1.0);
                }
                
                // Aplicar a escala hiperbólica às coordenadas
                float2 curvedPos = centeredPos * hyperbolicScale;
                
                // Reconstruir a direção do raio com a curvatura aplicada
                float3 curvedRayDir = float3(curvedPos.x * ViewParams.x, curvedPos.y * ViewParams.y, ViewParams.z);
                curvedRayDir = mul(CamLocalToWorldMatrix, float4(curvedRayDir, 0)).xyz;
                
                return normalize(curvedRayDir);
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            HitInfo RaySphere(Ray ray, float3 sphereCentre, float sphereRadius)
            {
                HitInfo hitInfo = (HitInfo)0;
                float3 offsetRayOrigin = ray.origin - sphereCentre;
                float a = dot(ray.dir, ray.dir);
                float b = 2 * dot(offsetRayOrigin, ray.dir);
                float c = dot(offsetRayOrigin, offsetRayOrigin) - sphereRadius * sphereRadius;
                float discriminant = b * b - 4 * a * c;

                if (discriminant >= 0) {
                    float dst = (-b - sqrt(discriminant)) / (2 * a);
                    if (dst >= 0) {
                        hitInfo.didHit = true;
                        hitInfo.dst = dst;
                        hitInfo.hitPoint = ray.origin + ray.dir * dst;
                        hitInfo.normal = normalize(hitInfo.hitPoint - sphereCentre);
                    }
                }
                return hitInfo;
            }

            HitInfo RayTriangle(Ray ray, Triangle tri)
            {
                float3 edgeAB = tri.posB - tri.posA;
                float3 edgeAC = tri.posC - tri.posA;
                float3 normalVector = cross(edgeAB, edgeAC);
                float3 ao = ray.origin - tri.posA;
                float3 dao = cross(ao, ray.dir);

                float determinant = -dot(ray.dir, normalVector);
                float invDet = 1 / determinant;

                float dst = dot(ao, normalVector) * invDet;
                float u = dot(edgeAC, dao) * invDet;
                float v = -dot(edgeAB, dao) * invDet;
                float w = 1 - u - v;

                HitInfo hitInfo;
                hitInfo.didHit = determinant >= 1E-6 && dst >= 0 && u >= 0 && v >= 0 && w >= 0;
                hitInfo.hitPoint = ray.origin + ray.dir * dst;
                hitInfo.normal = normalize(tri.normalA * w + tri.normalB * u + tri.normalC * v);
                hitInfo.dst = dst;
                return hitInfo;
            }

            HitInfo CalculateRayCollision(Ray ray)
            {
                HitInfo closestHit = (HitInfo)0;
                closestHit.dst = 1.#INF;

                for (int i = 0; i < NumSpheres; i ++)
                {
                    Sphere sphere = Spheres[i];
                    HitInfo hitInfo = RaySphere(ray, sphere.position, sphere.radius);
                    if (hitInfo.didHit && hitInfo.dst < closestHit.dst)
                    {
                        closestHit = hitInfo;
                        closestHit.material = sphere.material;
                    }
                }

                for (int meshIndex = 0; meshIndex < NumMeshes; meshIndex ++)
                {
                    MeshInfo meshInfo = AllMeshInfo[meshIndex];

                    for (uint i = 0; i < meshInfo.numTriangles; i ++) {
                        int triIndex = meshInfo.firstTriangleIndex + i;
                        Triangle tri = Triangles[triIndex];
                        HitInfo hitInfo = RayTriangle(ray, tri);

                        if (hitInfo.didHit && hitInfo.dst < closestHit.dst)
                        {
                            closestHit = hitInfo;
                            closestHit.material = meshInfo.material;
                        }
                    }
                }
                return closestHit;
            }

            // --- Iluminação Global ---
            
            // Função para calcular sombras suaves
            float CalculateSoftShadow(float3 hitPoint, float3 lightPos, float lightRadius)
            {
                float3 lightDir = lightPos - hitPoint;
                float lightDistance = length(lightDir);
                lightDir /= lightDistance;
                
                float shadowFactor = 1.0;
                int numShadowRays = 4; // Número de raios para sombras suaves (reduzido para performance)
                
                for (int i = 0; i < numShadowRays; i++)
                {
                    // Gerar posição aleatória na esfera de luz
                    float theta = (float)i / numShadowRays * 6.28318; // 2*PI
                    float phi = 0.5 + 0.5 * sin(theta); // Variação simples
                    
                    float3 randomOffset = float3(
                        cos(theta) * sin(phi),
                        sin(theta) * sin(phi),
                        cos(phi)
                    ) * lightRadius * 0.5;
                    
                    float3 sampleLightPos = lightPos + randomOffset;
                    float3 sampleLightDir = normalize(sampleLightPos - hitPoint);
                    
                    Ray shadowRay = { hitPoint + lightDir * 0.001, sampleLightDir };
                    HitInfo shadowHit = CalculateRayCollision(shadowRay);
                    
                    float sampleDistance = length(sampleLightPos - hitPoint);
                    if (shadowHit.didHit && shadowHit.dst < sampleDistance - 0.001)
                    {
                        shadowFactor -= 1.0 / numShadowRays;
                    }
                }
                
                return max(0.0, shadowFactor);
            }
            
            float3 CalculateDirectLighting(HitInfo hitInfo, float3 viewDir)
            {
                float3 totalLight = float3(0, 0, 0);
                float3 ambientColour = float3(0.05, 0.05, 0.1);
                
                totalLight += hitInfo.material.colour.rgb * ambientColour;
                
                float3 lightDir = normalize(_LightDirection);
                float3 hitPointWithOffset = hitInfo.hitPoint + hitInfo.normal * 0.001;
                Ray shadowRay = { hitPointWithOffset, lightDir };
                HitInfo shadowHit = CalculateRayCollision(shadowRay);
                
                if (!shadowHit.didHit)
                {
                    float3 lightColour = float3(1, 1, 1) * _DirectionalLightIntensity;
                    
                    // Difuso suavizado
                    float diffuseFactor = max(0, dot(hitInfo.normal, lightDir));
                    diffuseFactor = smoothstep(0.0, 1.0, diffuseFactor);
                    totalLight += hitInfo.material.colour.rgb * lightColour * diffuseFactor;
                    
                    // Especular suavizado
                    float3 reflectDir = reflect(-lightDir, hitInfo.normal);
                    float specularFactor = max(0, dot(viewDir, reflectDir));
                    specularFactor = pow(specularFactor, hitInfo.material.smoothness * 128 + 1);
                    specularFactor = smoothstep(0.0, 1.0, specularFactor);
                    totalLight += hitInfo.material.specularColour.rgb * lightColour * specularFactor * hitInfo.material.specularProbability;
                }
                
                for (int i = 0; i < NumSpheres; i++)
                {
                    Sphere sphere = Spheres[i];
                    if (sphere.material.emissionStrength > 0)
                    {
                        float3 lightPos = sphere.position;
                        float3 lightToHit = hitInfo.hitPoint - lightPos;
                        float distance = length(lightToHit);
                        float3 lightDirection = lightToHit / distance;
                        
                        // Usar sombras suaves para esferas emissivas
                        float shadowFactor = CalculateSoftShadow(hitInfo.hitPoint, lightPos, sphere.radius);
                        
                        if (shadowFactor > 0.0)
                        {
                            // Atenuação mais suave baseada na distância
                            float normalizedDistance = distance / (sphere.radius * 10.0); // Normalizar pela esfera
                            float smoothAttenuation = 1.0 / (1.0 + 0.05 * normalizedDistance + 0.005 * normalizedDistance * normalizedDistance);
                            smoothAttenuation = smoothstep(0.0, 1.0, smoothAttenuation); // Suavização adicional
                            
                            float3 emittedLight = sphere.material.emissionColour.rgb * sphere.material.emissionStrength * smoothAttenuation * shadowFactor;
                            
                            // Difuso com suavização
                            float diffuseFactor = max(0, dot(hitInfo.normal, -lightDirection));
                            diffuseFactor = smoothstep(0.0, 1.0, diffuseFactor); // Suavizar transição difusa
                            totalLight += hitInfo.material.colour.rgb * emittedLight * diffuseFactor;
                            
                            // Especular com suavização
                            float3 reflectDir = reflect(lightDirection, hitInfo.normal);
                            float specularFactor = max(0, dot(viewDir, reflectDir));
                            specularFactor = pow(specularFactor, hitInfo.material.smoothness * 128 + 1); // +1 para evitar divisão por zero
                            specularFactor = smoothstep(0.0, 1.0, specularFactor); // Suavizar especular
                            totalLight += hitInfo.material.specularColour.rgb * emittedLight * specularFactor * hitInfo.material.specularProbability;
                        }
                    }
                }
                
                for (int meshIndex = 0; meshIndex < NumMeshes; meshIndex++)
                {
                    MeshInfo meshInfo = AllMeshInfo[meshIndex];
                    if (meshInfo.material.emissionStrength > 0)
                    {
                        // Usar o centro da bounding box como aproximação da posição da mesh emissiva
                        float3 lightPos = 0.5 * (meshInfo.boundsMin + meshInfo.boundsMax);
                        float3 lightToHit = hitInfo.hitPoint - lightPos;
                        float distance = length(lightToHit);
                        float3 lightDirection = lightToHit / distance;

                        // Verificação simples de oclusão (sem bounding box)
                        Ray lightRay = { lightPos + lightDirection * 0.001, lightDirection };
                        HitInfo lightHit = CalculateRayCollision(lightRay);

                        if (!lightHit.didHit || lightHit.dst >= distance - 0.001)
                        {
                            // Atenuação suave para meshes
                            float meshSize = length(meshInfo.boundsMax - meshInfo.boundsMin);
                            float normalizedDistance = distance / (meshSize * 2.0);
                            float smoothAttenuation = 1.0 / (1.0 + 0.03 * normalizedDistance + 0.003 * normalizedDistance * normalizedDistance);
                            smoothAttenuation = smoothstep(0.0, 1.0, smoothAttenuation);
                            
                            float3 emittedLight = meshInfo.material.emissionColour.rgb * meshInfo.material.emissionStrength * smoothAttenuation;

                            // Difuso suavizado
                            float diffuseFactor = max(0, dot(hitInfo.normal, -lightDirection));
                            diffuseFactor = smoothstep(0.0, 1.0, diffuseFactor);
                            totalLight += hitInfo.material.colour.rgb * emittedLight * diffuseFactor;

                            // Especular suavizado
                            float3 reflectDir = reflect(lightDirection, hitInfo.normal);
                            float specularFactor = max(0, dot(viewDir, reflectDir));
                            specularFactor = pow(specularFactor, hitInfo.material.smoothness * 128 + 1);
                            specularFactor = smoothstep(0.0, 1.0, specularFactor);
                            totalLight += hitInfo.material.specularColour.rgb * emittedLight * specularFactor * hitInfo.material.specularProbability;
                        }
                    }
                }
                
                return totalLight;
            }

            // --- Fragment Shader ---
            
            // Função para suavizar cores (tone mapping)
            float3 ToneMap(float3 color)
            {
                // ACES tone mapping simplificado para suavizar cores brilhantes
                float3 a = 2.51 * color;
                float3 b = 0.03 + color * (0.59 + color * 0.14);
                return saturate((a * color) / (b + color));
            }

            float4 frag (v2f i) : SV_Target
            {
                Ray ray;
                ray.origin = _WorldSpaceCameraPos;

                // Calcular direção do raio inicial
                float3 focusPointLocal = float3(i.uv - 0.5, 1) * ViewParams;
                float3 focusPoint = mul(CamLocalToWorldMatrix, float4(focusPointLocal, 1));
                float3 initialRayDir = normalize(focusPoint - ray.origin);
                
                // Aplicar curvatura hiperbólica
                ray.dir = ApplyHyperbolicCurvature(initialRayDir, i.uv);

                HitInfo hitInfo = CalculateRayCollision(ray);

                if (hitInfo.didHit)
                {
                    RayTracingMaterial material = hitInfo.material;
                    
                    float3 finalColour = material.emissionColour.rgb * material.emissionStrength;
                    
                    if (material.emissionStrength <= 1.0)
                    {
                        float3 viewDir = normalize(ray.origin - hitInfo.hitPoint);
                        finalColour += CalculateDirectLighting(hitInfo, viewDir);
                    }

                    // Aplicar tone mapping para suavizar as cores
                    finalColour = ToneMap(finalColour);
                    
                    return float4(finalColour, 1.0);
                }
                else
                {
                    // Gradiente suave para o céu
                    float skyGradient = smoothstep(-0.5, 0.5, ray.dir.y);
                    float3 skyColor = lerp(float3(0.05, 0.1, 0.2), float3(0.1, 0.3, 0.6), skyGradient);
                    return float4(skyColor, 1.0);
                }
            }

            ENDCG
        }
    }
}