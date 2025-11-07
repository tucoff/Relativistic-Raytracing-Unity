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
                 
                float4 g_A, g_B, g_C;
                GetMetricAt(pos_3D, g_A, g_B, g_C);
                 
                float g_tt = g_A.x;
                float g_xx = g_A.y;
                float g_yy = g_A.z;
                float g_zz = g_A.w;
                float g_tx = g_B.x;
                float g_ty = g_B.y;
                float g_tz = g_B.z;
                float g_xy = g_B.w;
                float g_xz = g_C.x;
                float g_yz = g_C.y;
                 
                float dx = _GridSize / _GridResolution * 0.5; 
                
                float4 g_A_px, g_B_px, g_C_px; 
                float4 g_A_mx, g_B_mx, g_C_mx; 
                float4 g_A_py, g_B_py, g_C_py; 
                float4 g_A_my, g_B_my, g_C_my; 
                float4 g_A_pz, g_B_pz, g_C_pz;  
                float4 g_A_mz, g_B_mz, g_C_mz; 
                
                GetMetricAt(pos_3D + float3(dx, 0, 0), g_A_px, g_B_px, g_C_px);
                GetMetricAt(pos_3D - float3(dx, 0, 0), g_A_mx, g_B_mx, g_C_mx);
                GetMetricAt(pos_3D + float3(0, dx, 0), g_A_py, g_B_py, g_C_py);
                GetMetricAt(pos_3D - float3(0, dx, 0), g_A_my, g_B_my, g_C_my);
                GetMetricAt(pos_3D + float3(0, 0, dx), g_A_pz, g_B_pz, g_C_pz);
                GetMetricAt(pos_3D - float3(0, 0, dx), g_A_mz, g_B_mz, g_C_mz);
                 
                float dg_tt_dt = 0.0; 
                float dg_tt_dx = (g_A_px.x - g_A_mx.x) / (2*dx);
                float dg_tt_dy = (g_A_py.x - g_A_my.x) / (2*dx);
                float dg_tt_dz = (g_A_pz.x - g_A_mz.x) / (2*dx);
                 
                float dg_xx_dt = 0.0;
                float dg_xx_dx = (g_A_px.y - g_A_mx.y) / (2*dx);
                float dg_xx_dy = (g_A_py.y - g_A_my.y) / (2*dx);
                float dg_xx_dz = (g_A_pz.y - g_A_mz.y) / (2*dx);
                 
                float dg_yy_dt = 0.0;
                float dg_yy_dx = (g_A_px.z - g_A_mx.z) / (2*dx);
                float dg_yy_dy = (g_A_py.z - g_A_my.z) / (2*dx);
                float dg_yy_dz = (g_A_pz.z - g_A_mz.z) / (2*dx);
                 
                float dg_zz_dt = 0.0;
                float dg_zz_dx = (g_A_px.w - g_A_mx.w) / (2*dx);
                float dg_zz_dy = (g_A_py.w - g_A_my.w) / (2*dx);
                float dg_zz_dz = (g_A_pz.w - g_A_mz.w) / (2*dx);
                 
                float dg_tx_dx = (g_B_px.x - g_B_mx.x) / (2*dx);
                float dg_tx_dy = (g_B_py.x - g_B_my.x) / (2*dx);
                float dg_tx_dz = (g_B_pz.x - g_B_mz.x) / (2*dx);
                
                float dg_ty_dx = (g_B_px.y - g_B_mx.y) / (2*dx);
                float dg_ty_dy = (g_B_py.y - g_B_my.y) / (2*dx);
                float dg_ty_dz = (g_B_pz.y - g_B_mz.y) / (2*dx);
                
                float dg_tz_dx = (g_B_px.z - g_B_mx.z) / (2*dx);
                float dg_tz_dy = (g_B_py.z - g_B_my.z) / (2*dx);
                float dg_tz_dz = (g_B_pz.z - g_B_mz.z) / (2*dx);
                 
                float det_spatial = g_xx * g_yy * g_zz; 
                float g_inv_tt = 1.0 / g_tt;
                float g_inv_xx = 1.0 / g_xx;
                float g_inv_yy = 1.0 / g_yy;
                float g_inv_zz = 1.0 / g_zz;
                 
                float Gamma_t_tt = 0.5 * g_inv_tt * (dg_tt_dt + dg_tt_dt - dg_tt_dt);
                float Gamma_t_tx = 0.5 * g_inv_tt * (dg_tt_dx + dg_tx_dt - dg_tx_dt);
                float Gamma_t_ty = 0.5 * g_inv_tt * (dg_tt_dy + dg_ty_dt - dg_ty_dt);
                float Gamma_t_tz = 0.5 * g_inv_tt * (dg_tt_dz + dg_tz_dt - dg_tz_dt);
                float Gamma_t_xx = 0.5 * g_inv_tt * (dg_tx_dx + dg_tx_dx - dg_xx_dt);
                float Gamma_t_yy = 0.5 * g_inv_tt * (dg_ty_dy + dg_ty_dy - dg_yy_dt);
                float Gamma_t_zz = 0.5 * g_inv_tt * (dg_tz_dz + dg_tz_dz - dg_zz_dt);
                 
                float Gamma_x_tt = 0.5 * g_inv_xx * (dg_tx_dt + dg_tx_dt - dg_tt_dx);
                float Gamma_x_tx = 0.5 * g_inv_xx * (dg_tx_dx + dg_xx_dt - dg_tx_dx);
                float Gamma_x_xx = 0.5 * g_inv_xx * (dg_xx_dx + dg_xx_dx - dg_xx_dx);
                float Gamma_x_yy = 0.5 * g_inv_xx * (dg_xy_dy + dg_xy_dy - dg_yy_dx);
                float Gamma_x_zz = 0.5 * g_inv_xx * (dg_xz_dz + dg_xz_dz - dg_zz_dx);
                 
                float Gamma_y_tt = 0.5 * g_inv_yy * (dg_ty_dt + dg_ty_dt - dg_tt_dy);
                float Gamma_y_ty = 0.5 * g_inv_yy * (dg_ty_dy + dg_yy_dt - dg_ty_dy);
                float Gamma_y_xx = 0.5 * g_inv_yy * (dg_xy_dx + dg_xy_dx - dg_xx_dy);
                float Gamma_y_yy = 0.5 * g_inv_yy * (dg_yy_dy + dg_yy_dy - dg_yy_dy);
                float Gamma_y_zz = 0.5 * g_inv_yy * (dg_yz_dz + dg_yz_dz - dg_zz_dy);
                 
                float Gamma_z_tt = 0.5 * g_inv_zz * (dg_tz_dt + dg_tz_dt - dg_tt_dz);
                float Gamma_z_tz = 0.5 * g_inv_zz * (dg_tz_dz + dg_zz_dt - dg_tz_dz);
                float Gamma_z_xx = 0.5 * g_inv_zz * (dg_xz_dx + dg_xz_dx - dg_xx_dz);
                float Gamma_z_yy = 0.5 * g_inv_zz * (dg_yz_dy + dg_yz_dy - dg_yy_dz);
                float Gamma_z_zz = 0.5 * g_inv_zz * (dg_zz_dz + dg_zz_dz - dg_zz_dz);
                 
                float dg_xy_dx = 0.0, dg_xy_dy = 0.0;
                float dg_xz_dx = 0.0, dg_xz_dz = 0.0;
                float dg_yz_dy = 0.0, dg_yz_dz = 0.0;
                 
                float v_t = vel_4D.x;
                float v_x = vel_4D.y;
                float v_y = vel_4D.z;
                float v_z = vel_4D.w;
                 
                float a_t = -(
                    Gamma_t_tt * v_t * v_t +
                    2.0 * Gamma_t_tx * v_t * v_x +
                    2.0 * Gamma_t_ty * v_t * v_y +
                    2.0 * Gamma_t_tz * v_t * v_z +
                    Gamma_t_xx * v_x * v_x +
                    Gamma_t_yy * v_y * v_y +
                    Gamma_t_zz * v_z * v_z
                );
                 
                float a_x = -(
                    Gamma_x_tt * v_t * v_t +
                    2.0 * Gamma_x_tx * v_t * v_x +
                    Gamma_x_xx * v_x * v_x +
                    Gamma_x_yy * v_y * v_y +
                    Gamma_x_zz * v_z * v_z
                );
                 
                float a_y = -(
                    Gamma_y_tt * v_t * v_t +
                    2.0 * Gamma_y_ty * v_t * v_y +
                    Gamma_y_xx * v_x * v_x +
                    Gamma_y_yy * v_y * v_y +
                    Gamma_y_zz * v_z * v_z
                );
                 
                float a_z = -(
                    Gamma_z_tt * v_t * v_t +
                    2.0 * Gamma_z_tz * v_t * v_z +
                    Gamma_z_xx * v_x * v_x +
                    Gamma_z_yy * v_y * v_y +
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