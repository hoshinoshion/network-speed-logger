using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Windows.Graphics;

namespace NetworkSpeedLogger;

internal static class WindowSizing
{
    private const double MaximumWorkAreaRatio = 0.94;

    public static void ResizeAndCenter(
        AppWindow appWindow,
        WindowId windowId,
        nint windowHandle,
        double desiredWidthDip,
        double desiredHeightDip)
    {
        DisplayArea displayArea = DisplayArea.GetFromWindowId(windowId, DisplayAreaFallback.Primary);
        RectInt32 workArea = displayArea.WorkArea;
        double scale = Math.Max(1.0, GetDpiForWindow(windowHandle) / 96.0);

        int maximumWidth = Math.Max(640, (int)Math.Round(workArea.Width * MaximumWorkAreaRatio));
        int maximumHeight = Math.Max(480, (int)Math.Round(workArea.Height * MaximumWorkAreaRatio));
        int width = Math.Clamp((int)Math.Round(desiredWidthDip * scale), 640, maximumWidth);
        int height = Math.Clamp((int)Math.Round(desiredHeightDip * scale), 480, maximumHeight);
        int x = workArea.X + Math.Max(0, (workArea.Width - width) / 2);
        int y = workArea.Y + Math.Max(0, (workArea.Height - height) / 2);

        appWindow.MoveAndResize(new RectInt32(x, y, width, height));
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint windowHandle);
}
