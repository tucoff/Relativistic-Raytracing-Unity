using UnityEngine;
using System.Collections.Generic;

public class CurvedLineGenerator : MonoBehaviour
{
    private LineRenderer lineRenderer;
    private RayTracingManager rayTracingManager;
    private int numPoints;
    public float gravitationalConstant = 6.67430f; 
    public Transform targetCameraTransform; 
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
        
        numPoints = Mathf.Max(2, numPoints);
    }

    Vector3 CalculateGravitationalDeflection(Vector3 rayPosition, float stepSize)
    {

        // TOTAL = (0,0,0)
        Vector3 totalDeflection = Vector3.zero;
        
        if (massiveSpheres == null) return totalDeflection;
        
        // FOR EACH SPHERE
        foreach (RayTracedSphere sphere in massiveSpheres)
        {
            if (sphere == null || sphere.massa <= 0) continue;

            Vector3 spherePos = sphere.transform.position;

            Vector3 toSphere = spherePos - rayPosition;

            // DST 
            float distance = toSphere.magnitude;

            if (distance < 0.1f) continue;

            // DIR
            Vector3 direction = toSphere / distance;

            // DEF (by newtons)
            float deflectionStrength = gravitationalConstant * sphere.massa / (distance * distance);

            // TOTAL += DIR * DEF
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

        // START POINT ON CAMERA POSITION
        Vector3 currentPosition = targetCameraTransform.position;
        // START VECTOR ON CAMERA LOOK DIRECTION
        Vector3 currentDirection = targetCameraTransform.forward;
        
        points[0] = currentPosition;

        // STEP SIZE 
        float stepSize = rayTracingManager.GetStepSize(); // Use exact same stepSize as shader

        // ITERATE FOR EACH POINT / STEP
        for (int i = 1; i < numPoints; i++)
        {
            RaycastHit hit;
        
            if (Physics.Raycast(currentPosition, currentDirection, out hit, stepSize))
            {
                points[i] = hit.point;
                break; 
            }

            Vector3 gravitationalDeflection = CalculateGravitationalDeflection(currentPosition, stepSize);

            // ADD TOTAL TO LAST DIR AND NORMALIZE
            currentDirection += gravitationalDeflection;
            currentDirection = currentDirection.normalized;

            // MOVE CURRENT POSITION
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