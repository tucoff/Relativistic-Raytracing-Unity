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

            struct HitInfo
            {
                bool didHit;
                float dst;
                float3 hitPoint;
                float3 normal;
                float3 colour;
            };

            struct SceneConfig
            {
                float3 spherePos;
                float sphereRadius;
                float sphereMass;
                float3 sphere2Pos;
                float sphere2Radius;
                float sphere2Mass;
                bool hasRing;
                bool useUniverse;
            };

            // --- Parâmetros de Câmera e Controle ---
            float3 ViewParams;
            float4x4 CamLocalToWorldMatrix;
            int _UseHyperbolicView;
            int _UsePointMode;
            float _StepSize;
            int _MaxSteps;

            int _Metric;
            int _Integrator;
            float _SpinSpeed;

            // --- Scene Control ---
            int _CurrentScene;

            // --- CONSTANTES REAIS (SI) ---
            static const float G_REAL = 6.67430e-11;
            static const float C_REAL = 299792458.0;
            static const float SOLAR_MASS = 1.989e30;
            static const float MASS = 10.0 * SOLAR_MASS;
            static const float RS_KM = (2.0 * G_REAL * MASS) / (C_REAL * C_REAL) / 1000.0;

            // --- Configurações da Esfera Primária ---
            static const float3 SPHERE_POS = float3(0.0, 0.0, -150.0);
            static const float SPHERE_RADIUS = RS_KM;
            static const float SPHERE_MASS = MASS;

            // --- Configurações do Anel de Acrição ---
            static const float3 RING_NORMAL = normalize(float3(0.3, 1.0, 0.3));
            static const float RING_INNER = RS_KM * 4.0;
            static const float RING_OUTER = RS_KM * 7.0;

            // --- Configurações de Kerr ---
            static const float3 KERR_SPIN_AXIS = normalize(float3(0.0, 1.0, 0.0));
            static const float KERR_SPIN_AMOUNT = RS_KM;

            // --- Variáveis Dinâmicas (Configuradas por Cena) ---
            float3 _SpherePos;
            float _SphereRadius;
            float _SphereMass;
            float3 _Sphere2Pos;
            float _Sphere2Radius;
            float _Sphere2Mass;
            int _HasRing;
            int _UseUniverseSkybox;

            // --- Função de Carregamento de Cena ---
            void LoadSceneConfig()
            {
                // Cena 1: Buraco Negro com fundo colorido
                if (_CurrentScene == 1)
                {
                    _SpherePos = float3(0.0, 0.0, -150.0);
                    _SphereRadius = RS_KM;
                    _SphereMass = MASS;
                    _HasRing = 0;
                    _UseUniverseSkybox = 0;
                }
                // Cena 2: Buraco Negro com skybox do universo
                else if (_CurrentScene == 2)
                {
                    _SpherePos = float3(0.0, 0.0, -150.0);
                    _SphereRadius = RS_KM;
                    _SphereMass = MASS;
                    _HasRing = 0;
                    _UseUniverseSkybox = 1;
                    // TODO: Implementar skybox do universo
                }
                // Cena 3: Buraco Negro com skybox e disco de acrição
                else if (_CurrentScene == 3)
                {
                    _SpherePos = float3(0.0, 0.0, -150.0);
                    _SphereRadius = RS_KM;
                    _SphereMass = MASS;
                    _HasRing = 1;
                    _UseUniverseSkybox = 1;
                    // TODO: Implementar skybox do universo
                }
                // Cena 4: Dois Buracos Negros com fundo colorido
                else if (_CurrentScene == 4)
                {
                    _SpherePos = float3(-50.0, 0.0, -150.0);
                    _SphereRadius = RS_KM;
                    _SphereMass = MASS;
                    _Sphere2Pos = float3(50.0, 0.0, -150.0);
                    _Sphere2Radius = RS_KM;
                    _Sphere2Mass = MASS;
                    _HasRing = 0;
                    _UseUniverseSkybox = 0;
                }
                // Cena 5: Dois Buracos Negros com skybox do universo
                else if (_CurrentScene == 5)
                {
                    _SpherePos = float3(-50.0, 0.0, -150.0);
                    _SphereRadius = RS_KM;
                    _SphereMass = MASS;
                    _Sphere2Pos = float3(50.0, 0.0, -150.0);
                    _Sphere2Radius = RS_KM;
                    _Sphere2Mass = MASS;
                    _HasRing = 0;
                    _UseUniverseSkybox = 1;
                    // TODO: Implementar skybox do universo
                }
                // Cena 6: Eclipse de Einstein
                else if (_CurrentScene == 6)
                {
                    _SpherePos = float3(0.0, 0.0, -150.0);
                    _SphereRadius = RS_KM * 2.0;
                    _SphereMass = MASS * 2.0;
                    _Sphere2Pos = float3(15.0, 0.0, -100.0);
                    _Sphere2Radius = RS_KM * 0.5;
                    _Sphere2Mass = 0.0;
                    _HasRing = 0;
                    _UseUniverseSkybox = 1;
                    // TODO: Implementar skybox customizado com uma única estrela
                }
                // Cena padrão
                else
                {
                    _SpherePos = SPHERE_POS;
                    _SphereRadius = SPHERE_RADIUS;
                    _SphereMass = SPHERE_MASS;
                    _HasRing = 0;
                    _UseUniverseSkybox = 0;
                }
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

            bool IntersectPlane(float3 planeNormal, float3 planePoint, Ray ray, out float t)
            {
                float denom = dot(planeNormal, ray.dir);
                if (abs(denom) > 1e-6) {
                    float3 p0l0 = planePoint - ray.origin;
                    t = dot(p0l0, planeNormal) / denom;
                    return (t >= 0.0);
                }
                return false;
            }

            bool HitRing(float3 center, float3 normal, float innerRadius, float outerRadius, Ray ray, out float t_hit)
            {
                if (IntersectPlane(normal, center, ray, t_hit)) {
                    float3 p = ray.origin + ray.dir * t_hit;
                    float3 v = p - center;
                    float d2 = dot(v, v);
                    return (d2 <= outerRadius * outerRadius && d2 >= innerRadius * innerRadius);
                }
                return false;
            }

            HitInfo CalculateRayCollision(Ray ray)
            {
                HitInfo closestHit = (HitInfo)0;
                closestHit.dst = 1e10;

                // --- Colisão com a Esfera Primária ---
                HitInfo sphereHit = RaySphere(ray, _SpherePos, _SphereRadius);
                if (sphereHit.didHit && sphereHit.dst < closestHit.dst)
                {
                    closestHit = sphereHit;
                    closestHit.colour = float3(0, 0, 0);
                    if (_UseHyperbolicView == 0) closestHit.colour = float3(0.74, 0.74, 0.74);
                }

                // --- Colisão com Segunda Esfera (se existir) ---
                if (_CurrentScene == 4 || _CurrentScene == 5 || _CurrentScene == 6)
                {
                    HitInfo sphere2Hit = RaySphere(ray, _Sphere2Pos, _Sphere2Radius);
                    if (sphere2Hit.didHit && sphere2Hit.dst < closestHit.dst)
                    {
                        closestHit = sphere2Hit;
                        closestHit.colour = float3(0, 0, 0);
                        if (_UseHyperbolicView == 0) closestHit.colour = float3(0.74, 0.74, 0.74);
                    }
                }

                // --- Colisão com o Anel de Acrição ---
                if (_HasRing == 1)
                {
                    float t_ring;
                    if (HitRing(_SpherePos, RING_NORMAL, RING_INNER, RING_OUTER, ray, t_ring))
                    {
                        if (t_ring < closestHit.dst)
                        {
                            closestHit.didHit = true;
                            closestHit.dst = t_ring;
                            closestHit.hitPoint = ray.origin + ray.dir * t_ring;
                            closestHit.colour = float3(1, 1, 1);
                        }
                    }
                }

                return closestHit;
            }

            // --- Função de Aceleração Gravitacional ---
            float3 GetGravityAccel(float3 pos, float3 v)
            {
                float3 toSphere = _SpherePos - pos;
                float r_dist = length(toSphere);
                if (r_dist < 0.0001) return float3(0, 0, 0);

                float r_dist2 = r_dist * r_dist;
                float r_dist3 = r_dist2 * r_dist;
                float r_dist5 = r_dist3 * r_dist2;

                float3 accel = float3(0, 0, 0);

                if (_Metric == 0) // Newton: a = (GM / r^3) * r_vector
                {
                    accel = toSphere * (RS_KM * 0.5) / r_dist3;
                }
                else if (_Metric == 1) // Schwarzschild: a = 1.5 * Rs * |r x v|^2 / r^5 * (center - pos)
                {
                    float3 h_vec = cross(-toSphere, v);
                    float h2 = dot(h_vec, h_vec);
                    accel = toSphere * (1.5 * RS_KM * h2) / r_dist5;
                }
                else // Kerr (Métrica de Buraco Negro em Rotação)
                {
                    float3 r_vec = -toSphere;
                    float3 h_vec = cross(r_vec, v);
                    float h2 = dot(h_vec, h_vec);
        
                    float3 a_schwarzschild = -r_vec * (1.5 * RS_KM * h2) / r_dist5;
        
                    // Frame Dragging (Lense-Thirring)
                    float3 spin_vec = KERR_SPIN_AXIS * KERR_SPIN_AMOUNT * _SpinSpeed;
                    float3 H = (2.0 / r_dist5) * (3.0 * r_vec * dot(spin_vec, r_vec) - spin_vec * r_dist2);
                    float3 a_frame_drag = cross(v, H);
        
                    accel = a_schwarzschild + a_frame_drag;
                }

                // Adiciona influência de segunda esfera se existir
                if (_CurrentScene == 4 || _CurrentScene == 5 || _CurrentScene == 6)
                {
                    float3 toSphere2 = _Sphere2Pos - pos;
                    float r2_dist = length(toSphere2);
                    if (r2_dist > 0.0001)
                    {
                        float r2_dist2 = r2_dist * r2_dist;
                        float r2_dist3 = r2_dist2 * r2_dist;
                        accel += toSphere2 * (RS_KM * 0.5) / r2_dist3;
                    }
                }

                return accel;
            }

            // --- Novos Métodos de Integração ---
            void StepEuler(inout float3 origin, inout float3 velocity, float dt)
            {
                float3 accel = GetGravityAccel(origin, velocity);
                velocity += accel * dt;
                origin += velocity * dt;
            }

            void StepRK4(inout float3 origin, inout float3 velocity, float dt)
            {
                float3 p = origin;
                float3 v = velocity;

                // k1
                float3 k1_p = v;
                float3 k1_v = GetGravityAccel(p, v);

                // k2
                float3 k2_p = v + 0.5 * dt * k1_v;
                float3 k2_v = GetGravityAccel(p + 0.5 * dt * k1_p, v + 0.5 * dt * k1_v);

                // k3
                float3 k3_p = v + 0.5 * dt * k2_v;
                float3 k3_v = GetGravityAccel(p + 0.5 * dt * k2_p, v + 0.5 * dt * k2_v);

                // k4
                float3 k4_p = v + dt * k3_v;
                float3 k4_v = GetGravityAccel(p + dt * k3_p, v + dt * k3_v);

                origin += (dt / 6.0) * (k1_p + 2.0 * k2_p + 2.0 * k3_p + k4_p);
                float3 new_velocity = v + (dt / 6.0) * (k1_v + 2.0 * k2_v + 2.0 * k3_v + k4_v);
                
                // Normalize at the very end to maintain light speed c=1
                velocity = normalize(new_velocity);
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

                Ray ray;
                ray.origin = _WorldSpaceCameraPos;
                ray.dir = normalize(initialRayDir);

                for (int step = 0; step < _MaxSteps; step++)
                {
                    HitInfo hitInfo = CalculateRayCollision(ray);
                    
                    if (hitInfo.didHit && hitInfo.dst <= _StepSize)
                    {
                        return hitInfo;
                    }
                    
                    if (length(_SpherePos - ray.origin) < _SphereRadius)
                    {
                        HitInfo black = (HitInfo)0;
                        black.didHit = true;
                        black.dst = 0.0;
                        black.colour = float3(0, 0, 0);
                        return black;
                    }
                    
                    if (_Integrator == 1) // RK4
                        StepRK4(ray.origin, ray.dir, _StepSize);
                    else // Euler
                        StepEuler(ray.origin, ray.dir, _StepSize);
                    
                    if (length(ray.origin - _WorldSpaceCameraPos) > 2000.0) break;
                }
                
                HitInfo missInfo = (HitInfo)0;
                missInfo.didHit = false;
                return missInfo;
            }

            // --- Iluminação Global (Inalterada mas usando calculateRayCollision padrão) ---
            float3 GetSkyColor(float3 direction)
            {
                float3 unitDir = normalize(direction);
                if (unitDir.x < 0 && unitDir.y > 0) return float3(1, 1, 0);
                else if (unitDir.x >= 0 && unitDir.y > 0) return float3(1, 0, 0);
                else if (unitDir.x < 0 && unitDir.y < 0) return float3(0, 1, 0);
                else return float3(0, 0, 1);
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
                // Carrega configuração da cena no início do fragment 
                LoadSceneConfig();

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
                float3 finalColour = float3(0, 0, 0);

                if (hitInfo.didHit)
                {
                    finalColour = hitInfo.colour;
                }
                else
                {
                    finalColour = GetSkyColor(initialRayDir);
                }
                
                return float4(finalColour, 1.0);
            }
            ENDCG
        }
    }
}