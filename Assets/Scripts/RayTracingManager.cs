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
    [SerializeField] float stepSize = 0.1f;
    [SerializeField] int maxSteps = 100;

    [Header("View Settings")]
    [SerializeField] bool showFPS = true;

    [Header("First Person Controls")]
    [SerializeField] float moveSpeed = 5f;
    [SerializeField] float mouseSensitivity = 2f;
    [SerializeField] bool enableFirstPersonControls = true;

    [Header("References")]
    [SerializeField] Shader rayTracingShader;

    [Header("Info")]
    [SerializeField] int numMeshChunks;
    [SerializeField] int numTriangles;
    [SerializeField] int numEmissiveSpheres;

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

    // Buffers
    ComputeBuffer sphereBuffer;
    ComputeBuffer triangleBuffer;
    ComputeBuffer meshInfoBuffer;

    List<Triangle> allTriangles;
    List<MeshInfo> allMeshInfo;

    void Start()
    {
        lastTime = Time.realtimeSinceStartup;
        
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
        }

        // Atalhos para visão relativística
        if (Input.GetKeyDown(KeyCode.H))
        {
            ToggleRelativisticView();
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

    void OnGUI()
    {
        if (showFPS)
        {
            int w = Screen.width, h = Screen.height;
            GUIStyle style = new GUIStyle();
            Rect rect = new Rect(10, 10, w, h * 2 / 100);
            style.alignment = TextAnchor.UpperLeft;
            style.fontSize = h * 2 / 100;
            style.normal.textColor = Color.yellow;
            float msec = deltaTime * 1000.0f;
            string text = string.Format("FPS: {0:0.} ({1:0.0} ms)", fps, msec);
            GUI.Label(rect, text, style);

            rect.y += 25;
            style.normal.textColor = Color.white;
            string rayTracingInfo = string.Format("Triangles: {0} | Meshes: {1} | Emissive Spheres: {2}",
                numTriangles, numMeshChunks, numEmissiveSpheres);
            GUI.Label(rect, rayTracingInfo, style);

            rect.y += 25;
            style.normal.textColor = Application.isPlaying ? Color.green : Color.cyan;
            string modeText = Application.isPlaying ? "RUNTIME" : "EDITOR";
            GUI.Label(rect, modeText, style);

            if (Application.isPlaying && enableFirstPersonControls)
            {
                rect.y += 25;
                style.normal.textColor = cursorLocked ? Color.green : Color.red;
                string controlsText = cursorLocked ? "WASD: Move | Mouse: Look | Space/Shift: Up/Down | ESC: Unlock" : "Press ESC to enable controls";
                GUI.Label(rect, controlsText, style);
            }

            // Mostrar status da visão relativística
            rect.y += 25;
            style.normal.textColor = useRelativisticView ? Color.cyan : Color.gray;
            string relativisticText = useRelativisticView ? 
                $"Relativistic View: ON | Press H to disable" : 
                "Relativistic View: OFF | Press H to enable";
            GUI.Label(rect, relativisticText, style);
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
            InitFrame();
            Graphics.Blit(null, target, rayTracingMaterial);
        }
    }

    void InitFrame()
    {
        ShaderHelper.InitMaterial(rayTracingShader, ref rayTracingMaterial);
        UpdateCameraParams(Camera.current);
        CreateSpheres();
        CreateMeshes();
        SetShaderParams();
    }

    void SetShaderParams()
    {
        rayTracingMaterial.SetVector("_LightDirection", lightDirection.normalized);
        rayTracingMaterial.SetFloat("_DirectionalLightIntensity", directionalLightIntensity);
        rayTracingMaterial.SetInt("_UseHyperbolicView", useRelativisticView ? 1 : 0);
        rayTracingMaterial.SetFloat("_StepSize", stepSize);
        rayTracingMaterial.SetInt("_MaxSteps", maxSteps);
    }

    void UpdateCameraParams(Camera cam)
    {
        float planeHeight = focusDistance * Tan(cam.fieldOfView * 0.5f * Deg2Rad) * 2;
        float planeWidth = planeHeight * cam.aspect;
        rayTracingMaterial.SetVector("ViewParams", new Vector3(planeWidth, planeHeight, focusDistance));
        rayTracingMaterial.SetMatrix("CamLocalToWorldMatrix", cam.transform.localToWorldMatrix);
    }

    void CreateMeshes()
    {
        RayTracedMesh[] meshObjects = FindObjectsByType<RayTracedMesh>(FindObjectsSortMode.None);

        allTriangles ??= new List<Triangle>();
        allMeshInfo ??= new List<MeshInfo>();
        allTriangles.Clear();
        allMeshInfo.Clear();

        for (int i = 0; i < meshObjects.Length; i++)
        {
            MeshChunk[] chunks = meshObjects[i].GetSubMeshes();
            foreach (MeshChunk chunk in chunks)
            {
                RayTracingMaterial material = meshObjects[i].GetMaterial(chunk.subMeshIndex);
                allMeshInfo.Add(new MeshInfo(allTriangles.Count, chunk.triangles.Length, material, chunk.bounds));
                allTriangles.AddRange(chunk.triangles);
            }
        }

        numMeshChunks = allMeshInfo.Count;
        numTriangles = allTriangles.Count;

        ShaderHelper.CreateStructuredBuffer(ref triangleBuffer, allTriangles);
        ShaderHelper.CreateStructuredBuffer(ref meshInfoBuffer, allMeshInfo);
        rayTracingMaterial.SetBuffer("Triangles", triangleBuffer);
        rayTracingMaterial.SetBuffer("AllMeshInfo", meshInfoBuffer);
        rayTracingMaterial.SetInt("NumMeshes", allMeshInfo.Count);
    }

    void CreateSpheres()
    {
        RayTracedSphere[] sphereObjects = FindObjectsByType<RayTracedSphere>(FindObjectsSortMode.None);
        Sphere[] spheres = new Sphere[sphereObjects.Length];

        int emissiveCount = 0;
        for (int i = 0; i < sphereObjects.Length; i++)
        {
            spheres[i] = new Sphere()
            {
                position = sphereObjects[i].transform.position,
                radius = sphereObjects[i].transform.localScale.x * 0.5f,
                material = sphereObjects[i].material,
                massa = sphereObjects[i].massa
            };

            if (sphereObjects[i].material.emissionStrength > 0)
            {
                emissiveCount++;
            }
        }

        numEmissiveSpheres = emissiveCount;

        ShaderHelper.CreateStructuredBuffer(ref sphereBuffer, spheres);
        rayTracingMaterial.SetBuffer("Spheres", sphereBuffer);
        rayTracingMaterial.SetInt("NumSpheres", sphereObjects.Length);
    }

    void OnDisable()
    {
        ShaderHelper.Release(sphereBuffer, triangleBuffer, meshInfoBuffer);
    }

    // --- Métodos Públicos ---

    public void ToggleRelativisticView()
    {
        useRelativisticView = !useRelativisticView;
        Debug.Log($"Relativistic View: {(useRelativisticView ? "ENABLED" : "DISABLED")}");
    }

    public void SetRelativisticView(bool enabled)
    {
        useRelativisticView = enabled;
        Debug.Log($"Relativistic View: {(useRelativisticView ? "ENABLED" : "DISABLED")}");
    }

    public bool IsRelativisticViewEnabled()
    {
        return useRelativisticView;
    }

    public float GetStepSize()
    {
        return stepSize;
    }

    public int GetMaxSteps()
    {
        return maxSteps;
    }

    void OnValidate()
    {
        // ... (removido para manter o código conciso)
    }
}