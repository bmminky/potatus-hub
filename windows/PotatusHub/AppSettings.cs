using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PotatusHub;

public sealed class SettingsData
{
    public L.Language Language { get; set; } = L.Language.System;
    public bool AlwaysOnTop { get; set; }
    public HashSet<MetricKind> VisibleMetrics { get; set; } = Enum.GetValues<MetricKind>().ToHashSet();
    public List<SavedPanel> Panels { get; set; } = [];
}

public sealed class SavedPanel
{
    public List<LayoutCell> Cells { get; set; } = [];
    public double Left { get; set; }
    public double Top { get; set; }
}

public static class AppSettings
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    private static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "potatus hub");
    private static readonly string FilePath = Path.Combine(DirectoryPath, "settings.json");

    public static SettingsData Current { get; private set; } = Load();

    public static void Save()
    {
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(Current, Options));
        }
        catch
        {
            // Preferences should never stop the monitor from running.
        }
    }

    private static SettingsData Load()
    {
        try
        {
            return File.Exists(FilePath)
                ? JsonSerializer.Deserialize<SettingsData>(File.ReadAllText(FilePath), Options) ?? new SettingsData()
                : new SettingsData();
        }
        catch
        {
            return new SettingsData();
        }
    }
}
