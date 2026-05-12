using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using UnityEngine;

public class BenchmarkCSVExporter : MonoBehaviour
{
    private static string csvFilePath;
    private static bool headerWritten = false;
    private static string applicationTypeIdentifier = "Unity";

    private const string CSV_FILENAME = "TCCBenchmark.csv";

    public static void SetApplicationType(string appType)
    {
        applicationTypeIdentifier = appType;
    }

    public static string GetApplicationType()
    {
        return applicationTypeIdentifier;
    }

    public static void InitializeCSV()
    {
        string benchmarksFolder = @"C:\All Projects";
        if (!Directory.Exists(benchmarksFolder))
        {
            Directory.CreateDirectory(benchmarksFolder);
        }

        csvFilePath = Path.Combine(benchmarksFolder, CSV_FILENAME);
        
        // Write header if file doesn't exist
        if (!File.Exists(csvFilePath))
        {
            WriteCSVHeader();
            headerWritten = true;
        }
        else
        {
            headerWritten = true;
        }
    }

    private static void WriteCSVHeader()
    {
        StringBuilder header = new StringBuilder();
        header.Append("Timestamp,");
        header.Append("Application_Type,");
        header.Append("Resolution,");
        header.Append("Resolution_W,");
        header.Append("Resolution_H,");
        header.Append("Metric,");
        header.Append("Integrator,");
        header.Append("Scene_ID,");
        header.Append("Camera_Name,");
        header.Append("Camera_Position_X,");
        header.Append("Camera_Position_Y,");
        header.Append("Camera_Position_Z,");
        header.Append("Camera_Rotation_X,");
        header.Append("Camera_Rotation_Y,");
        header.Append("Camera_Rotation_Z,");
        header.Append("Step_Size,");
        header.Append("Step_Name,");
        header.Append("Gravity_Value,");
        header.Append("Gravity_Name,");
        header.Append("Spin_Speed,");
        header.Append("Spin_Name,");
        header.Append("Average_FPS,");
        header.Append("Frame_Count,");
        header.Append("Duration_Seconds,");
        header.Append("Image_Path");

        File.WriteAllText(csvFilePath, header.ToString() + "\n");
    }

    public static void AppendBenchmarkData(
        int resolutionW, int resolutionH,
        string metric, string integrator, int sceneId,
        CameraPreset cameraPreset,
        StepSizePreset stepPreset,
        GravityPreset gravityPreset,
        SpinSpeedPreset spinPreset,
        float averageFps, int frameCount, float duration,
        string imagePath)
    {
        if (!headerWritten)
        {
            InitializeCSV();
        }

        string timestamp = System.DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
        string resolution = $"{resolutionH}p";

        StringBuilder row = new StringBuilder();
        row.Append(EscapeCSV(timestamp) + ",");
        row.Append(EscapeCSV(applicationTypeIdentifier) + ",");
        row.Append(EscapeCSV(resolution) + ",");
        row.Append(resolutionW + ",");
        row.Append(resolutionH + ",");
        row.Append(EscapeCSV(metric) + ",");
        row.Append(EscapeCSV(integrator) + ",");
        row.Append(sceneId + ",");
        row.Append(EscapeCSV(cameraPreset.name) + ",");
        row.Append(cameraPreset.position.x.ToString("F2") + ",");
        row.Append(cameraPreset.position.y.ToString("F2") + ",");
        row.Append(cameraPreset.position.z.ToString("F2") + ",");
        row.Append(cameraPreset.rotation.x.ToString("F2") + ",");
        row.Append(cameraPreset.rotation.y.ToString("F2") + ",");
        row.Append(cameraPreset.rotation.z.ToString("F2") + ",");
        row.Append(stepPreset.value.ToString("F2") + ",");
        row.Append(EscapeCSV(stepPreset.name) + ",");
        row.Append(gravityPreset.value.ToString("E2") + ",");
        row.Append(EscapeCSV(gravityPreset.name) + ",");
        row.Append(spinPreset.value.ToString("F2") + ",");
        row.Append(EscapeCSV(spinPreset.name) + ",");
        row.Append(averageFps.ToString("F2") + ",");
        row.Append(frameCount + ",");
        row.Append(duration.ToString("F2") + ",");
        row.Append(EscapeCSV(imagePath));

        File.AppendAllText(csvFilePath, row.ToString() + "\n");
        Debug.Log($"CSV Entry Recorded: {csvFilePath}");
    }

    private static string EscapeCSV(string value)
    {
        if (value.Contains(",") || value.Contains("\"") || value.Contains("\n"))
        {
            return "\"" + value.Replace("\"", "\"\"") + "\"";
        }
        return value;
    }

    public static string GetCSVFilePath()
    {
        if (string.IsNullOrEmpty(csvFilePath))
        {
            InitializeCSV();
        }
        return csvFilePath;
    }
}
