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
    [SerializeField, Min(0.001f)] float stepSize = 0.1f;
    [SerializeField, Min(1)] int maxSteps = 1000;
    
    [Header("Point Mode Settings")]
    [SerializeField] bool usePointMode = false;

    [Header("View Settings")]
    [SerializeField] bool showFPS = true;

    [Header("First Person Controls")]
    [SerializeField] float moveSpeed = 5f;
    [SerializeField] float mouseSensitivity = 2f;
    [SerializeField] bool enableFirstPersonControls = true;

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
    [SerializeField] float spinSpeed = 0.5f;
     
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
}