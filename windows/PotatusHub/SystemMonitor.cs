using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Windows.Threading;

namespace PotatusHub;

public sealed class SystemMonitor : INotifyPropertyChanged, IDisposable
{
    private readonly DispatcherTimer _timer;
    private readonly CpuSampler _cpu = new();
    private bool _gpuRefreshInFlight;
    private int _tick;

    public event PropertyChangedEventHandler? PropertyChanged;

    public double? RamUsage { get; private set; }
    public double? CpuUsage { get; private set; }
    public double? GpuUsage { get; private set; }

    public SystemMonitor()
    {
        _cpu.Sample();
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) => Refresh();
    }

    public void Start()
    {
        Refresh();
        _timer.Start();
    }

    public void Refresh()
    {
        RamUsage = MemorySampler.Sample();
        CpuUsage = _cpu.Sample();
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));

        _tick += 1;
        if (_tick == 1 || _tick % 2 == 0) RefreshGpu();
    }

    public double? Value(MetricKind kind) => kind switch
    {
        MetricKind.Ram => RamUsage,
        MetricKind.Cpu => CpuUsage,
        _ => GpuUsage,
    };

    private async void RefreshGpu()
    {
        if (_gpuRefreshInFlight) return;
        _gpuRefreshInFlight = true;
        try
        {
            GpuUsage = await Task.Run(GpuSampler.Sample);
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(GpuUsage)));
        }
        finally
        {
            _gpuRefreshInFlight = false;
        }
    }

    public void Dispose() => _timer.Stop();
}

internal sealed class CpuSampler
{
    private ulong? _idle;
    private ulong? _kernel;
    private ulong? _user;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);

    [StructLayout(LayoutKind.Sequential)]
    private struct FileTime
    {
        public uint Low;
        public uint High;
        public readonly ulong Value => ((ulong)High << 32) | Low;
    }

    public double? Sample()
    {
        if (!GetSystemTimes(out var idle, out var kernel, out var user)) return null;
        var idleNow = idle.Value;
        var kernelNow = kernel.Value;
        var userNow = user.Value;
        if (_idle is null || _kernel is null || _user is null)
        {
            (_idle, _kernel, _user) = (idleNow, kernelNow, userNow);
            return null;
        }

        var idleDelta = idleNow - _idle.Value;
        var kernelDelta = kernelNow - _kernel.Value;
        var userDelta = userNow - _user.Value;
        (_idle, _kernel, _user) = (idleNow, kernelNow, userNow);
        var total = kernelDelta + userDelta;
        return total == 0 ? null : Math.Clamp((double)(total - idleDelta) / total * 100, 0, 100);
    }
}

internal static class MemorySampler
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MemoryStatus
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhysical;
        public ulong AvailablePhysical;
        public ulong TotalPageFile;
        public ulong AvailablePageFile;
        public ulong TotalVirtual;
        public ulong AvailableVirtual;
        public ulong AvailableExtendedVirtual;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);

    public static double? Sample()
    {
        var status = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        if (!GlobalMemoryStatusEx(ref status) || status.TotalPhysical == 0) return null;
        return Math.Clamp((double)(status.TotalPhysical - status.AvailablePhysical) / status.TotalPhysical * 100, 0, 100);
    }
}

internal static partial class GpuSampler
{
    [GeneratedRegex(@"_phys_\d+_eng_\d+_engtype_[^_]+", RegexOptions.IgnoreCase)]
    private static partial Regex EngineKeyRegex();

    public static double? Sample()
    {
        try
        {
            var category = new PerformanceCounterCategory("GPU Engine");
            var instances = category.GetInstanceNames();
            if (instances.Length == 0) return null;

            var engineTotals = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
            foreach (var instance in instances)
            {
                using var counter = new PerformanceCounter("GPU Engine", "Utilization Percentage", instance, true);
                var value = Math.Max(0, counter.NextValue());
                var match = EngineKeyRegex().Match(instance);
                var key = match.Success ? match.Value : instance;
                engineTotals[key] = engineTotals.GetValueOrDefault(key) + value;
            }

            return engineTotals.Count == 0 ? null : Math.Clamp(engineTotals.Values.Max(), 0, 100);
        }
        catch
        {
            return null;
        }
    }
}
