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
            int _UsePointMode;
            float _StepSize;
            int _MaxSteps;

            int _Metric;
            int _Integrator;
            float _SpinSpeed;

            // Constantes adicionais para Kerr (baseadas no seu shader.comp)
            static const float KERR_SPIN_AMOUNT = 1.0; // Ajuste conforme a escala do seu mundo
            static const float3 KERR_SPIN_AXIS = float3(0, 1, 0);

            // --- CONSTANTES REAIS (SI) ---
            // Cuidado: float tem pouca precisão para esses números extremos sem normalização
            static const float G = 6.67430e-11;
            static const float C = 299792458.0;

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

            // --- Função de Aceleração Gravitacional ---
            float3 GetGravityAccel(float3 pos, float3 v, Sphere s)
            {
                float3 toSphere = s.position - pos;
                float r_dist = length(toSphere);
                if (r_dist < 0.1) return float3(0, 0, 0);

                float r_dist2 = r_dist * r_dist;
                float r_dist3 = r_dist2 * r_dist;
                float r_dist5 = r_dist3 * r_dist2;
                float cSq = C * C;
                float Rs = (2.0 * G * s.massa) / cSq;

                if (_Metric == 0) // Newton
                {
                    return toSphere * (G * s.massa) / r_dist3;
                }
                else if (_Metric == 1) // Schwarzschild
                {
                    float3 h_vec = cross(-toSphere, v);
                    float h2 = dot(h_vec, h_vec);
                    return toSphere * (1.5 * Rs * h2) / r_dist5;
                }
                else // Kerr (Métrica de Buraco Negro em Rotação)
                {
                    float3 r_vec = -toSphere;
                    float3 h_vec = cross(r_vec, v);
                    float h2 = dot(h_vec, h_vec);
        
                    float3 a_schwarz = -r_vec * (1.5 * Rs * h2) / r_dist5;
        
                    // Frame Dragging (Lense-Thirring)
                    float3 spin_vec = KERR_SPIN_AXIS * Rs * _SpinSpeed;
                    float3 H = (2.0 / r_dist5) * (3.0 * r_vec * dot(spin_vec, r_vec) - spin_vec * r_dist2);
                    float3 a_frame_drag = cross(v, H);
        
                    return a_schwarz + a_frame_drag;
                }
            }

            // --- Novos Métodos de Integração ---
            void StepEuler(inout float3 origin, inout float3 velocity, float dt, Sphere s)
            {
                float3 accel = GetGravityAccel(origin, velocity, s);
                velocity = normalize(velocity + accel * dt) * C;
                origin += velocity * dt;
            }

            void StepRK4(inout float3 origin, inout float3 velocity, float dt, Sphere s)
            {
                float3 p = origin;
                float3 v = velocity;

                // k1
                float3 k1_p = v;
                float3 k1_v = GetGravityAccel(p, v, s);

                // k2
                float3 k2_p = v + 0.5 * dt * k1_v;
                float3 k2_v = GetGravityAccel(p + 0.5 * dt * k1_p, v + 0.5 * dt * k1_v, s);

                // k3
                float3 k3_p = v + 0.5 * dt * k2_v;
                float3 k3_v = GetGravityAccel(p + 0.5 * dt * k2_p, v + 0.5 * dt * k2_v, s);

                // k4
                float3 k4_p = v + dt * k3_v;
                float3 k4_v = GetGravityAccel(p + dt * k3_p, v + dt * k3_v, s);

                origin += (dt / 6.0) * (k1_p + 2.0 * k2_p + 2.0 * k3_p + k4_p);
                float3 new_v = v + (dt / 6.0) * (k1_v + 2.0 * k2_v + 2.0 * k3_v + k4_v);
                velocity = normalize(new_v) * C;
            }

            HitInfo ApplyRelativisticEffects(float3 initialRayDir)
            {
                if (_UseHyperbolicView == 0) 
                { 
                    Ray straightRay; 
                    straightRay.origin = _WorldSpaceCameraPos;  
                    straightRay.dir = initialRayDir; 
         
                    return CalculateRayCollision(straightRay); 
                }

                float3 currentPos = _WorldSpaceCameraPos;
                float3 currentVelocity = initialRayDir * C;
                float dt = _StepSize / C;

                for (int step = 0; step < _MaxSteps; step++)
                {
                    // Check Colisão
                    Ray checkRay = { currentPos, normalize(currentVelocity) };
                    HitInfo hitInfo = CalculateRayCollision(checkRay);
                    if (hitInfo.didHit && hitInfo.dst <= _StepSize) return hitInfo;

                    // Atualmente o shader suporta múltiplas esferas, 
                    // mas a física relativística geralmente foca na mais massiva (index 0)
                    Sphere s = Spheres[0]; 
        
                    if (_Integrator == 1) // RK4
                        StepRK4(currentPos, currentVelocity, dt, s);
                    else // Euler
                        StepEuler(currentPos, currentVelocity, dt, s);

                    // Horizonte de eventos (escape antecipado)
                    if (length(currentPos - s.position) < s.radius * 1.01) { 
                        HitInfo black = (HitInfo)0; 
                         
                        black.didHit = true; 
                        black.dst = 0.0; 
                        black.material.colour = float4(0, 0, 0, 1);  
                        black.material.emissionStrength = 0; 

                        return black;
                    }
                }
                
                HitInfo missInfo;
                missInfo.didHit = false;
                return missInfo;
            }

            // --- Iluminação Global (Inalterada mas usando calculateRayCollision padrão) ---
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
                
                // Luz emitida por esferas (Pode ser caro em loops grandes, simplificado aqui)
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

                if (_UsePointMode == 1)
                {
                    float2 center = float2(0.5, 0.5);
                    float2 pixelSize = float2(1.0 / _ScreenParams.x, 1.0 / _ScreenParams.y);
                    if (abs(i.uv.x - center.x) > pixelSize.x || abs(i.uv.y - center.y) > pixelSize.y)
                    { return float4(0,0,0,1); }
                }

                HitInfo hitInfo = ApplyRelativisticEffects(initialRayDir);

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
                    float skyGradient = smoothstep(-0.5, 0.5, initialRayDir.y);
                    float3 skyColor = lerp(float3(0.05, 0.1, 0.2), float3(0.1, 0.3, 0.6), skyGradient);
                    return float4(skyColor, 1.0);
                }
            }
            ENDCG
        }
    }
}