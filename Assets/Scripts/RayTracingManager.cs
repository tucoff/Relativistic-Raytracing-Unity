using System.Collections.Generic;
using UnityEngine;
using static UnityEngine.Mathf;

[ExecuteAlways, ImageEffectAllowedInSceneView]
public class RayTracingManager : MonoBehaviour
{
	// Raytracer is currently *very* slow, so limit the number of triangles allowed per mesh
	public const int TriangleLimit = 1500;

	[Header("Ray Tracing Settings")]
	[SerializeField, Range(0, 32)] int maxBounceCount = 4;
	[SerializeField, Range(0, 64)] int numRaysPerPixel = 2;
	[SerializeField, Min(0)] float defocusStrength = 0;
	[SerializeField, Min(0)] float divergeStrength = 0.3f;
	[SerializeField, Min(0)] float focusDistance = 1;
	[SerializeField] EnvironmentSettings environmentSettings;

	[Header("View Settings")]
	[SerializeField] bool showFPS = true;
	
	[Header("First Person Controls")]
	[SerializeField] float moveSpeed = 5f;
	[SerializeField] float mouseSensitivity = 2f;
	[SerializeField] bool enableFirstPersonControls = true;
	
	[Header("References")]
	[SerializeField] Shader rayTracingShader;
	[SerializeField, HideInInspector] Shader accumulateShader;

	[Header("Info")]
	[SerializeField] int numRenderedFrames;
	[SerializeField] int numMeshChunks;
	[SerializeField] int numTriangles;

	// FPS tracking variables
	private float deltaTime = 0.0f;
	private float fps = 0.0f;
	private int frameCount = 0;
	private float fpsUpdateInterval = 0.5f; // Update FPS every 0.5 seconds
	private float fpsAccumulator = 0.0f;
	private float lastTime = 0.0f;

	// Camera movement detection for accumulation reset
	private Vector3 lastCameraPosition;
	private Quaternion lastCameraRotation;
	private bool sceneChanged = true;
	
	// Parameter change detection
	private int lastMaxBounceCount;
	private int lastNumRaysPerPixel;
	private float lastDefocusStrength;
	private float lastDivergeStrength;
	
	// First person controls
	private float xRotation = 0f;
	private float yRotation = 0f;
	private bool cursorLocked = false;

	// Materials and render textures
	Material rayTracingMaterial;
	Material accumulateMaterial;
	RenderTexture resultTexture;

	// Buffers
	ComputeBuffer sphereBuffer;
	ComputeBuffer triangleBuffer;
	ComputeBuffer meshInfoBuffer;

	List<Triangle> allTriangles;
	List<MeshInfo> allMeshInfo;

	void Start()
	{
		numRenderedFrames = 0;
		lastTime = Time.realtimeSinceStartup;
		
		// Initialize first person controls
		if (Application.isPlaying && enableFirstPersonControls)
		{
			Cursor.lockState = CursorLockMode.Locked;
			Cursor.visible = false;
			cursorLocked = true;
		}
	}

	void Update()
	{
		// Só atualiza durante runtime
		if (!Application.isPlaying) return;

		// Calculate FPS usando Time.realtimeSinceStartup para funcionar no editor
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
		
		// Check if camera moved (para reset de accumulation)
		Camera cam = Camera.current ?? Camera.main;
		if (cam != null)
		{
			if (cam.transform.position != lastCameraPosition || 
				cam.transform.rotation != lastCameraRotation)
			{
				sceneChanged = true;
				lastCameraPosition = cam.transform.position;
				lastCameraRotation = cam.transform.rotation;
			}
		}
		
		// Check if ray tracing parameters changed
		if (maxBounceCount != lastMaxBounceCount ||
			numRaysPerPixel != lastNumRaysPerPixel ||
			!Mathf.Approximately(defocusStrength, lastDefocusStrength) ||
			!Mathf.Approximately(divergeStrength, lastDivergeStrength))
		{
			sceneChanged = true;
			lastMaxBounceCount = maxBounceCount;
			lastNumRaysPerPixel = numRaysPerPixel;
			lastDefocusStrength = defocusStrength;
			lastDivergeStrength = divergeStrength;
		}
		
		// Handle first person controls
		if (enableFirstPersonControls)
		{
			HandleFirstPersonControls();
		}
	}
	
	void HandleFirstPersonControls()
	{
		// Toggle cursor lock with Escape
		if (Input.GetKeyDown(KeyCode.Escape))
		{
			cursorLocked = !cursorLocked;
			Cursor.lockState = cursorLocked ? CursorLockMode.Locked : CursorLockMode.None;
			Cursor.visible = !cursorLocked;
		}
		
		if (cursorLocked)
		{
			// Mouse look
			float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
			float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity;
			
			// Acumular rotações
			xRotation -= mouseY;
			xRotation = Mathf.Clamp(xRotation, -90f, 90f); // Limita apenas pitch (vertical)
			yRotation += mouseX; // Rotação livre no eixo Y (horizontal)
			
			// Aplicar rotação combinada
			transform.rotation = Quaternion.Euler(xRotation, yRotation, 0f);
			
			// Movement relative to camera direction
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
			
			// Additional ray tracing info
			rect.y += 25;
			style.normal.textColor = Color.white;
			string rayTracingInfo = string.Format("Triangles: {0} | Meshes: {1} | Frames: {2}", 
				numTriangles, numMeshChunks, numRenderedFrames);
			GUI.Label(rect, rayTracingInfo, style);
			
			// Runtime vs Editor indicator
			rect.y += 25;
			style.normal.textColor = Application.isPlaying ? Color.green : Color.cyan;
			string modeText = Application.isPlaying ? "RUNTIME" : "EDITOR";
			GUI.Label(rect, modeText, style);
			
			// First person controls info
			if (Application.isPlaying && enableFirstPersonControls)
			{
				rect.y += 25;
				style.normal.textColor = cursorLocked ? Color.green : Color.red;
				string controlsText = cursorLocked ? "WASD: Move | Mouse: Look | Space/Shift: Up/Down | ESC: Unlock" : "Press ESC to enable controls";
				GUI.Label(rect, controlsText, style);
			}
		}
	}

	// Called after any camera (e.g. game or scene camera) has finished rendering into the src texture
	void OnRenderImage(RenderTexture src, RenderTexture target)
	{
		// Só executa ray tracing durante runtime (não no editor)
		if (!Application.isPlaying)
		{
			Graphics.Blit(src, target); // Mostra render normal da câmera
			return;
		}

		bool isSceneCam = Camera.current.name == "SceneCamera";

		if (isSceneCam)
		{
			Graphics.Blit(src, target); // Scene camera sempre mostra render normal
		}
		else
		{
			InitFrame();

			// Reset accumulation if scene changed
			if (sceneChanged)
			{
				numRenderedFrames = 0;
				sceneChanged = false;
			}

			// Create copy of prev frame
			RenderTexture prevFrameCopy = RenderTexture.GetTemporary(src.width, src.height, 0, ShaderHelper.RGBA_SFloat);
			Graphics.Blit(resultTexture, prevFrameCopy);

			// Run the ray tracing shader and draw the result to a temp texture
			rayTracingMaterial.SetInt("Frame", numRenderedFrames);
			RenderTexture currentFrame = RenderTexture.GetTemporary(src.width, src.height, 0, ShaderHelper.RGBA_SFloat);
			Graphics.Blit(null, currentFrame, rayTracingMaterial);

			// Accumulate
			accumulateMaterial.SetInt("_Frame", numRenderedFrames);
			accumulateMaterial.SetTexture("_PrevFrame", prevFrameCopy);
			Graphics.Blit(currentFrame, resultTexture, accumulateMaterial);

			// Draw result to screen
			Graphics.Blit(resultTexture, target);

			// Release temps
			RenderTexture.ReleaseTemporary(currentFrame);
			RenderTexture.ReleaseTemporary(prevFrameCopy);

			numRenderedFrames++;
		}
	}

	void InitFrame()
	{
		// Create materials used in blits
		ShaderHelper.InitMaterial(rayTracingShader, ref rayTracingMaterial);
		ShaderHelper.InitMaterial(accumulateShader, ref accumulateMaterial);
		// Create result render texture
		ShaderHelper.CreateRenderTexture(ref resultTexture, Screen.width, Screen.height, FilterMode.Bilinear, ShaderHelper.RGBA_SFloat, "Result");

		// Update data
		UpdateCameraParams(Camera.current);
		CreateSpheres();
		CreateMeshes();
		SetShaderParams();

	}

	void SetShaderParams()
	{
		rayTracingMaterial.SetInt("MaxBounceCount", maxBounceCount);
		rayTracingMaterial.SetInt("NumRaysPerPixel", numRaysPerPixel);
		rayTracingMaterial.SetFloat("DefocusStrength", defocusStrength);
		rayTracingMaterial.SetFloat("DivergeStrength", divergeStrength);

		// Garantir que environment sempre tem valores válidos
		bool envEnabled = !ReferenceEquals(environmentSettings, null) && environmentSettings.enabled;
		rayTracingMaterial.SetInteger("EnvironmentEnabled", envEnabled ? 1 : 0);
		
		if (envEnabled)
		{
			rayTracingMaterial.SetColor("GroundColour", environmentSettings.groundColour);
			rayTracingMaterial.SetColor("SkyColourHorizon", environmentSettings.skyColourHorizon);
			rayTracingMaterial.SetColor("SkyColourZenith", environmentSettings.skyColourZenith);
			rayTracingMaterial.SetFloat("SunFocus", environmentSettings.sunFocus);
			rayTracingMaterial.SetFloat("SunIntensity", environmentSettings.sunIntensity);
		}
		else
		{
			// Valores padrão para evitar pontos pretos
			rayTracingMaterial.SetColor("GroundColour", new Color(0.3f, 0.3f, 0.3f));
			rayTracingMaterial.SetColor("SkyColourHorizon", new Color(0.5f, 0.7f, 1.0f));
			rayTracingMaterial.SetColor("SkyColourZenith", new Color(0.2f, 0.5f, 1.0f));
			rayTracingMaterial.SetFloat("SunFocus", 2.0f);
			rayTracingMaterial.SetFloat("SunIntensity", 1.0f);
		}
	}

	void UpdateCameraParams(Camera cam)
	{
		float planeHeight = focusDistance * Tan(cam.fieldOfView * 0.5f * Deg2Rad) * 2;
		float planeWidth = planeHeight * cam.aspect;
		// Send data to shader
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
		// Create sphere data from the sphere objects in the scene
		RayTracedSphere[] sphereObjects = FindObjectsByType<RayTracedSphere>(FindObjectsSortMode.None);
		Sphere[] spheres = new Sphere[sphereObjects.Length];

		for (int i = 0; i < sphereObjects.Length; i++)
		{
			spheres[i] = new Sphere()
			{
				position = sphereObjects[i].transform.position,
				radius = sphereObjects[i].transform.localScale.x * 0.5f,
				material = sphereObjects[i].material
			};
		}

		// Create buffer containing all sphere data, and send it to the shader
		ShaderHelper.CreateStructuredBuffer(ref sphereBuffer, spheres);
		rayTracingMaterial.SetBuffer("Spheres", sphereBuffer);
		rayTracingMaterial.SetInt("NumSpheres", sphereObjects.Length);
	}


	void OnDisable()
	{
		ShaderHelper.Release(sphereBuffer, triangleBuffer, meshInfoBuffer);
		ShaderHelper.Release(resultTexture);
	}

	void OnValidate()
	{
		maxBounceCount = Mathf.Max(0, maxBounceCount);
		numRaysPerPixel = Mathf.Max(1, numRaysPerPixel);
		
		if (!ReferenceEquals(environmentSettings, null))
		{
			environmentSettings.sunFocus = Mathf.Max(1, environmentSettings.sunFocus);
			environmentSettings.sunIntensity = Mathf.Max(0, environmentSettings.sunIntensity);
		}
	}
}