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
        QualitySettings.vSyncCount = 0;
        Application.targetFrameRate = 9999;

        string folderPath = Path.Combine(Application.dataPath, "../Benchmarks");
        if (!Directory.Exists(folderPath)) Directory.CreateDirectory(folderPath);

        BenchmarkCSVExporter.InitializeCSV();

        if (benchmarkConfig == null)
        {
            benchmarkConfig = FindFirstObjectByType<BenchmarkConfiguration>();
        }

        if (manager != null)
        {
            manager.enableFirstPersonControls = false;
            manager.SetRelativisticView(false);
            StartCoroutine(RunBaselineAndBenchmark());
        }
    }

    IEnumerator RunBaselineAndBenchmark()
    {
        Debug.Log(">>> FASE 1: CAPTURA DE BASELINE (MODO NÃO-RELATIVÍSTICO) <<<");
        yield return StartCoroutine(CaptureBaselineScreenshots());

        Debug.Log(">>> FASE 2: BENCHMARK COMPLETO (MODO RELATIVÍSTICO) <<<");
        manager.SetRelativisticView(true);
        yield return StartCoroutine(RunConfigurableBenchmark());

        Debug.Log(">>> BENCHMARK CONCLUÍDO! <<<");
        manager.enableFirstPersonControls = true;
    }

    IEnumerator CaptureBaselineScreenshots()
    {
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

            Screen.SetResolution(w, h, false);
            yield return new WaitForSeconds(2f);

            for (int sceneID = 1; sceneID <= 6; sceneID++)
            {
                SceneCameraConfig sceneCamConfig = config.GetSceneCameraConfig(sceneID);

                for (int camIdx = 0; camIdx < sceneCamConfig.cameras.Count; camIdx++)
                {
                    CameraPreset cameraPreset = sceneCamConfig.cameras[camIdx];
                    
                    Camera.main.transform.position = cameraPreset.position;
                    Camera.main.transform.rotation = Quaternion.Euler(cameraPreset.rotation);
                    manager.currentScene = sceneID;
                    manager.ForceCameraUpdate();
                    
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
                    CaptureBaselineScreenshot(w, h, sceneID, cameraPreset.name, averageFps);
                }
            }
        }

        Debug.Log(">>> FASE 1 CONCLUÍDA: Baseline screenshots capturados <<<");
    }

    void CaptureBaselineScreenshot(int w, int h, int sceneID, string cameraPresetName, float avgFps)
    {
        RenderTexture rt = new RenderTexture(w, h, 24);
        Camera cam = Camera.main;

        RenderTexture oldRT = cam.targetTexture;
        cam.targetTexture = rt;
        cam.Render();

        Texture2D screenShot = new Texture2D(w, h, TextureFormat.RGB24, false);
        RenderTexture.active = rt;
        screenShot.ReadPixels(new Rect(0, 0, w, h), 0, 0);
        screenShot.Apply();

        cam.targetTexture = oldRT;
        RenderTexture.active = null;
        Destroy(rt);

        byte[] bytes = screenShot.EncodeToPNG();
        string cameraName = cameraPresetName.Replace(" ", "");
        string fileName = $"BASELINE_{avgFps:F1}FPS_NonRelativistic_S{sceneID}_{cameraName}_{h}p.png";
        string path = Path.Combine(Application.dataPath, "../Benchmarks", fileName);

        File.WriteAllBytes(path, bytes);
        Destroy(screenShot);

        AppendBaselineData(w, h, sceneID, cameraName, avgFps);
        Debug.Log($"Baseline capturado: {fileName}");
    }

    void AppendBaselineData(int w, int h, int sceneID, string cameraName, float avgFps)
    {
        BenchmarkConfiguration config = benchmarkConfig ?? FindFirstObjectByType<BenchmarkConfiguration>();
        
        string csvPath = Path.Combine(Application.dataPath, "../Benchmarks", "Baseline_Results.csv");
        bool fileExists = File.Exists(csvPath);

        using (StreamWriter writer = new StreamWriter(csvPath, true))
        {
            if (!fileExists)
            {
                writer.WriteLine("Resolution_W,Resolution_H,Scene_ID,Camera_Name,Average_FPS");
            }

            writer.WriteLine($"{w},{h},{sceneID},{cameraName},{avgFps:F2}");
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

            Screen.SetResolution(w, h, false);
            yield return new WaitForSeconds(2f);

            foreach (RayTracingManager.Metric m in System.Enum.GetValues(typeof(RayTracingManager.Metric)))
            {
                foreach (RayTracingManager.Integrator i in System.Enum.GetValues(typeof(RayTracingManager.Integrator)))
                {
                    for (int sceneID = 1; sceneID <= 6; sceneID++)
                    {
                        SceneCameraConfig sceneCamConfig = config.GetSceneCameraConfig(sceneID);

                        for (int camIdx = 0; camIdx < sceneCamConfig.cameras.Count; camIdx++)
                        {
                            CameraPreset cameraPreset = sceneCamConfig.cameras[camIdx];

                            int maxStepIdx = (i == RayTracingManager.Integrator.RK4) ? 1 : config.stepSizePresets.Count;
                            for (int stepIdx = 0; stepIdx < maxStepIdx; stepIdx++)
                            {
                                StepSizePreset stepPreset = config.stepSizePresets[stepIdx];
                                 
                                List<GravityPreset> currentGravities = config.gravityPresets;
                                if (sceneID == 6)
                                {
                                    currentGravities = new List<GravityPreset>
                                    {
                                        new GravityPreset { name = "Grav_1.989e31", value = 1.989e+31f },
                                        new GravityPreset { name = "Grav_1.989e32", value = 1.989e+32f },
                                        new GravityPreset { name = "Grav_1.989e33", value = 1.989e+33f },
                                        new GravityPreset { name = "Grav_1.989e34", value = 1.989e+34f }
                                    };
                                }

                                for (int gravIdx = 0; gravIdx < currentGravities.Count; gravIdx++)
                                {
                                    GravityPreset gravityPreset = currentGravities[gravIdx];

                                    int maxSpinIdx = (m == RayTracingManager.Metric.Kerr) ? config.spinSpeedPresets.Count : 1;
                                    for (int spinIdx = 0; spinIdx < maxSpinIdx; spinIdx++)
                                    {
                                        SpinSpeedPreset spinPreset = config.spinSpeedPresets[spinIdx];

                                        Camera.main.transform.position = cameraPreset.position;
                                        Camera.main.transform.rotation = Quaternion.Euler(cameraPreset.rotation);
                                        manager.selectedMetric = m;
                                        manager.selectedIntegrator = i;
                                        manager.currentScene = sceneID;
                                        manager.stepSize = stepPreset.value;
                                        manager.baseBlackHoleMass = gravityPreset.value;
                                        manager.spinSpeed = spinPreset.value;
                                        manager.ForceCameraUpdate();

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
        BenchmarkConfiguration config = benchmarkConfig ?? FindFirstObjectByType<BenchmarkConfiguration>();
        SceneCameraConfig sceneCamConfig = config?.GetSceneCameraConfig(sceneId);
        CameraPreset cameraPreset = null;
        StepSizePreset stepPreset = null;
        GravityPreset gravityPreset = null;
        SpinSpeedPreset spinPreset = null;

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

        // Fallback for dynamically generated custom Scene 6 gravities
        if (gravityPreset == null && sceneId == 6)
        {
            if (gravityPresetName == "Grav_1.989e31") gravityPreset = new GravityPreset { name = "Grav_1.989e31", value = 1.989e+31f };
            else if (gravityPresetName == "Grav_1.989e32") gravityPreset = new GravityPreset { name = "Grav_1.989e32", value = 1.989e+32f };
            else if (gravityPresetName == "Grav_1.989e33") gravityPreset = new GravityPreset { name = "Grav_1.989e33", value = 1.989e+33f };
            else if (gravityPresetName == "Grav_1.989e34") gravityPreset = new GravityPreset { name = "Grav_1.989e34", value = 1.989e+34f };
        }

        foreach (var spin in config.spinSpeedPresets)
        {
            if (spin.name.Replace(" ", "") == spinPresetName)
            {
                spinPreset = spin;
                break;
            }
        }

        RenderTexture rt = new RenderTexture(w, h, 24);
        Camera cam = Camera.main;

        RenderTexture oldRT = cam.targetTexture;
        cam.targetTexture = rt;
        cam.Render();

        Texture2D screenShot = new Texture2D(w, h, TextureFormat.RGB24, false);
        RenderTexture.active = rt;
        screenShot.ReadPixels(new Rect(0, 0, w, h), 0, 0);
        screenShot.Apply();

        cam.targetTexture = oldRT;
        RenderTexture.active = null;
        Destroy(rt);

        byte[] bytes = screenShot.EncodeToPNG();
        string fileName = $"{avgFps:F1}FPS_{metric}_{integrator}_S{sceneId}_{cameraPresetName}_{stepPresetName}_{gravityPresetName}_{spinPresetName}_{h}p.png";
        string path = Path.Combine(Application.dataPath, "../Benchmarks", fileName);

        File.WriteAllBytes(path, bytes);
        Destroy(screenShot);

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