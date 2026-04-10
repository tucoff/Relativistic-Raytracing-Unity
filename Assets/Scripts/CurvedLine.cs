using UnityEngine;
using System.Collections.Generic;


public class CurvedLine : MonoBehaviour
{

    private LineRenderer lineRenderer;     
    private RayTracingManager rayTracingManager;
    private int numPoints;

    [Header("General Relativity Settings")]
    public float gravitationalConstant = 6.67430e-11f; // G
    public float speedOfLight = 299792458.0f; // c (Ajuste isso para ver mais/menos curvatura na escala do jogo)

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

        rayTracingManager = FindFirstObjectByType<RayTracingManager>();

        if (rayTracingManager == null)
        {
            Debug.LogError("RayTracingManager not found!");
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
        numPoints = Mathf.Max(2, newMaxSteps);
    }


    // Calcula a aceleração geodésica baseada na Métrica de Schwarzschild
    Vector3 CalculateGeodesicAcceleration(Vector3 currentPos, Vector3 currentVel)
    {
        Vector3 totalAcceleration = Vector3.zero;

        if (massiveSpheres == null) return totalAcceleration;

        float cSq = speedOfLight * speedOfLight; // c^2

        foreach (RayTracedSphere sphere in massiveSpheres)
        {
            if (sphere == null || sphere.massa <= 0) continue;

            // Vetor r: Do centro da massa até o fóton (na física, r aponta radialmente para fora)
            Vector3 r_vec = currentPos - sphere.transform.position;
            float r_dist = r_vec.magnitude;

            // Evitar singularidade (divisão por zero no centro)
            if (r_dist < 0.1f) continue;

            // 1. Calcular Raio de Schwarzschild (Rs = 2GM / c^2)
            // Rs define o horizonte de eventos.
            float Rs = (2.0f * gravitationalConstant * sphere.massa) / cSq;

            // 2. Calcular Momento Angular Específico (h = r x v)
            Vector3 h_vec = Vector3.Cross(r_vec, currentVel);
            float h2 = h_vec.sqrMagnitude; // |h|^2

            // 3. Fórmula da Aceleração Geodésica de Schwarzschild (Simplificada para coordenadas cartesianas)
            // Aceleração = - (3/2) * Rs * (h^2 / r^5) * r_vec
            // O termo negativo indica atração (contra o vetor r que aponta para fora)
            float magnitudeFactor = 1.5f * Rs * (h2 / Mathf.Pow(r_dist, 5));
            Vector3 acceleration = -magnitudeFactor * r_vec;

            totalAcceleration += acceleration;
        }

        return totalAcceleration;
    }

    void Update()
    {
        if (targetCameraTransform == null) return;

        UpdateParametersFromRayTracingManager();
        Vector3[] points = new Vector3[numPoints];
        lineRenderer.positionCount = numPoints;

        // Estado inicial
        Vector3 currentPosition = targetCameraTransform.position;

        // A direção agora é um vetor velocidade com magnitude 'c'
        Vector3 currentVelocity = targetCameraTransform.forward * speedOfLight;
        points[0] = currentPosition;

        // Passo de tempo (dt) derivado do stepSize espacial
        // Se dx = v * dt => dt = dx / v
        float stepSize = rayTracingManager.GetStepSize();
        float dt = stepSize / speedOfLight;

        for (int i = 1; i < numPoints; i++)
        {
            // Checagem de colisão (Raycast padrão para terminar a linha se bater em algo)
            RaycastHit hit;

            if (Physics.Raycast(currentPosition, currentVelocity.normalized, out hit, stepSize))
            {
                points[i] = hit.point;
                // Preenche o resto da linha no ponto de impacto para não ficar piscando
                for(int j = i + 1; j < numPoints; j++) points[j] = hit.point;
                break;
            }

            // --- INTEGRAÇÃO NUMÉRICA (Método de Euler Semi-Implícito ou Velocity Verlet simplificado) ---
            // 1. Calcular a aceleração baseada na curvatura do espaço-tempo na posição atual
            Vector3 acceleration = CalculateGeodesicAcceleration(currentPosition, currentVelocity);

            // 2. Atualizar velocidade (curvatura da luz)
            currentVelocity += acceleration * dt;

            // Nota: Na Relatividade Geral pura, a velocidade da luz é sempre 'c' localmente.
            // A "aceleração" aqui muda a direção. Podemos renormalizar para manter a estabilidade numérica,
            // embora a equação de Schwarzschild já conserve energia orbital naturalmente.
            currentVelocity = currentVelocity.normalized * speedOfLight;


            // 3. Atualizar posição
            currentPosition += currentVelocity * dt;
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