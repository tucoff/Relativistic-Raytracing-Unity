using System.Collections.Generic;
using UnityEngine;

[System.Serializable]
public class CameraPreset
{
    public string name = "Front View";
    public Vector3 position = new Vector3(0f, 0f, 666f);
    public Vector3 rotation = new Vector3(0f, 180f, 0f);
}

[System.Serializable]
public class StepSizePreset
{
    public string name = "Default";
    public float value = 10f;
}

[System.Serializable]
public class GravityPreset
{
    public string name = "Natural";
    public float value = 1.989e30f * 10f;
}

[System.Serializable]
public class SpinSpeedPreset
{
    public string name = "Natural";
    public float value = 0.5f;
}

[System.Serializable]
public class SceneCameraConfig
{
    public int sceneId = 1;
    public List<CameraPreset> cameras = new List<CameraPreset>();
}

public class BenchmarkConfiguration : MonoBehaviour
{
    [Header("Step Size Presets")]
    [SerializeField] public List<StepSizePreset> stepSizePresets = new List<StepSizePreset>();

    [Header("Gravity Presets")]
    [SerializeField] public List<GravityPreset> gravityPresets = new List<GravityPreset>();

    [Header("Spin Speed Presets")]
    [SerializeField] public List<SpinSpeedPreset> spinSpeedPresets = new List<SpinSpeedPreset>();

    [Header("Camera Presets by Scene")]
    [SerializeField] public List<SceneCameraConfig> sceneCameraConfigs = new List<SceneCameraConfig>();

    [Header("Resolutions")]
    [SerializeField] public int[] resolutionsH = { 144, 480, 720, 1080 };
    [SerializeField] public int[] resolutionsW = { 256, 853, 1280, 1920 };

    [Header("Benchmark Settings")]
    [SerializeField] public float benchmarkDurationPerConfig = 1f;
    [SerializeField] public int maxSteps = 1000;

    private static BenchmarkConfiguration instance;

    private void Awake()
    {
        if (instance == null)
        {
            instance = this;
            InitializeDefaultPresets();
        }
        else
        {
            Destroy(gameObject);
        }
    }

    private void InitializeDefaultPresets()
    {
        if (stepSizePresets.Count == 0)
        {
            stepSizePresets.Add(new StepSizePreset { name = "SmallStep", value = 1f });
            stepSizePresets.Add(new StepSizePreset { name = "MediumStep", value = 52f });
            stepSizePresets.Add(new StepSizePreset { name = "BigStep", value = 260f });
        }

        if (gravityPresets.Count == 0)
        {
            gravityPresets.Add(new GravityPreset { name = "NormalG", value = 1.989e31f });
            gravityPresets.Add(new GravityPreset { name = "StrongG", value = 3.978e31f });
            gravityPresets.Add(new GravityPreset { name = "MuchStrongerG", value = 5.967e31f });
        }

        if (spinSpeedPresets.Count == 0)
        {
            spinSpeedPresets.Add(new SpinSpeedPreset { name = "NaturalSpinSpeed", value = 0.5f });
            spinSpeedPresets.Add(new SpinSpeedPreset { name = "UnaturalSpinSpeed", value = 10f });
            spinSpeedPresets.Add(new SpinSpeedPreset { name = "StrongSpinSpeed", value = 50f });
            spinSpeedPresets.Add(new SpinSpeedPreset { name = "FunnySpinSpeed", value = 200f });
        }

        if (sceneCameraConfigs.Count == 0)
        {
            for (int sceneId = 1; sceneId <= 6; sceneId++)
            {
                SceneCameraConfig config = new SceneCameraConfig { sceneId = sceneId };

                if (sceneId == 6)
                { 
                    config.cameras.Add(new CameraPreset { name = "CamPos1", position = new Vector3(83f, -4f, 30f), rotation = new Vector3(0f, 240f, 0f) });
                    config.cameras.Add(new CameraPreset { name = "CamPos2", position = new Vector3(100f, 0f, 235f), rotation = new Vector3(0f, 170f, 0f) });
                    config.cameras.Add(new CameraPreset { name = "CamPos3", position = new Vector3(300f, 0f, 800f), rotation = new Vector3(0f, 116f, 0f) });
                    config.cameras.Add(new CameraPreset { name = "CamPos4", position = new Vector3(150f, -200f, -100f), rotation = new Vector3(-60f, -20f, 0f) });
                    config.cameras.Add(new CameraPreset { name = "CamPos5", position = new Vector3(125f, -2f, -30f), rotation = new Vector3(1f, 25f, 0f) });
                    config.cameras.Add(new CameraPreset { name = "CamPos6", position = new Vector3(100f, 2.2f, 45f), rotation = new Vector3(-0.3f, 90f, 0f) });
                }
                else
                { 
                    config.cameras.Add(new CameraPreset { name = "Front", position = new Vector3(0f, 0f, 666f), rotation = new Vector3(0f, 180f, 0f) });
                    config.cameras.Add(new CameraPreset { name = "Periferic", position = new Vector3(-140f, 0f, -360f), rotation = new Vector3(0f, 66f, 0f) });
                    config.cameras.Add(new CameraPreset { name = "Above", position = new Vector3(0f, 180f, -150f), rotation = new Vector3(90f, 0f, 0f) });
                    config.cameras.Add(new CameraPreset { name = "Diagonal", position = new Vector3(-70f, 70f, -400f), rotation = new Vector3(15f, 15f, 0f) });
                    config.cameras.Add(new CameraPreset { name = "Tangent", position = new Vector3(0f, 0f, -180f), rotation = new Vector3(0f, 90f, 0f) });
                    config.cameras.Add(new CameraPreset { name = "LookAway", position = new Vector3(0f, 0f, -200f), rotation = new Vector3(0f, 180f, 0f) });
                }

                sceneCameraConfigs.Add(config);
            }
        }
    }

    public static BenchmarkConfiguration Instance => instance;

    public SceneCameraConfig GetSceneCameraConfig(int sceneId)
    {
        foreach (var config in sceneCameraConfigs)
        {
            if (config.sceneId == sceneId)
                return config;
        }
        return null;
    }

    public CameraPreset GetCameraPreset(int sceneId, int cameraIndex)
    {
        SceneCameraConfig config = GetSceneCameraConfig(sceneId);
        if (config != null && cameraIndex >= 0 && cameraIndex < config.cameras.Count)
            return config.cameras[cameraIndex];
        return null;
    }

    public int GetCameraCountForScene(int sceneId)
    {
        SceneCameraConfig config = GetSceneCameraConfig(sceneId);
        return config != null ? config.cameras.Count : 0;
    }
}