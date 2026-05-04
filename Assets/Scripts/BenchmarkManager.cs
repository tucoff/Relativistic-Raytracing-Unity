using UnityEngine;
using System.Collections;
using System.IO;

public class BenchmarkAutomator : MonoBehaviour
{
    [Header("Referências")]
    public RayTracingManager manager;

    [Header("Configurações do Loop")]
    public int[] resolutionsH = { 144, 480, 720, 1080 };
    private int[] resolutionsW = { 256, 853, 1280, 1920 };

    private Vector3 targetPos = new Vector3(0f, 0f, 666f);
    private Vector3 targetRot = new Vector3(0f, 180f, 0f);

    void Start()
    {
        // Desativa V-Sync para o benchmark não ficar travado no refresh rate do monitor
        QualitySettings.vSyncCount = 0;
        Application.targetFrameRate = 9999;

        string folderPath = Path.Combine(Application.dataPath, "../Benchmarks");
        if (!Directory.Exists(folderPath)) Directory.CreateDirectory(folderPath);

        if (manager != null)
        {
            manager.enableFirstPersonControls = false;
            manager.SetRelativisticView(true);
            StartCoroutine(RunHardcodedBenchmark());
        }
    }

    IEnumerator RunHardcodedBenchmark()
    {
        Debug.Log(">>> BENCHMARK INICIADO <<<");

        for (int r = 0; r < resolutionsH.Length; r++)
        {
            int w = resolutionsW[r];
            int h = resolutionsH[r];

            // 1. Aplica Resolução (No .exe isso redimensiona a janela)
            Screen.SetResolution(w, h, false);
            yield return new WaitForSeconds(1f); // Respiro curto para o driver de vídeo

            foreach (RayTracingManager.Metric m in System.Enum.GetValues(typeof(RayTracingManager.Metric)))
            {
                foreach (RayTracingManager.Integrator i in System.Enum.GetValues(typeof(RayTracingManager.Integrator)))
                {
                    for (int sceneID = 1; sceneID <= 5; sceneID++)
                    {
                        // Configura a cena e câmera
                        Camera.main.transform.position = targetPos;
                        Camera.main.transform.rotation = Quaternion.Euler(targetRot);
                        manager.selectedMetric = m;
                        manager.selectedIntegrator = i;
                        manager.currentScene = sceneID;
                        manager.ForceCameraUpdate();

                        // 2. LOOP DE MÉDIA (5 SEGUNDOS)
                        float duration = 5f;
                        float elapsed = 0f;
                        int frameCount = 0;

                        while (elapsed < duration)
                        {
                            elapsed += Time.unscaledDeltaTime;
                            frameCount++;
                            yield return null; // Espera o próximo frame
                        }

                        float averageFps = frameCount / elapsed;

                        // 3. CAPTURA E SALVA
                        CaptureAndSave(w, h, averageFps, m.ToString(), i.ToString(), sceneID);
                    }
                }
            }
        }

        Debug.Log(">>> BENCHMARK CONCLUÍDO! <<<");
        manager.enableFirstPersonControls = true;
    }

    void CaptureAndSave(int w, int h, float avgFps, string metric, string integrator, int sceneId)
    {
        // Cria buffer de renderização na resolução correta
        RenderTexture rt = new RenderTexture(w, h, 24);
        Camera cam = Camera.main;

        RenderTexture oldRT = cam.targetTexture;
        cam.targetTexture = rt;
        cam.Render();

        // Lê os pixels da GPU para a CPU
        Texture2D screenShot = new Texture2D(w, h, TextureFormat.RGB24, false);
        RenderTexture.active = rt;
        screenShot.ReadPixels(new Rect(0, 0, w, h), 0, 0);
        screenShot.Apply();

        // Limpeza
        cam.targetTexture = oldRT;
        RenderTexture.active = null;
        Destroy(rt);

        // Salva arquivo com a média no nome
        byte[] bytes = screenShot.EncodeToPNG();
        string fileName = $"{avgFps:F1}AVG_FPS_{metric}_{integrator}_S{sceneId}_{h}p.png";
        string path = Path.Combine(Application.dataPath, "../Benchmarks", fileName);

        File.WriteAllBytes(path, bytes);
        Destroy(screenShot);
        Debug.Log($"Registrado: {fileName}");
    }
}