using System.Windows.Media;

namespace PotatusHub;

public enum MetricKind
{
    Ram,
    Cpu,
    Gpu,
}

public static class MetricKindExtensions
{
    public static string Title(this MetricKind kind) => kind switch
    {
        MetricKind.Ram => "RAM",
        MetricKind.Cpu => "CPU",
        _ => "GPU",
    };

    public static Color Accent(this MetricKind kind) => kind switch
    {
        MetricKind.Ram => Color.FromRgb(0xBD, 0xBD, 0xC4),
        MetricKind.Cpu => Color.FromRgb(0xF5, 0xDB, 0x8C),
        _ => Color.FromRgb(0xD9, 0x77, 0x57),
    };

    public static string Glyph(this MetricKind kind) => kind switch
    {
        MetricKind.Ram => "▥",
        MetricKind.Cpu => "▣",
        _ => "▦",
    };
}
