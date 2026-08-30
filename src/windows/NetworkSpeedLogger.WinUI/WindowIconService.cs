using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;

namespace NetworkSpeedLogger;

internal static class WindowIconService
{
    private const uint ImageIcon = 1;
    private const uint LoadFromFile = 0x0010;
    private const uint WmSetIcon = 0x0080;
    private const nuint IconSmall = 0;
    private const nuint IconBig = 1;
    private const int SmCxIcon = 11;
    private const int SmCyIcon = 12;
    private const int SmCxSmallIcon = 49;
    private const int SmCySmallIcon = 50;

    private static nint _largeIcon;
    private static nint _smallIcon;

    public static void Apply(nint windowHandle, AppWindow appWindow)
    {
        string iconPath = Path.Combine(AppContext.BaseDirectory, "NetworkSpeedLogger.ico");
        if (!File.Exists(iconPath)) return;

        try
        {
            appWindow.SetIcon(iconPath);

            _largeIcon = LoadIcon(iconPath, SmCxIcon, SmCyIcon, _largeIcon);
            _smallIcon = LoadIcon(iconPath, SmCxSmallIcon, SmCySmallIcon, _smallIcon);
            if (_largeIcon != 0) SendMessage(windowHandle, WmSetIcon, IconBig, _largeIcon);
            if (_smallIcon != 0) SendMessage(windowHandle, WmSetIcon, IconSmall, _smallIcon);
        }
        catch
        {
            // The embedded executable icon remains available as a fallback.
        }
    }

    private static nint LoadIcon(string path, int widthMetric, int heightMetric, nint existing)
    {
        if (existing != 0) return existing;
        int width = GetSystemMetrics(widthMetric);
        int height = GetSystemMetrics(heightMetric);
        return LoadImage(0, path, ImageIcon, width, height, LoadFromFile);
    }

    [DllImport("user32.dll", EntryPoint = "LoadImageW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint LoadImage(nint instance, string name, uint type, int width, int height, uint loadFlags);

    [DllImport("user32.dll", EntryPoint = "SendMessageW")]
    private static extern nint SendMessage(nint windowHandle, uint message, nuint wParam, nint lParam);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);
}
