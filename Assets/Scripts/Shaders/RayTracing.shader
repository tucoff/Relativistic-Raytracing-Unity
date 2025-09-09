Shader "Custom/RayTracingRelativistic"
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
            int _UseHyperbolicView;
            float _StepSize;
            int _MaxSteps;

            // Constante gravitacional exagerada para efeitos visíveis
            #define G 1000000.0

            // --- Funções de Interseção de Raio ---
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

            // Função de curvatura hiperbólica estabilizada
            HitInfo ApplyHyperbolicCurvatureExaggerated(float3 initialRayDir, float2 screenPos)
            {
                if (_UseHyperbolicView == 0) 
                {
                    Ray straightRay;
                    straightRay.origin = _WorldSpaceCameraPos;
                    straightRay.dir = initialRayDir;
                    return CalculateRayCollision(straightRay);
                }
                
                Ray curvedRay;
                curvedRay.origin = _WorldSpaceCameraPos;
                curvedRay.dir = initialRayDir;
                float totalDistanceTraveled = 0.0;

                for (int step = 0; step < _MaxSteps; step++)
                {
                    // Primeiro, aplicar deflexão gravitacional
                    float3 totalDeflection = float3(0, 0, 0);
                        
                    for (int i = 0; i < NumSpheres; i++)
                    {
                        Sphere sphere = Spheres[i];
                        if (sphere.massa <= 0) continue;
                        
                        float3 toSphere = sphere.position - curvedRay.origin;
                        float distance = length(toSphere);
                        
                        // Evitar divisão por zero ou valores muito pequenos
                        if (distance < 0.1) continue;
                        
                        float3 direction = toSphere / distance;
                        
                        // Fórmula gravitacional estabilizada
                        // Usa uma força inversamente proporcional ao quadrado da distância
                        float deflectionStrength = G * sphere.massa / (distance * distance);
                        
                        // A deflexão é na direção da esfera (fisicamente correto)
                        totalDeflection += direction * deflectionStrength;
                    }
                    
                    // Aplicar deflexão de forma suave
                    if (length(totalDeflection) > 0)
                    {
                        // Normalizar a deflexão total para evitar mudanças bruscas
                        float deflectionMagnitude = length(totalDeflection);
                        float3 deflectionDir = totalDeflection / deflectionMagnitude;
                        
                        float smoothDeflection = deflectionMagnitude * _StepSize;
                        curvedRay.dir = normalize(curvedRay.dir + deflectionDir * smoothDeflection);
                    }
                    
                    // Avançar o raio
                    curvedRay.origin += curvedRay.dir * _StepSize;
                    totalDistanceTraveled += _StepSize;
                    
                    // DEPOIS de aplicar a deflexão, verificar colisão
                    HitInfo hitInfo = CalculateRayCollision(curvedRay);
                    if (hitInfo.didHit)
                    {
                        // Adicionar a distância já percorrida nos passos anteriores
                        hitInfo.dst = totalDistanceTraveled + hitInfo.dst;
                        return hitInfo;
                    }
                }
                
                HitInfo missInfo;
                missInfo.didHit = false;
                return missInfo;
            }

            // --- Iluminação Global ---
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
                    float diffuseFactor = max(0, dot(hitInfo.normal, lightDir));
                    totalLight += hitInfo.material.colour.rgb * lightColour * diffuseFactor;
                    
                    float3 reflectDir = reflect(-lightDir, hitInfo.normal);
                    float specularFactor = pow(max(0, dot(viewDir, reflectDir)), hitInfo.material.smoothness * 128 + 1);
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
                        
                        Ray lightRay = { lightPos + lightDirection * 0.001, lightDirection };
                        HitInfo lightHit = CalculateRayCollision(lightRay);
                        
                        if (!lightHit.didHit || lightHit.dst >= distance - 0.001)
                        {
                            float attenuation = 1.0 / (1.0 + 0.1 * distance + 0.01 * distance * distance);
                            float3 emittedLight = sphere.material.emissionColour.rgb * sphere.material.emissionStrength * attenuation;
                            
                            float diffuseFactor = max(0, dot(hitInfo.normal, -lightDirection));
                            totalLight += hitInfo.material.colour.rgb * emittedLight * diffuseFactor;
                            
                            float3 reflectDir = reflect(lightDirection, hitInfo.normal);
                            float specularFactor = pow(max(0, dot(viewDir, reflectDir)), hitInfo.material.smoothness * 128 + 1);
                            totalLight += hitInfo.material.specularColour.rgb * emittedLight * specularFactor * hitInfo.material.specularProbability;
                        }
                    }
                }
                
                return totalLight;
            }

            // --- Fragment Shader ---
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float3 focusPointLocal = float3(i.uv - 0.5, 1) * ViewParams;
                float3 focusPoint = mul(CamLocalToWorldMatrix, float4(focusPointLocal, 1));
                float3 initialRayDir = normalize(focusPoint - _WorldSpaceCameraPos);
                                
                //float2 center = float2(0.5, 0.5);
                //float2 pixelSize = float2(1.0 / _ScreenParams.x, 1.0 / _ScreenParams.y);
                
                //if (abs(i.uv.x - center.x) > pixelSize.x || abs(i.uv.y - center.y) > pixelSize.y)
                //{
                //    return float4(0,0,0,1); 
                //}

                // Aplicar curvatura exagerada
                HitInfo hitInfo = ApplyHyperbolicCurvatureExaggerated(initialRayDir, i.uv);

                if (hitInfo.didHit)
                {
                    RayTracingMaterial material = hitInfo.material;
                    float3 finalColour = material.emissionColour.rgb * material.emissionStrength;
                    
                    if (material.emissionStrength <= 1.0)
                    {
                        float3 viewDir = normalize(_WorldSpaceCameraPos - hitInfo.hitPoint);
                        finalColour += CalculateDirectLighting(hitInfo, viewDir);
                    }
                    
                    return float4(finalColour, 1.0);
                }
                else
                {
                    // Fundo com gradiente
                    float skyGradient = smoothstep(-0.5, 0.5, initialRayDir.y);
                    float3 skyColor = lerp(float3(0.05, 0.1, 0.2), float3(0.1, 0.3, 0.6), skyGradient);
                    return float4(skyColor, 1.0);
                }

            }
            ENDCG
        }
    }
}