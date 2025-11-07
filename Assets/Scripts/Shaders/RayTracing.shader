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
 
            Texture3D<float4> _GeodesicTable_A; 
            Texture3D<float4> _GeodesicTable_B; 
            Texture3D<float4> _GeodesicTable_C;
            
            // Texturas com os Símbolos de Christoffel pré-calculados (40 componentes em 10 float4)
            Texture3D<float4> _Christoffel_1;
            Texture3D<float4> _Christoffel_2;
            Texture3D<float4> _Christoffel_3;
            Texture3D<float4> _Christoffel_4;
            Texture3D<float4> _Christoffel_5;
            Texture3D<float4> _Christoffel_6;
            Texture3D<float4> _Christoffel_7;
            Texture3D<float4> _Christoffel_8;
            Texture3D<float4> _Christoffel_9;
            Texture3D<float4> _Christoffel_10; 
             
            SamplerState sampler_linear_clamp; 
             
            int _GridResolution;
            float3 _GridCenter;
            float _GridSize;

            #define G 6.67430f
 
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
 
            float3 WorldToGridUV(float3 worldPos)
            { 
                return (worldPos - _GridCenter) / _GridSize + 0.5;
            }
 
            void GetMetricAt(float3 worldPos, out float4 g_A, out float4 g_B, out float4 g_C)
            {
                float3 uvw = WorldToGridUV(worldPos); 
                g_A = _GeodesicTable_A.SampleLevel(sampler_linear_clamp, uvw, 0);
                g_B = _GeodesicTable_B.SampleLevel(sampler_linear_clamp, uvw, 0);
                g_C = _GeodesicTable_C.SampleLevel(sampler_linear_clamp, uvw, 0);
            }
 
            float4 CalculateGeodesicAcceleration(float4 pos_4D, float4 vel_4D)
            {
                float3 pos_3D = pos_4D.yzw;
                
                // Calcula coordenadas de textura (uvw) para amostragem
                float3 uvw = WorldToGridUV(pos_3D);
                
                // ========================================================================
                // 1. Amostra as 10 texturas de Símbolos de Christoffel pré-calculados
                // ========================================================================
                float4 C1 = _Christoffel_1.SampleLevel(sampler_linear_clamp, uvw, 0);
                float4 C2 = _Christoffel_2.SampleLevel(sampler_linear_clamp, uvw, 0);
                float4 C3 = _Christoffel_3.SampleLevel(sampler_linear_clamp, uvw, 0);
                float4 C4 = _Christoffel_4.SampleLevel(sampler_linear_clamp, uvw, 0);
                float4 C5 = _Christoffel_5.SampleLevel(sampler_linear_clamp, uvw, 0);
                float4 C6 = _Christoffel_6.SampleLevel(sampler_linear_clamp, uvw, 0);
                float4 C7 = _Christoffel_7.SampleLevel(sampler_linear_clamp, uvw, 0);
                float4 C8 = _Christoffel_8.SampleLevel(sampler_linear_clamp, uvw, 0);
                float4 C9 = _Christoffel_9.SampleLevel(sampler_linear_clamp, uvw, 0);
                float4 C10 = _Christoffel_10.SampleLevel(sampler_linear_clamp, uvw, 0);
                
                // ========================================================================
                // 2. Desempacota os 40 componentes dos Símbolos de Christoffel
                // ========================================================================
                // Layout (deve corresponder ao usado no compute shader):
                // C1:  Gamma_t_tt, Gamma_t_tx, Gamma_t_ty, Gamma_t_tz
                // C2:  Gamma_t_xx, Gamma_t_xy, Gamma_t_xz, Gamma_t_yy
                // C3:  Gamma_t_yz, Gamma_t_zz, Gamma_x_tt, Gamma_x_tx
                // C4:  Gamma_x_ty, Gamma_x_tz, Gamma_x_xx, Gamma_x_xy
                // C5:  Gamma_x_xz, Gamma_x_yy, Gamma_x_yz, Gamma_x_zz
                // C6:  Gamma_y_tt, Gamma_y_tx, Gamma_y_ty, Gamma_y_tz
                // C7:  Gamma_y_xx, Gamma_y_xy, Gamma_y_xz, Gamma_y_yy
                // C8:  Gamma_y_yz, Gamma_y_zz, Gamma_z_tt, Gamma_z_tx
                // C9:  Gamma_z_ty, Gamma_z_tz, Gamma_z_xx, Gamma_z_xy
                // C10: Gamma_z_xz, Gamma_z_yy, Gamma_z_yz, Gamma_z_zz
                
                // Γ^t_νσ
                float Gamma_t_tt = C1.x;
                float Gamma_t_tx = C1.y;
                float Gamma_t_ty = C1.z;
                float Gamma_t_tz = C1.w;
                float Gamma_t_xx = C2.x;
                float Gamma_t_xy = C2.y;
                float Gamma_t_xz = C2.z;
                float Gamma_t_yy = C2.w;
                float Gamma_t_yz = C3.x;
                float Gamma_t_zz = C3.y;
                
                // Γ^x_νσ
                float Gamma_x_tt = C3.z;
                float Gamma_x_tx = C3.w;
                float Gamma_x_ty = C4.x;
                float Gamma_x_tz = C4.y;
                float Gamma_x_xx = C4.z;
                float Gamma_x_xy = C4.w;
                float Gamma_x_xz = C5.x;
                float Gamma_x_yy = C5.y;
                float Gamma_x_yz = C5.z;
                float Gamma_x_zz = C5.w;
                
                // Γ^y_νσ
                float Gamma_y_tt = C6.x;
                float Gamma_y_tx = C6.y;
                float Gamma_y_ty = C6.z;
                float Gamma_y_tz = C6.w;
                float Gamma_y_xx = C7.x;
                float Gamma_y_xy = C7.y;
                float Gamma_y_xz = C7.z;
                float Gamma_y_yy = C7.w;
                float Gamma_y_yz = C8.x;
                float Gamma_y_zz = C8.y;
                
                // Γ^z_νσ
                float Gamma_z_tt = C8.z;
                float Gamma_z_tx = C8.w;
                float Gamma_z_ty = C9.x;
                float Gamma_z_tz = C9.y;
                float Gamma_z_xx = C9.z;
                float Gamma_z_xy = C9.w;
                float Gamma_z_xz = C10.x;
                float Gamma_z_yy = C10.y;
                float Gamma_z_yz = C10.z;
                float Gamma_z_zz = C10.w;
                
                // ========================================================================
                // 3. Calcula a aceleração geodésica usando a equação:
                // a^μ = -Γ^μ_νσ v^ν v^σ
                // ========================================================================
                float v_t = vel_4D.x;
                float v_x = vel_4D.y;
                float v_y = vel_4D.z;
                float v_z = vel_4D.w;
                
                // Aceleração temporal
                float a_t = -(
                    Gamma_t_tt * v_t * v_t +
                    2.0 * Gamma_t_tx * v_t * v_x +
                    2.0 * Gamma_t_ty * v_t * v_y +
                    2.0 * Gamma_t_tz * v_t * v_z +
                    Gamma_t_xx * v_x * v_x +
                    2.0 * Gamma_t_xy * v_x * v_y +
                    2.0 * Gamma_t_xz * v_x * v_z +
                    Gamma_t_yy * v_y * v_y +
                    2.0 * Gamma_t_yz * v_y * v_z +
                    Gamma_t_zz * v_z * v_z
                );
                
                // Aceleração em x
                float a_x = -(
                    Gamma_x_tt * v_t * v_t +
                    2.0 * Gamma_x_tx * v_t * v_x +
                    2.0 * Gamma_x_ty * v_t * v_y +
                    2.0 * Gamma_x_tz * v_t * v_z +
                    Gamma_x_xx * v_x * v_x +
                    2.0 * Gamma_x_xy * v_x * v_y +
                    2.0 * Gamma_x_xz * v_x * v_z +
                    Gamma_x_yy * v_y * v_y +
                    2.0 * Gamma_x_yz * v_y * v_z +
                    Gamma_x_zz * v_z * v_z
                );
                
                // Aceleração em y
                float a_y = -(
                    Gamma_y_tt * v_t * v_t +
                    2.0 * Gamma_y_tx * v_t * v_x +
                    2.0 * Gamma_y_ty * v_t * v_y +
                    2.0 * Gamma_y_tz * v_t * v_z +
                    Gamma_y_xx * v_x * v_x +
                    2.0 * Gamma_y_xy * v_x * v_y +
                    2.0 * Gamma_y_xz * v_x * v_z +
                    Gamma_y_yy * v_y * v_y +
                    2.0 * Gamma_y_yz * v_y * v_z +
                    Gamma_y_zz * v_z * v_z
                );
                
                // Aceleração em z
                float a_z = -(
                    Gamma_z_tt * v_t * v_t +
                    2.0 * Gamma_z_tx * v_t * v_x +
                    2.0 * Gamma_z_ty * v_t * v_y +
                    2.0 * Gamma_z_tz * v_t * v_z +
                    Gamma_z_xx * v_x * v_x +
                    2.0 * Gamma_z_xy * v_x * v_y +
                    2.0 * Gamma_z_xz * v_x * v_z +
                    Gamma_z_yy * v_y * v_y +
                    2.0 * Gamma_z_yz * v_y * v_z +
                    Gamma_z_zz * v_z * v_z
                );
                
                return float4(a_t, a_x, a_y, a_z);
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
                 
                float4 currentPosition4D = float4(0, _WorldSpaceCameraPos.x, _WorldSpaceCameraPos.y, _WorldSpaceCameraPos.z);
                 
                float4 g_A_cam, g_B_cam, g_C_cam;
                GetMetricAt(_WorldSpaceCameraPos, g_A_cam, g_B_cam, g_C_cam);
                 
                float g_tt = g_A_cam.x;
                float g_xx = g_A_cam.y;
                float g_yy = g_A_cam.z;
                float g_zz = g_A_cam.w;
                float g_tx = g_B_cam.x;
                float g_ty = g_B_cam.y;
                float g_tz = g_B_cam.z;
                float g_xy = g_B_cam.w;
                float g_xz = g_C_cam.x;
                float g_yz = g_C_cam.y;
                 
                float3 v_spatial = normalize(initialRayDir);
                float v_x = v_spatial.x;
                float v_y = v_spatial.y;
                float v_z = v_spatial.z;
                 
                float A = g_tt;
                float B = 2.0 * (g_tx * v_x + g_ty * v_y + g_tz * v_z);
                float C = g_xx * v_x * v_x + g_yy * v_y * v_y + g_zz * v_z * v_z
                        + 2.0 * (g_xy * v_x * v_y + g_xz * v_x * v_z + g_yz * v_y * v_z);
                 
                float discriminant = B * B - 4.0 * A * C;
                float v_t = 1.0; 
                
                if (discriminant >= 0.0 && abs(A) > 1e-6)
                { 
                    v_t = (-B + sqrt(discriminant)) / (2.0 * A);
                }
                 
                float4 currentVelocity4D = float4(v_t, v_x, v_y, v_z);
                
                Ray curvedRay;
                 
                for (int step = 0; step < _MaxSteps; step++)
                { 
                    curvedRay.origin = currentPosition4D.yzw;
                    curvedRay.dir = normalize(currentVelocity4D.yzw);

                    HitInfo hitInfo = CalculateRayCollision(curvedRay);
                    if (hitInfo.didHit && hitInfo.dst <= _StepSize)
                    {
                        return hitInfo;
                    }
                     
                    float h = _StepSize; 
                     
                    float4 k1_v = CalculateGeodesicAcceleration(currentPosition4D, currentVelocity4D);
                    float4 k1_x = currentVelocity4D;
                     
                    float4 pos_k2 = currentPosition4D + k1_x * (h * 0.5);
                    float4 vel_k2 = currentVelocity4D + k1_v * (h * 0.5);
                    float4 k2_v = CalculateGeodesicAcceleration(pos_k2, vel_k2);
                    float4 k2_x = vel_k2;
                     
                    float4 pos_k3 = currentPosition4D + k2_x * (h * 0.5);
                    float4 vel_k3 = currentVelocity4D + k2_v * (h * 0.5);
                    float4 k3_v = CalculateGeodesicAcceleration(pos_k3, vel_k3);
                    float4 k3_x = vel_k3;
                     
                    float4 pos_k4 = currentPosition4D + k3_x * h;
                    float4 vel_k4 = currentVelocity4D + k3_v * h;
                    float4 k4_v = CalculateGeodesicAcceleration(pos_k4, vel_k4);
                    float4 k4_x = vel_k4;
                     
                    float4 deltaVelocity = (k1_v + 2.0 * k2_v + 2.0 * k3_v + k4_v) / 6.0;
                    float4 deltaPosition = (k1_x + 2.0 * k2_x + 2.0 * k3_x + k4_x) / 6.0;
                     
                    currentVelocity4D += deltaVelocity * h;
                    currentPosition4D += deltaPosition * h;
                     
                    if (step % 10 == 0)
                    {
                        float4 g_A_curr, g_B_curr, g_C_curr;
                        GetMetricAt(currentPosition4D.yzw, g_A_curr, g_B_curr, g_C_curr);
                         
                        float3 v_spatial_curr = currentVelocity4D.yzw;
                        float v_x_curr = v_spatial_curr.x;
                        float v_y_curr = v_spatial_curr.y;
                        float v_z_curr = v_spatial_curr.z;
                        
                        float A_curr = g_A_curr.x;
                        float B_curr = 2.0 * (g_B_curr.x * v_x_curr + g_B_curr.y * v_y_curr + g_B_curr.z * v_z_curr);
                        float C_curr = g_A_curr.y * v_x_curr * v_x_curr 
                                     + g_A_curr.z * v_y_curr * v_y_curr 
                                     + g_A_curr.w * v_z_curr * v_z_curr
                                     + 2.0 * (g_B_curr.w * v_x_curr * v_y_curr 
                                            + g_C_curr.x * v_x_curr * v_z_curr 
                                            + g_C_curr.y * v_y_curr * v_z_curr);
                        
                        float disc_curr = B_curr * B_curr - 4.0 * A_curr * C_curr;
                        if (disc_curr >= 0.0 && abs(A_curr) > 1e-6)
                        {
                            currentVelocity4D.x = (-B_curr + sqrt(disc_curr)) / (2.0 * A_curr);
                        }
                    }
                }
                
                HitInfo missInfo;
                missInfo.didHit = false;
                return missInfo;
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
                    {
                        return float4(0,0,0,1);
                    }
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