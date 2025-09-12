using UnityEngine;
using System.Collections.Generic;

public class CurvedLineGenerator : MonoBehaviour
{
    private LineRenderer lineRenderer;
    private RayTracingManager rayTracingManager;

    // Parameters now calculated from RayTracingManager instead of Unity interface
    private int numPoints = 200;
    private float lineLength = 100.0f;
    
    public float curveStrength = 1.0f;

    [Header("Gravitational Settings")]
    public float gravitationalConstant = 6.67430f; //* Mathf.Pow(10, -11);

    [Header("Directional Settings")]
    public Transform targetCameraTransform; // A câmera 1 que dita a origem e direção
    public bool useCustomDirection = false;
    public Vector3 customDirection = Vector3.forward;
    
    private RayTracedSphere[] massiveSpheres;

    void Awake()
    {
        lineRenderer = GetComponent<LineRenderer>();
        if (lineRenderer == null)
        {
            Debug.LogError("Line Renderer component not found!");
            return;
        }
        
        // Find the RayTracingManager in the scene
        rayTracingManager = FindFirstObjectByType<RayTracingManager>();
        if (rayTracingManager == null)
        {
            Debug.LogError("RayTracingManager not found! CurvedLineGenerator requires RayTracingManager to get step parameters.");
        }
        
        UpdateMassiveSpheres();
        UpdateParametersFromRayTracingManager();
    }
    
    void UpdateMassiveSpheres()
    {
        massiveSpheres = FindObjectsByType<RayTracedSphere>(FindObjectsSortMode.None);
    }

    void UpdateParametersFromRayTracingManager()
    {
        if (rayTracingManager == null) return;

        int newMaxSteps = rayTracingManager.GetMaxSteps();
        float newStepSize = rayTracingManager.GetStepSize();
        
        numPoints = newMaxSteps;
        lineLength = newStepSize * newMaxSteps; 
        
        numPoints = Mathf.Max(2, numPoints);
        lineLength = Mathf.Max(0.1f, lineLength);
    }

    Vector3 CalculateGravitationalDeflection(Vector3 rayPosition, float stepSize)
    {
        Vector3 totalDeflection = Vector3.zero;
        
        if (massiveSpheres == null) return totalDeflection;
        
        foreach (RayTracedSphere sphere in massiveSpheres)
        {
            if (sphere == null || sphere.massa <= 0) continue;
            
            Vector3 spherePos = sphere.transform.position;
            
            Vector3 toSphere = spherePos - rayPosition;

            float distance = toSphere.magnitude;
            
            if (distance < 0.1f) continue;
            
            Vector3 direction = toSphere / distance;
            
            float deflectionStrength = gravitationalConstant * sphere.massa / (distance * distance);
            
            totalDeflection += direction * deflectionStrength;
        }
        
        if (totalDeflection.magnitude > 0)
        {
            return totalDeflection * stepSize;
        }
        
        return Vector3.zero;
    }

    void Update()
    {
        if (targetCameraTransform == null) return;

        // Update parameters from RayTracingManager each frame in case they changed
        UpdateParametersFromRayTracingManager();

        Vector3[] points = new Vector3[numPoints];
        lineRenderer.positionCount = numPoints;

        Vector3 currentPosition = targetCameraTransform.position;
        Vector3 currentDirection = useCustomDirection ? 
            (targetCameraTransform.rotation * customDirection).normalized : 
            targetCameraTransform.forward;
        
        points[0] = currentPosition;

        float stepSize = rayTracingManager.GetStepSize(); // Use exact same stepSize as shader

        for (int i = 1; i < numPoints; i++)
        {
            Vector3 gravitationalDeflection = CalculateGravitationalDeflection(currentPosition, stepSize);
            
            currentDirection += gravitationalDeflection;

            currentDirection.Normalize();
            
            currentPosition += currentDirection * stepSize;

            points[i] = currentPosition;
        }

        lineRenderer.SetPositions(points);
    }
    
    public void RefreshMassiveSpheres()
    {
        UpdateMassiveSpheres();
        UpdateParametersFromRayTracingManager();
    }
}