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
                int bodyIndex;
            };

            float3 ViewParams;
            float4x4 CamLocalToWorldMatrix;
            int _UseHyperbolicView;
            int _UsePointMode;
            float _StepSize;
            float _GravityMultiplier;
            int _MaxSteps;

            int _Metric;
            int _Integrator;
            float _SpinSpeed;
            int _CurrentScene;

            samplerCUBE _SkyboxTexture;
            samplerCUBE _MilkyWayTex;
            int _UseMilkyWay;

            float4 _Bodies[10];
            float _BodyMasses[10];
            sampler2D _PlanetTex0; sampler2D _PlanetTex1; sampler2D _PlanetTex2; sampler2D _PlanetTex3; sampler2D _PlanetTex4;
            sampler2D _PlanetTex5; sampler2D _PlanetTex6; sampler2D _PlanetTex7; sampler2D _PlanetTex8; sampler2D _PlanetTex9;

            static const float G_REAL = 6.67430e-11;
            static const float C_REAL = 299792458.0;
            static const float SOLAR_MASS = 1.989e30;
            static const float MASS = 10.0 * SOLAR_MASS;
            static const float RS_KM = (2.0 * G_REAL * MASS) / (C_REAL * C_REAL) / 1000.0;

            static const float3 SPHERE_POS = float3(0.0, 0.0, -150.0);
            static const float SPHERE_RADIUS = RS_KM;
            static const float SPHERE_MASS = MASS;

            static const float3 RING_NORMAL = normalize(float3(0.3, 1.0, 0.3));
            static const float RING_INNER = RS_KM * 4.0;
            static const float RING_OUTER = RS_KM * 7.0;

            static const float3 KERR_SPIN_AXIS = normalize(float3(0.0, 1.0, 0.0));
            static const float KERR_SPIN_AMOUNT = RS_KM;

            float3 _SpherePos;
            float _SphereRadius;
            float _SphereMass;
            float3 _Sphere2Pos;
            float _Sphere2Radius;
            float _Sphere2Mass;
            int _HasRing;
            int _UseUniverseSkybox;

            void LoadSceneConfig()
            {
                _SpherePos = SPHERE_POS;
                _SphereRadius = SPHERE_RADIUS;
                _SphereMass = SPHERE_MASS;
                _Sphere2Pos = float3(0.0, 0.0, 0.0);
                _Sphere2Radius = 0.0;
                _Sphere2Mass = 0.0;
                _HasRing = 0;
                _UseUniverseSkybox = 0;

                if (_CurrentScene == 1)
                {
                    _SpherePos = float3(0.0, 0.0, -150.0);
                    _SphereRadius = RS_KM;
                    _SphereMass = MASS;
                }
                else if (_CurrentScene == 2)
                {
                    _SpherePos = float3(0.0, 0.0, -150.0);
                    _SphereRadius = RS_KM;
                    _SphereMass = MASS;
                    _UseUniverseSkybox = 1;
                }
                else if (_CurrentScene == 3)
                {
                    _SpherePos = float3(0.0, 0.0, -150.0);
                    _SphereRadius = RS_KM;
                    _SphereMass = MASS;
                    _HasRing = 1;
                    _UseUniverseSkybox = 1;
                }
                else if (_CurrentScene == 4)
                {
                    _SpherePos = float3(-50.0, 0.0, -150.0);
                    _SphereRadius = RS_KM;
                    _SphereMass = MASS;
                    _Sphere2Pos = float3(50.0, 0.0, -150.0);
                    _Sphere2Radius = RS_KM;
                    _Sphere2Mass = MASS;
                }
                else if (_CurrentScene == 5)
                {
                    _SpherePos = float3(-50.0, 0.0, -150.0);
                    _SphereRadius = RS_KM;
                    _SphereMass = MASS;
                    _Sphere2Pos = float3(50.0, 0.0, -150.0);
                    _Sphere2Radius = RS_KM;
                    _Sphere2Mass = MASS;
                    _UseUniverseSkybox = 1;
                }
                else if (_CurrentScene == 6)
                {
                    // Sun (primary star)
                    _Bodies[0] = float4(0.0, 0.0, 0.0, 20.0);
                    _BodyMasses[0] = 1.989e30;
                    
                    // Mercury
                    _Bodies[1] = float4(30.0, 0.0, 0.0, 2.0);
                    _BodyMasses[1] = 3.285e23;
                    
                    // Venus
                    _Bodies[2] = float4(50.0, 5.0, 10.0, 3.5);
                    _BodyMasses[2] = 4.867e24;
                    
                    // Earth
                    _Bodies[3] = float4(70.0, -3.0, 15.0, 3.7);
                    _BodyMasses[3] = 5.972e24;
                    
                    // Mars
                    _Bodies[4] = float4(90.0, 4.0, 20.0, 2.8);
                    _BodyMasses[4] = 6.417e23;
                    
                    // Jupiter
                    _Bodies[5] = float4(130.0, -8.0, 35.0, 12.0);
                    _BodyMasses[5] = 1.898e27;
                    
                    // Saturn (with ring)
                    _Bodies[6] = float4(170.0, 6.0, 50.0, 10.5);
                    _BodyMasses[6] = 5.683e26;
                    
                    // Saturn alternate position for ring demonstration
                    _Bodies[7] = float4(170.0, 6.0, 50.0, 10.5);
                    _BodyMasses[7] = 5.683e26;
                    
                    // Uranus
                    _Bodies[8] = float4(220.0, -5.0, 70.0, 8.0);
                    _BodyMasses[8] = 8.681e25;
                    
                    // Neptune
                    _Bodies[9] = float4(270.0, 7.0, 90.0, 7.8);
                    _BodyMasses[9] = 1.024e26;
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
                    float sqrtDisc = sqrt(discriminant);
                    float dst = (-b - sqrtDisc) / (2 * a);
                    if (dst < 0) dst = (-b + sqrtDisc) / (2 * a);
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

            float2 GetSphericalUV(float3 normal)
            {
                float u = atan2(normal.z, normal.x) / (2.0 * 3.14159265) + 0.5;
                float v = asin(normal.y) / 3.14159265 + 0.5;
                return float2(u, v);
            }

            HitInfo CalculateRayCollision(Ray ray)
            {
                HitInfo closestHit = (HitInfo)0;
                closestHit.dst = 1e10;
                closestHit.bodyIndex = -1;

                if (_CurrentScene == 6)
                {
                    for (int i = 0; i < 10; i++)
                    {
                        HitInfo hit = RaySphere(ray, _Bodies[i].xyz, _Bodies[i].w);
                        if (hit.didHit && hit.dst < closestHit.dst)
                        {
                            closestHit = hit;
                            closestHit.bodyIndex = i;
                            
                            float2 uv = GetSphericalUV(hit.normal);
                            
                            if (i == 0) closestHit.colour = tex2Dlod(_PlanetTex0, float4(uv, 0, 0)).rgb;
                            else if (i == 1) closestHit.colour = tex2Dlod(_PlanetTex1, float4(uv, 0, 0)).rgb;
                            else if (i == 2) closestHit.colour = tex2Dlod(_PlanetTex2, float4(uv, 0, 0)).rgb;
                            else if (i == 3) closestHit.colour = tex2Dlod(_PlanetTex3, float4(uv, 0, 0)).rgb;
                            else if (i == 4) closestHit.colour = tex2Dlod(_PlanetTex4, float4(uv, 0, 0)).rgb;
                            else if (i == 5) closestHit.colour = tex2Dlod(_PlanetTex5, float4(uv, 0, 0)).rgb;
                            else if (i == 6) closestHit.colour = tex2Dlod(_PlanetTex6, float4(uv, 0, 0)).rgb;
                            else if (i == 7) closestHit.colour = tex2Dlod(_PlanetTex7, float4(uv, 0, 0)).rgb;
                            else if (i == 8) closestHit.colour = tex2Dlod(_PlanetTex8, float4(uv, 0, 0)).rgb;
                            else if (i == 9) closestHit.colour = tex2Dlod(_PlanetTex9, float4(uv, 0, 0)).rgb;
                        }
                    }

                    float t_ring;
                    float ringInner = _Bodies[7].w * 1.5;
                    float ringOuter = _Bodies[7].w * 2.5;
                    if (HitRing(_Bodies[7].xyz, float3(0.2, 1.0, 0.2), ringInner, ringOuter, ray, t_ring))
                    {
                        if (t_ring < closestHit.dst)
                        {
                            closestHit.didHit = true;
                            closestHit.dst = t_ring;
                            closestHit.hitPoint = ray.origin + ray.dir * t_ring;
                            closestHit.colour = float3(0.8, 0.7, 0.5);
                        }
                    }
                    return closestHit;
                }

                HitInfo sphereHit = RaySphere(ray, _SpherePos, _SphereRadius);
                if (sphereHit.didHit && sphereHit.dst < closestHit.dst)
                {
                    closestHit = sphereHit;
                    closestHit.colour = float3(0, 0, 0);
                    if (_UseHyperbolicView == 0) closestHit.colour = float3(0.74, 0.74, 0.74);
                }

                if (_Sphere2Radius > 0.0)
                {
                    HitInfo sphere2Hit = RaySphere(ray, _Sphere2Pos, _Sphere2Radius);
                    if (sphere2Hit.didHit && sphere2Hit.dst < closestHit.dst)
                    {
                        closestHit = sphere2Hit;
                        closestHit.colour = float3(0, 0, 0);
                        if (_UseHyperbolicView == 0) closestHit.colour = float3(0.74, 0.74, 0.74);
                    }
                }

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

            float3 GetGravityAccel(float3 pos, float3 v)
            {
                float3 accel = float3(0, 0, 0);

                if (_CurrentScene == 6)
                {
                    for (int i = 0; i < 10; i++)
                    {
                        if (_BodyMasses[i] <= 0) continue;
                        
                        float3 toBody = _Bodies[i].xyz - pos;
                        float r_dist = length(toBody);
                        if (r_dist < 0.0001) continue;

                        float rs_km = (2.0 * G_REAL * _BodyMasses[i] * _GravityMultiplier) / (C_REAL * C_REAL) / 1000.0;
                        float r_dist2 = r_dist * r_dist;
                        float r_dist3 = r_dist2 * r_dist;
                        
                        if (_Metric == 0) {
                            accel += toBody * (rs_km * 0.5) / r_dist3;
                        } else {
                            float r_dist5 = r_dist3 * r_dist2;
                            float3 h_vec = cross(-toBody, v);
                            accel += toBody * (1.5 * rs_km * dot(h_vec, h_vec)) / r_dist5;
                        }
                    }
                    return accel;
                }

                float3 toSphere = _SpherePos - pos;
                float r_dist = length(toSphere);
                if (r_dist < 0.0001) return float3(0, 0, 0);

                float r_dist2 = r_dist * r_dist;
                float r_dist3 = r_dist2 * r_dist;
                float r_dist5 = r_dist3 * r_dist2;

                float sphereRadiusAdjusted = _SphereRadius * _GravityMultiplier;
                
                if (_Metric == 0)
                {
                    accel = toSphere * (sphereRadiusAdjusted * 0.5) / r_dist3;
                }
                else if (_Metric == 1)
                {
                    float3 h_vec = cross(-toSphere, v);
                    accel = toSphere * (1.5 * sphereRadiusAdjusted * dot(h_vec, h_vec)) / r_dist5;
                }
                else 
                {
                    float3 r_vec = -toSphere;
                    float3 h_vec = cross(r_vec, v);
                    float3 a_schwarzschild = -r_vec * (1.5 * sphereRadiusAdjusted * dot(h_vec, h_vec)) / r_dist5;
                    float3 spin_vec = KERR_SPIN_AXIS * sphereRadiusAdjusted * _SpinSpeed;
                    float3 H = (2.0 / r_dist5) * (3.0 * r_vec * dot(spin_vec, r_vec) - spin_vec * r_dist2);
                    float3 a_frame_drag = -cross(v, H);
                    accel = a_schwarzschild + a_frame_drag;
                }

                if (_Sphere2Radius > 0.0)
                {
                    float3 toSphere2 = _Sphere2Pos - pos;
                    float r2_dist = length(toSphere2);
                    if (r2_dist > 0.0001)
                    {
                        float d2_2 = r2_dist * r2_dist;
                        float d2_3 = d2_2 * r2_dist;
                        float d2_5 = d2_3 * d2_2;

                        float sphere2RadiusAdjusted = _Sphere2Radius * _GravityMultiplier;

                        if (_Metric == 0)
                        {
                            accel += toSphere2 * (sphere2RadiusAdjusted * 0.5) / d2_3;
                        }
                        else if (_Metric == 1)
                        {
                            float3 h_vec2 = cross(-toSphere2, v);
                            accel += toSphere2 * (1.5 * sphere2RadiusAdjusted * dot(h_vec2, h_vec2)) / d2_5;
                        }
                        else 
                        {
                            float3 r_vec2 = -toSphere2;
                            float3 h_vec2 = cross(r_vec2, v);
                            float3 a_schwarzschild2 = -r_vec2 * (1.5 * sphere2RadiusAdjusted * dot(h_vec2, h_vec2)) / d2_5;
                            float3 spin_vec2 = KERR_SPIN_AXIS * sphere2RadiusAdjusted * _SpinSpeed;
                            float3 H2 = (2.0 / d2_5) * (3.0 * r_vec2 * dot(spin_vec2, r_vec2) - spin_vec2 * d2_2);
                            float3 a_frame_drag2 = -cross(v, H2);
                            accel += a_schwarzschild2 + a_frame_drag2;
                        }
                    }
                }

                return accel;
            }

            void StepEuler(inout float3 origin, inout float3 velocity, float dt)
            {
                float3 accel = GetGravityAccel(origin, velocity);
                velocity = normalize(velocity + accel * dt);
                origin += velocity * dt;
            }

            void StepRK4(inout float3 origin, inout float3 velocity, float dt)
            {
                float3 p = origin;
                float3 v = velocity;

                float3 k1_p = v;
                float3 k1_v = GetGravityAccel(p, v);

                float3 k2_p = v + 0.5 * dt * k1_v;
                float3 k2_v = GetGravityAccel(p + 0.5 * dt * k1_p, v + 0.5 * dt * k1_v);

                float3 k3_p = v + 0.5 * dt * k2_v;
                float3 k3_v = GetGravityAccel(p + 0.5 * dt * k2_p, v + 0.5 * dt * k2_v);

                float3 k4_p = v + dt * k3_v;
                float3 k4_v = GetGravityAccel(p + dt * k3_p, v + dt * k3_v);

                origin += (dt / 6.0) * (k1_p + 2.0 * k2_p + 2.0 * k3_p + k4_p);
                float3 new_velocity = v + (dt / 6.0) * (k1_v + 2.0 * k2_v + 2.0 * k3_v + k4_v);
                
                velocity = normalize(new_velocity);
            }

            HitInfo ApplyRelativisticEffects(float3 initialRayDir, out float3 finalRayDir)
            {
                if (_UseHyperbolicView == 0) 
                { 
                    Ray straightRay; 
                    straightRay.origin = _WorldSpaceCameraPos;  
                    straightRay.dir = initialRayDir; 
                    finalRayDir = initialRayDir;
         
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
                        finalRayDir = ray.dir;
                        return hitInfo;
                    }
                    
                    // First Black Hole Trapping
                    if (length(_SpherePos - ray.origin) < _SphereRadius)
                    {
                        HitInfo black = (HitInfo)0;
                        black.didHit = true;
                        black.dst = 0.0;
                        black.colour = float3(0, 0, 0);
                        finalRayDir = ray.dir;
                        return black;
                    }

                    // Second Black Hole Trapping
                    if (_Sphere2Radius > 0.0 && length(_Sphere2Pos - ray.origin) < _Sphere2Radius)
                    {
                        HitInfo black = (HitInfo)0;
                        black.didHit = true;
                        black.dst = 0.0;
                        black.colour = float3(0, 0, 0);
                        finalRayDir = ray.dir;
                        return black;
                    }

                    // Cena 6 celestial body trapping
                    if (_CurrentScene == 6)
                    {
                        for (int body = 0; body < 10; body++)
                        {
                            if (length(_Bodies[body].xyz - ray.origin) < _Bodies[body].w * 0.5)
                            {
                                HitInfo black = (HitInfo)0;
                                black.didHit = true;
                                black.dst = 0.0;
                                black.colour = float3(0, 0, 0);
                                finalRayDir = ray.dir;
                                return black;
                            }
                        }
                    }
                    
                    if (_Integrator == 1)
                        StepRK4(ray.origin, ray.dir, _StepSize);
                    else
                        StepEuler(ray.origin, ray.dir, _StepSize);
                    
                    if (length(ray.origin - _WorldSpaceCameraPos) > 2000.0) break;
                }
                
                HitInfo missInfo = (HitInfo)0;
                missInfo.didHit = false;
                finalRayDir = ray.dir;
                return missInfo;
            }

            float3 GetSkyColor(float3 direction, int useUniverse)
            {
                if (_CurrentScene == 6 && _UseMilkyWay == 1)
                {
                    return texCUBE(_MilkyWayTex, direction).rgb;
                }
                if (useUniverse == 1)
                {
                    return texCUBE(_SkyboxTexture, direction).rgb;
                }
                else
                {
                    float3 unitDir = normalize(direction);
                    if (unitDir.x < 0 && unitDir.y > 0) return float3(1, 1, 0);
                    else if (unitDir.x >= 0 && unitDir.y > 0) return float3(1, 0, 0);
                    else if (unitDir.x < 0 && unitDir.y < 0) return float3(0, 1, 0);
                    else return float3(0, 0, 1);
                }
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
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

                float3 finalRayDir;
                HitInfo hitInfo = ApplyRelativisticEffects(initialRayDir, finalRayDir);
                float3 finalColour = float3(0, 0, 0);

                if (hitInfo.didHit)
                {
                    finalColour = hitInfo.colour;
                }
                else
                {
                    finalColour = GetSkyColor(finalRayDir, _UseUniverseSkybox);
                }

                return float4(finalColour, 1.0);
            }
            ENDCG
        }
    }
}