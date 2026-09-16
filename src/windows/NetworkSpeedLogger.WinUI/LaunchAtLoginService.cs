using Microsoft.Win32;

namespace NetworkSpeedLogger;

public static class LaunchAtLoginService
{
    public const string ValueName = "NetworkSpeedLogger";
    public const string RegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public const string LaunchArgument = "--launch-at-login";

    public static bool TrySetEnabled(bool enabled, out string? error)
    {
        error = null;
        try
        {
            using RegistryKey key = Registry.CurrentUser.CreateSubKey(RegistryPath, writable: true)
                ?? throw new InvalidOperationException("Unable to open the current user's startup registry key.");

            if (enabled)
            {
                string executablePath = Environment.ProcessPath
                    ?? throw new InvalidOperationException("Unable to determine the application executable path.");
                key.SetValue(
                    ValueName,
                    $"\"{executablePath}\" {LaunchArgument}",
                    RegistryValueKind.String);
            }
            else
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }

            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            return false;
        }
    }
}
