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
    public float gravitationalConstant = 1000000f; // Matches shader #define G

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
            // Calculate the gravitational deflection at current position (similar to shader)
            Vector3 gravitationalDeflection = CalculateGravitationalDeflection(currentPosition, targetCameraTransform.position, currentDirection, stepSize);
            
            // The deflection is a change in direction, so we need to add it to the current direction
            currentDirection += gravitationalDeflection;
            currentDirection.Normalize(); // Keep the direction vector a unit vector
            
            // Move along the updated direction (after deflection)
            currentPosition += currentDirection * stepSize;

            // Store the position after movement
            points[i] = currentPosition;
        }

        lineRenderer.SetPositions(points);
    }
    
    Vector3 CalculateGravitationalDeflection(Vector3 rayPosition, Vector3 rayOrigin, Vector3 rayDirection, float stepSize)
    {
        Vector3 totalDeflection = Vector3.zero;
        
        if (massiveSpheres == null) return totalDeflection;
        
        foreach (RayTracedSphere sphere in massiveSpheres)
        {
            if (sphere == null || sphere.massa <= 0) continue;
            
            Vector3 spherePos = sphere.transform.position;
            float mass = sphere.massa;
            
            Vector3 toSphere = spherePos - rayPosition;
            float distance = toSphere.magnitude;
            
            // Evitar divisão por zero ou valores muito pequenos
            if (distance < 0.1f) continue;
            
            Vector3 direction = toSphere / distance;
            
            // Fórmula gravitacional estabilizada 
            // Usa uma força inversamente proporcional ao quadrado da distância
            float deflectionStrength = gravitationalConstant * mass / (distance * distance);
            
            // A deflexão é na direção da esfera 
            totalDeflection += direction * deflectionStrength;
        }
        
        // Aplicar deflexão de forma suave (using exact shader algorithm)
        if (totalDeflection.magnitude > 0)
        {
            // Normalizar a deflexão total para evitar mudanças bruscas
            float deflectionMagnitude = totalDeflection.magnitude;
            Vector3 deflectionDir = totalDeflection / deflectionMagnitude;
            
            // Aplicar uma deflexão suave proporcional ao step size 
            float smoothDeflection = deflectionMagnitude * stepSize * 0.1f;
            return deflectionDir * smoothDeflection;
        }
        
        return Vector3.zero;
    }
    
    public void RefreshMassiveSpheres()
    {
        UpdateMassiveSpheres();
        UpdateParametersFromRayTracingManager();
    }
}