using System.Collections.Generic;
using UnityEngine;
using static UnityEngine.Mathf;

[ExecuteAlways, ImageEffectAllowedInSceneView]
public class RayTracingManager : MonoBehaviour
{
    public const int TriangleLimit = 1500;
    [Header("Ray Tracing Settings")]
    [SerializeField, Min(0)] float focusDistance = 1;
    [SerializeField] Vector3 lightDirection = new Vector3(1, -1, -1);
    [SerializeField, Range(0f, 2f)] float directionalLightIntensity = 0.5f;
    
    [Header("Relativistic View Settings")]
    [SerializeField] bool useRelativisticView = false;
    [SerializeField, Min(0.001f)] public float stepSize = 10f;
    [SerializeField, Min(1)] int maxSteps = 1000;
    
    [Header("Point Mode Settings")]
    [SerializeField] bool usePointMode = false; 

    [Header("First Person Controls")]
    [SerializeField] float moveSpeed = 5f;
    [SerializeField] float mouseSensitivity = 2f;
    public bool enableFirstPersonControls = false;

    [Header("References")]
    [SerializeField] Shader rayTracingShader;

    // FPS tracking variables
    private float deltaTime = 0.0f;
    private float fps = 0.0f;
    private int frameCount = 0;
    private float fpsUpdateInterval = 0.5f;
    private float fpsAccumulator = 0.0f;
    private float lastTime = 0.0f;

    // First person controls
    private float xRotation = 0f;
    private float yRotation = 0f;
    private bool cursorLocked = false;

    // Materials and render textures
    Material rayTracingMaterial;
    
    // Cached values for optimization
    private Camera cachedCamera;
    private int lastScreenWidth = -1;
    private int lastScreenHeight = -1;
    private Matrix4x4 lastCamMatrix;
    private bool needsCameraUpdate = true;

    void Start()
    {
        lastTime = Time.realtimeSinceStartup;
        cachedCamera = GetComponent<Camera>();
        
        if (Application.isPlaying && enableFirstPersonControls)
        {
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
            cursorLocked = true;
        }
    }

    void Update()
    {
        if (!Application.isPlaying) return;

        float currentTime = Time.realtimeSinceStartup;
        deltaTime += (currentTime - lastTime - deltaTime) * 0.1f;
        fpsAccumulator += currentTime - lastTime;
        lastTime = currentTime;
        frameCount++;

        if (fpsAccumulator >= fpsUpdateInterval)
        {
            fps = frameCount / fpsAccumulator;
            frameCount = 0;
            fpsAccumulator = 0.0f;
        }

        if (enableFirstPersonControls)
        {
            HandleFirstPersonControls();
            needsCameraUpdate = true;
        }

        UpdateSolarSystem();

        // Atalhos para visão relativística
        if (Input.GetKeyDown(KeyCode.H))
        {
            ToggleRelativisticView();
        }

        // Atalho para modo ponto
        if (Input.GetKeyDown(KeyCode.P))
        {
            TogglePointMode();
        }

        if (Input.GetKey(KeyCode.L))
        {
            float msec = deltaTime * 1000.0f;
            string text = string.Format("FPS: {0:0.} ({1:0.0} ms)", fps, msec);
            if (fps != 0) Debug.Log(text);
        }
    }

    void HandleFirstPersonControls()
    {
        if (Input.GetKeyDown(KeyCode.Escape))
        {
            cursorLocked = !cursorLocked;
            Cursor.lockState = cursorLocked ? CursorLockMode.Locked : CursorLockMode.None;
            Cursor.visible = !cursorLocked;
        }

        if (cursorLocked)
        {
            float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
            float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity;

            xRotation -= mouseY;
            xRotation = Mathf.Clamp(xRotation, -90f, 90f);
            yRotation += mouseX;

            transform.rotation = Quaternion.Euler(xRotation, yRotation, 0f);

            Vector3 move = Vector3.zero;

            if (Input.GetKey(KeyCode.W)) move += transform.forward;
            if (Input.GetKey(KeyCode.S)) move -= transform.forward;
            if (Input.GetKey(KeyCode.A)) move -= transform.right;
            if (Input.GetKey(KeyCode.D)) move += transform.right;
            if (Input.GetKey(KeyCode.Space)) move += Vector3.up;
            if (Input.GetKey(KeyCode.LeftShift)) move -= Vector3.up;

            if (move != Vector3.zero)
            {
                move = move.normalized * moveSpeed * Time.deltaTime;
                transform.position += move;
            }
        }
    }

    void OnRenderImage(RenderTexture src, RenderTexture target)
    {
        if (!Application.isPlaying)
        {
            Graphics.Blit(src, target);
            return;
        }

        bool isSceneCam = Camera.current.name == "SceneCamera";

        if (isSceneCam)
        {
            Graphics.Blit(src, target);
        }
        else
        {
            // Check if screen resolution changed
            if (Screen.width != lastScreenWidth || Screen.height != lastScreenHeight)
            {
                lastScreenWidth = Screen.width;
                lastScreenHeight = Screen.height;
                needsCameraUpdate = true;
            }

            InitFrame(Camera.current);
            Graphics.Blit(null, target, rayTracingMaterial);
        }
    }

    void InitFrame(Camera cam)
    {
        ShaderHelper.InitMaterial(rayTracingShader, ref rayTracingMaterial);
        
        // Only update camera params if needed
        if (needsCameraUpdate || cam.transform.localToWorldMatrix != lastCamMatrix)
        {
            UpdateCameraParams(cam);
            lastCamMatrix = cam.transform.localToWorldMatrix;
            needsCameraUpdate = false;
        }
        
        SetShaderParams();
    }
     
    public enum Metric { Newton = 0, Schwarzschild = 1, Kerr = 2 }
    public enum Integrator { Euler = 0, RK4 = 1 }
     
    [Header("Relativistic Physics")]
    public Metric selectedMetric = Metric.Schwarzschild;
    public Integrator selectedIntegrator = Integrator.Euler;
    public float spinSpeed = 0.5f;

    [Header("Scene Selection")] public int currentScene = 1;

    [Header("Cena 6 - Sistema Solar")]
    [SerializeField] float systemTimeMultiplier = 0f;
    public float baseBlackHoleMass = 1.989e30f * 10f;
    [SerializeField] Cubemap milkyWaySkybox;
    
    [SerializeField] Texture2D[] solarSystemTextures = new Texture2D[10];
    
    [SerializeField] float[] planetOrbitalOffsets = new float[10];
    
    private Vector4[] bodyPositionsAndRadii = new Vector4[10];
    private float[] bodyMasses = new float[10];
    private float systemCurrentTime = 0f;

    void UpdateSolarSystem()
    {
        if (currentScene != 6) return;

        systemCurrentTime += Time.deltaTime * systemTimeMultiplier;

        float[] baseRadii = { 5.0f, 0.3f, 0.7f, 0.8f, 0.2f, 0.4f, 2.5f, 2.0f, 1.5f, 1.4f };
        float[] distances = { 0.0f, 10f, 18f, 28f, 2.5f, 40f, 65f, 95f, 125f, 150f };
        float[] orbitSpeeds = { 0.0f, 4.1f, 1.6f, 1.0f, 13.3f, 0.5f, 0.08f, 0.03f, 0.01f, 0.005f };
        float[] massPercentages = { 1.0f, 0.005f, 0.008f, 0.01f, 0.001f, 0.005f, 0.1f, 0.08f, 0.04f, 0.03f };

        Vector3 sunPos = new Vector3(0, 0, -150f);

        for (int i = 0; i < 10; i++)
        {
            Vector3 pos;
            if (i == 0)
            {
                pos = sunPos;
            }
            else if (i == 4)
            {
                float offset = planetOrbitalOffsets[i] * Mathf.Deg2Rad;
                float earthOffset = planetOrbitalOffsets[3] * Mathf.Deg2Rad;
                float earthX = sunPos.x + Mathf.Cos(systemCurrentTime * orbitSpeeds[3] + earthOffset) * distances[3];
                float earthZ = sunPos.z + Mathf.Sin(systemCurrentTime * orbitSpeeds[3] + earthOffset) * distances[3];
                pos = new Vector3(earthX, 0, earthZ);
                pos.x += Mathf.Cos(systemCurrentTime * orbitSpeeds[i] + offset) * distances[i];
                pos.z += Mathf.Sin(systemCurrentTime * orbitSpeeds[i] + offset) * distances[i];
            }
            else
            {
                float offset = planetOrbitalOffsets[i] * Mathf.Deg2Rad;
                pos.x = sunPos.x + Mathf.Cos(systemCurrentTime * orbitSpeeds[i] + offset) * distances[i];
                pos.y = sunPos.y;
                pos.z = sunPos.z + Mathf.Sin(systemCurrentTime * orbitSpeeds[i] + offset) * distances[i];
            }

            bodyPositionsAndRadii[i] = new Vector4(pos.x, pos.y, pos.z, baseRadii[i]);
            bodyMasses[i] = baseBlackHoleMass * massPercentages[i];
        }
    }

    void SetShaderParams()
    {
        rayTracingMaterial.SetVector("_LightDirection", lightDirection.normalized);
        rayTracingMaterial.SetFloat("_DirectionalLightIntensity", directionalLightIntensity);
        rayTracingMaterial.SetInt("_UseHyperbolicView", useRelativisticView ? 1 : 0);
        rayTracingMaterial.SetInt("_UsePointMode", usePointMode ? 1 : 0);
        rayTracingMaterial.SetFloat("_StepSize", stepSize);
        rayTracingMaterial.SetInt("_MaxSteps", maxSteps);
         
        rayTracingMaterial.SetInt("_Metric", (int)selectedMetric);
        rayTracingMaterial.SetInt("_Integrator", (int)selectedIntegrator);
        rayTracingMaterial.SetFloat("_SpinSpeed", spinSpeed);
        rayTracingMaterial.SetInt("_CurrentScene", currentScene);
        
        SetupSkyboxTexture();

        if (currentScene == 6)
        {
            rayTracingMaterial.SetVectorArray("_Bodies", bodyPositionsAndRadii);
            rayTracingMaterial.SetFloatArray("_BodyMasses", bodyMasses);
            rayTracingMaterial.SetInt("_UseMilkyWay", milkyWaySkybox != null ? 1 : 0);
            if (milkyWaySkybox != null) rayTracingMaterial.SetTexture("_MilkyWayTex", milkyWaySkybox);
            
            for (int i = 0; i < 10; i++)
            {
                if (solarSystemTextures.Length > i && solarSystemTextures[i] != null)
                    rayTracingMaterial.SetTexture("_PlanetTex" + i, solarSystemTextures[i]);
            }
        }
    }

    void SetupSkyboxTexture()
    {
        // Scenes 1 and 4 use colors instead of skybox texture
        if (currentScene == 1 || currentScene == 4)
        {
            rayTracingMaterial.SetInt("_UseSkyboxTexture", 0);
            return;
        }

        if (RenderSettings.skybox == null)
        {
            rayTracingMaterial.SetInt("_UseSkyboxTexture", 0);
            return;
        }

        // Skybox/6 Sided usa 6 texturas 2D, não cubemap
        // Outros shaders de skybox podem ter cubemap em propriedades diferentes
        string[] cubemapProperties = new string[]
        {
            "_Tex",          // Skybox/Cubemap
            "_Cube",         // Skybox/Procedural
            "_MainTex",      // Variação comum
            "_TexCube",      // Alternativa
            "_SkyboxTexture" // Custom
        };

        Texture skyboxTexture = null;
        foreach (string prop in cubemapProperties)
        {
            if (RenderSettings.skybox.HasProperty(prop))
            {
                skyboxTexture = RenderSettings.skybox.GetTexture(prop);
                if (skyboxTexture != null && skyboxTexture is Cubemap)
                {
                    rayTracingMaterial.SetInt("_UseSkyboxTexture", 1);
                    rayTracingMaterial.SetTexture("_SkyboxTexture", skyboxTexture);
                    return;
                }
            }
        }

        // Se não achou cubemap, usar fallback colorido
        rayTracingMaterial.SetInt("_UseSkyboxTexture", 0);
    }

    void UpdateCameraParams(Camera cam)
    {
        float planeHeight = focusDistance * Tan(cam.fieldOfView * 0.5f * Deg2Rad) * 2;
        float planeWidth = planeHeight * cam.aspect;
        rayTracingMaterial.SetVector("ViewParams", new Vector3(planeWidth, planeHeight, focusDistance));
        rayTracingMaterial.SetMatrix("CamLocalToWorldMatrix", cam.transform.localToWorldMatrix);
    }

    // --- Métodos Públicos ---

    public void ToggleRelativisticView()
    {
        useRelativisticView = !useRelativisticView;
        Debug.Log($"Relativistic View: {(useRelativisticView ? "ENABLED" : "DISABLED")}");
    }
    
    public void TogglePointMode()
    {
        usePointMode = !usePointMode;
        Debug.Log($"Point Mode: {(usePointMode ? "ENABLED" : "DISABLED")}");
    }

    public void SetRelativisticView(bool enabled)
    {
        useRelativisticView = enabled;
        Debug.Log($"Relativistic View: {(useRelativisticView ? "ENABLED" : "DISABLED")}");
    }
    
    public void SetPointMode(bool enabled)
    {
        usePointMode = enabled;
        Debug.Log($"Point Mode: {(usePointMode ? "ENABLED" : "DISABLED")}");
    }

    public bool IsRelativisticViewEnabled()
    {
        return useRelativisticView;
    }
    
    public bool IsPointModeEnabled()
    {
        return usePointMode;
    }

    public float GetStepSize()
    {
        return stepSize;
    }

    public int GetMaxSteps()
    {
        return maxSteps;
    } 

    public void ForceCameraUpdate()
    {
        needsCameraUpdate = true;
    }

    public void SetPlanetOrbitalOffset(int bodyIndex, float degrees)
    {
        if (bodyIndex >= 0 && bodyIndex < 10)
        {
            planetOrbitalOffsets[bodyIndex] = degrees;
        }
    }

    public float GetPlanetOrbitalOffset(int bodyIndex)
    {
        if (bodyIndex >= 0 && bodyIndex < 10)
        {
            return planetOrbitalOffsets[bodyIndex];
        }
        return 0f;
    }
}