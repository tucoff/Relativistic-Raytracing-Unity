using UnityEngine;
using System.Collections;
using System.Collections.Generic;
using System.IO;

public class BenchmarkAutomator : MonoBehaviour
{
    [Header("Referências")]
    public RayTracingManager manager;
    public BenchmarkConfiguration benchmarkConfig; 

    void Start()
    {
        // Desativa V-Sync para o benchmark não ficar travado no refresh rate do monitor
        QualitySettings.vSyncCount = 0;
        Application.targetFrameRate = 9999;

        string folderPath = Path.Combine(Application.dataPath, "../Benchmarks");
        if (!Directory.Exists(folderPath)) Directory.CreateDirectory(folderPath);

        // Initialize CSV exporter
        BenchmarkCSVExporter.InitializeCSV();

        if (benchmarkConfig == null)
        {
            benchmarkConfig = FindFirstObjectByType<BenchmarkConfiguration>();
        }

        if (manager != null)
        {
            manager.enableFirstPersonControls = false;
            manager.SetRelativisticView(true);
            StartCoroutine(RunConfigurableBenchmark());
        }
    }

    IEnumerator RunConfigurableBenchmark()
    {
        Debug.Log(">>> BENCHMARK INICIADO COM CONFIGURAÇÕES <<<");

        BenchmarkConfiguration config = benchmarkConfig ?? FindFirstObjectByType<BenchmarkConfiguration>();
        if (config == null)
        {
            Debug.LogError("BenchmarkConfiguration não encontrada!");
            yield break;
        }

        int[] resolutionsH = config.resolutionsH;
        int[] resolutionsW = config.resolutionsW;

        for (int r = 0; r < resolutionsH.Length; r++)
        {
            int w = resolutionsW[r];
            int h = resolutionsH[r];

            // 1. Aplica Resolução
            Screen.SetResolution(w, h, false);
            yield return new WaitForSeconds(1f);

            foreach (RayTracingManager.Metric m in System.Enum.GetValues(typeof(RayTracingManager.Metric)))
            {
                foreach (RayTracingManager.Integrator i in System.Enum.GetValues(typeof(RayTracingManager.Integrator)))
                {
                    for (int sceneID = 1; sceneID <= 6; sceneID++)
                    {
                        // Obtém configuração de câmeras para esta cena
                        SceneCameraConfig sceneCamConfig = config.GetSceneCameraConfig(sceneID);
                        if (sceneCamConfig == null || sceneCamConfig.cameras.Count == 0)
                        {
                            Debug.LogWarning($"Nenhuma configuração de câmera para cena {sceneID}");
                            continue;
                        }

                        // Loop através de cada preset de câmera
                        for (int camIdx = 0; camIdx < sceneCamConfig.cameras.Count; camIdx++)
                        {
                            CameraPreset cameraPreset = sceneCamConfig.cameras[camIdx];

                            // Loop através de cada preset de Step Size
                            for (int stepIdx = 0; stepIdx < config.stepSizePresets.Count; stepIdx++)
                            {
                                StepSizePreset stepPreset = config.stepSizePresets[stepIdx];

                                // Loop através de cada preset de Gravidade
                                for (int gravIdx = 0; gravIdx < config.gravityPresets.Count; gravIdx++)
                                {
                                    GravityPreset gravityPreset = config.gravityPresets[gravIdx];

                                    // Loop através de cada preset de Spin Speed
                                    for (int spinIdx = 0; spinIdx < config.spinSpeedPresets.Count; spinIdx++)
                                    {
                                        SpinSpeedPreset spinPreset = config.spinSpeedPresets[spinIdx];

                                        // Configura tudo
                                        Camera.main.transform.position = cameraPreset.position;
                                        Camera.main.transform.rotation = Quaternion.Euler(cameraPreset.rotation);
                                        manager.selectedMetric = m;
                                        manager.selectedIntegrator = i;
                                        manager.currentScene = sceneID;
                                        manager.stepSize = stepPreset.value;
                                        manager.baseBlackHoleMass = gravityPreset.value;
                                        manager.spinSpeed = spinPreset.value;
                                        manager.ForceCameraUpdate();

                                        // 2. LOOP DE MÉDIA
                                        float duration = config.benchmarkDurationPerConfig;
                                        float elapsed = 0f;
                                        int frameCount = 0;

                                        while (elapsed < duration)
                                        {
                                            elapsed += Time.unscaledDeltaTime;
                                            frameCount++;
                                            yield return null;
                                        }

                                        float averageFps = frameCount / elapsed;

                                        // 3. CAPTURA E SALVA
                                        string cameraName = cameraPreset.name.Replace(" ", "");
                                        string stepName = stepPreset.name.Replace(" ", "");
                                        string gravName = gravityPreset.name.Replace(" ", "");
                                        string spinName = spinPreset.name.Replace(" ", "");

                                        CaptureAndSave(w, h, averageFps, m.ToString(), i.ToString(), sceneID,
                                            cameraName, stepName, gravName, spinName);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Debug.Log(">>> BENCHMARK CONCLUÍDO! <<<");
        manager.enableFirstPersonControls = true;
    }

    void CaptureAndSave(int w, int h, float avgFps, string metric, string integrator, int sceneId,
        string cameraPresetName, string stepPresetName, string gravityPresetName, string spinPresetName)
    {
        // Get the actual preset objects to pass to CSV exporter
        BenchmarkConfiguration config = benchmarkConfig ?? FindFirstObjectByType<BenchmarkConfiguration>();
        SceneCameraConfig sceneCamConfig = config?.GetSceneCameraConfig(sceneId);
        CameraPreset cameraPreset = null;
        StepSizePreset stepPreset = null;
        GravityPreset gravityPreset = null;
        SpinSpeedPreset spinPreset = null;

        // Find the matching presets
        if (sceneCamConfig != null)
        {
            foreach (var preset in sceneCamConfig.cameras)
            {
                if (preset.name.Replace(" ", "") == cameraPresetName)
                {
                    cameraPreset = preset;
                    break;
                }
            }
        }

        foreach (var step in config.stepSizePresets)
        {
            if (step.name.Replace(" ", "") == stepPresetName)
            {
                stepPreset = step;
                break;
            }
        }

        foreach (var grav in config.gravityPresets)
        {
            if (grav.name.Replace(" ", "") == gravityPresetName)
            {
                gravityPreset = grav;
                break;
            }
        }

        foreach (var spin in config.spinSpeedPresets)
        {
            if (spin.name.Replace(" ", "") == spinPresetName)
            {
                spinPreset = spin;
                break;
            }
        }

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
        string fileName = $"{avgFps:F1}FPS_{metric}_{integrator}_S{sceneId}_{cameraPresetName}_{stepPresetName}_{gravityPresetName}_{spinPresetName}_{h}p.png";
        string path = Path.Combine(Application.dataPath, "../Benchmarks", fileName);

        File.WriteAllBytes(path, bytes);
        Destroy(screenShot);

        // Record to CSV if all presets were found
        if (cameraPreset != null && stepPreset != null && gravityPreset != null && spinPreset != null)
        {
            float duration = config.benchmarkDurationPerConfig;
            int frameCount = Mathf.RoundToInt(avgFps * duration);
            BenchmarkCSVExporter.AppendBenchmarkData(
                w, h, metric, integrator, sceneId,
                cameraPreset, stepPreset, gravityPreset, spinPreset,
                avgFps, frameCount, duration, path);
        }
        else
        {
            Debug.LogWarning("Could not find all presets for CSV export");
        }

        Debug.Log($"Registrado: {fileName}");
    }
}