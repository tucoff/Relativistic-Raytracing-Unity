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
    [SerializeField] public float benchmarkDurationPerConfig = 5f;
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
        // Initialize Step Sizes if empty
        if (stepSizePresets.Count == 0)
        {
            stepSizePresets.Add(new StepSizePreset { name = "Very Small", value = 1f });
            stepSizePresets.Add(new StepSizePreset { name = "Small", value = 5f });
            stepSizePresets.Add(new StepSizePreset { name = "Default", value = 10f });
            stepSizePresets.Add(new StepSizePreset { name = "Large", value = 20f });
            stepSizePresets.Add(new StepSizePreset { name = "Very Large", value = 50f });
        }

        // Initialize Gravity Presets if empty
        if (gravityPresets.Count == 0)
        {
            float baseMass = 1.989e30f;
            gravityPresets.Add(new GravityPreset { name = "Natural", value = baseMass * 10f });
            gravityPresets.Add(new GravityPreset { name = "Higher", value = baseMass * 50f });
            gravityPresets.Add(new GravityPreset { name = "Very High", value = baseMass * 200f });
        }

        // Initialize Spin Speed Presets if empty
        if (spinSpeedPresets.Count == 0)
        {
            spinSpeedPresets.Add(new SpinSpeedPreset { name = "Natural", value = 0.5f });
            spinSpeedPresets.Add(new SpinSpeedPreset { name = "Faster", value = 1.0f });
            spinSpeedPresets.Add(new SpinSpeedPreset { name = "Very Fast", value = 2.0f });
        }

        // Initialize Scene Camera Configs if empty
        if (sceneCameraConfigs.Count == 0)
        {
            for (int sceneId = 1; sceneId <= 6; sceneId++)
            {
                SceneCameraConfig config = new SceneCameraConfig { sceneId = sceneId };

                // Add default camera presets for each scene
                config.cameras.Add(new CameraPreset
                {
                    name = "Front View",
                    position = new Vector3(0f, 0f, 666f),
                    rotation = new Vector3(0f, 180f, 0f)
                });

                config.cameras.Add(new CameraPreset
                {
                    name = "Peripheral View",
                    position = new Vector3(300f, 100f, 400f),
                    rotation = new Vector3(-15f, 130f, 0f)
                });

                config.cameras.Add(new CameraPreset
                {
                    name = "Top View",
                    position = new Vector3(0f, 500f, 0f),
                    rotation = new Vector3(90f, 0f, 0f)
                });

                config.cameras.Add(new CameraPreset
                {
                    name = "Diagonal View",
                    position = new Vector3(400f, 300f, 400f),
                    rotation = new Vector3(-30f, 135f, 0f)
                });

                config.cameras.Add(new CameraPreset
                {
                    name = "Tangent View",
                    position = new Vector3(500f, 50f, 100f),
                    rotation = new Vector3(-5f, 160f, 0f)
                });

                config.cameras.Add(new CameraPreset
                {
                    name = "Opposite Direction",
                    position = new Vector3(0f, 0f, -666f),
                    rotation = new Vector3(0f, 0f, 0f)
                });

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
