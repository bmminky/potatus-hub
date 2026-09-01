using Microsoft.Win32;

namespace PotatusHub;

public static class LaunchAtLogin
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "potatus hub";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(KeyPath, false);
            return key?.GetValue(ValueName) is string;
        }
    }

    public static void Toggle()
    {
        using var key = Registry.CurrentUser.OpenSubKey(KeyPath, true)
            ?? Registry.CurrentUser.CreateSubKey(KeyPath, true);
        if (IsEnabled)
        {
            key.DeleteValue(ValueName, false);
        }
        else if (Environment.ProcessPath is { } path)
        {
            key.SetValue(ValueName, $"\"{path}\"");
        }
    }
}
