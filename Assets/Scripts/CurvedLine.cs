using UnityEngine;

public class CurvedLineGenerator : MonoBehaviour
{
    private LineRenderer lineRenderer;
    [Range(2, 100)] public int numPoints = 50;
    public float curveStrength = 1.0f;
    public float lineLength = 10.0f;

    public Transform targetCameraTransform; // A câmera 1 que dita a origem e direção

    void Awake()
    {
        lineRenderer = GetComponent<LineRenderer>();
        if (lineRenderer == null)
        {
            Debug.LogError("Line Renderer component not found!");
            return;
        }
    }

    void Update()
    {
        if (targetCameraTransform == null) return;

        Vector3[] points = new Vector3[numPoints];
        lineRenderer.positionCount = numPoints;

        Vector3 origin = targetCameraTransform.position;
        Vector3 forward = targetCameraTransform.forward;

        for (int i = 0; i < numPoints; i++)
        {
            float t = (float)i / (numPoints - 1);
            
            // Posição base do ponto no caminho do raio (linha reta)
            Vector3 pointPosition = origin + forward * (t * lineLength);
            
            // Adiciona a curvatura. A curvatura é perpendicular à direção inicial
            // e varia ao longo do comprimento da linha.
            Vector3 curveOffset = targetCameraTransform.up * Mathf.Sin(t * Mathf.PI) * curveStrength;

            points[i] = pointPosition + curveOffset;
        }

        lineRenderer.SetPositions(points);
    }
}