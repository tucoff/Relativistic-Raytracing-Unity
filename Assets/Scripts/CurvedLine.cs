using UnityEngine;
using System.Collections.Generic;

public class CurvedLineGenerator : MonoBehaviour
{
    private LineRenderer lineRenderer;
    [Range(2, 100)]
    public int numPoints = 200;
    public float curveStrength = 1.0f;
    public float lineLength = 100.0f;
    
    [Header("Gravitational Settings")]
    public float gravitationalConstant = 6.67430e-11f;
    public float lightSpeed = 299792458.0f;
    public float massInfluenceRadius = 100.0f;
    public float gravitationalStrength = 1.0f;

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
        
        UpdateMassiveSpheres();
    }
    
    void UpdateMassiveSpheres()
    {
        massiveSpheres = FindObjectsOfType<RayTracedSphere>();
    }

    void Update()
    {
        if (targetCameraTransform == null) return;

        Vector3[] points = new Vector3[numPoints];
        lineRenderer.positionCount = numPoints;

        Vector3 currentPosition = targetCameraTransform.position;
        Vector3 currentDirection = useCustomDirection ? customDirection.normalized : targetCameraTransform.forward;
        
        points[0] = currentPosition;

        float stepSize = lineLength / (numPoints - 1);

        for (int i = 1; i < numPoints; i++)
        {
            // Move along the current direction
            currentPosition += currentDirection * stepSize;
            
            // Calculate the gravitational deflection for the new position and update the direction
            Vector3 gravitationalDeflection = CalculateGravitationalDeflection(currentPosition, targetCameraTransform.position, currentDirection);
            
            // The deflection is a change in direction, so we need to add it to the current direction
            currentDirection += gravitationalDeflection;
            currentDirection.Normalize(); // Keep the direction vector a unit vector

            // Add an original curve for the 'targetCameraTransform.up' effect if you still want it
            // This part might need adjustment depending on how you want this effect to interact with gravity
            Vector3 originalCurve = targetCameraTransform.up * Mathf.Sin((float)i / (numPoints - 1) * Mathf.PI) * curveStrength;

            points[i] = currentPosition + originalCurve;
        }

        lineRenderer.SetPositions(points);
    }
    
    Vector3 CalculateGravitationalDeflection(Vector3 rayPosition, Vector3 rayOrigin, Vector3 rayDirection)
    {
        Vector3 totalDirectionChange = Vector3.zero;
        
        if (massiveSpheres == null) return totalDirectionChange;
        
        foreach (RayTracedSphere sphere in massiveSpheres)
        {
            if (sphere == null) continue;
            
            Vector3 spherePos = sphere.transform.position;
            float mass = sphere.massa;
            
            Vector3 toSphere = spherePos - rayPosition;
            float distance = toSphere.magnitude;
            
            if (distance > massInfluenceRadius || distance < 0.1f) continue;
            
            // Calculate the impact parameter as the perpendicular distance from the sphere to the current ray direction
            Vector3 closestPointOnRay = rayPosition - (Vector3.Dot(toSphere, rayDirection)) * rayDirection;
            float impactParameter = closestPointOnRay.magnitude;
            
            // Re-check the logic for deflection angle, making sure it applies to the impact parameter
            // The formula is an approximation for small angles, which is fine for most game scenarios
            float deflectionAngle = 4.0f * gravitationalConstant * mass / (lightSpeed * lightSpeed * Mathf.Max(impactParameter, 0.1f));
            deflectionAngle *= gravitationalStrength;
            
            // The direction of deflection is perpendicular to both the ray direction and the vector from the ray to the sphere
            Vector3 deflectionDirection = Vector3.Cross(rayDirection, Vector3.Cross(toSphere, rayDirection)).normalized;
            
            // The change in direction is a vector with the magnitude of the angle and the calculated direction
            totalDirectionChange += deflectionDirection * deflectionAngle;
        }
        
        return totalDirectionChange;
    }
    
    public void RefreshMassiveSpheres()
    {
        UpdateMassiveSpheres();
    }
}