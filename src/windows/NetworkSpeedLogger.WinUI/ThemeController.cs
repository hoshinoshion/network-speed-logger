using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.UI.ViewManagement;

namespace NetworkSpeedLogger;

internal sealed class ThemeController : IDisposable
{
    private readonly FrameworkElement _root;
    private readonly AppWindow _appWindow;
    private readonly DispatcherQueue _dispatcherQueue;
    private readonly UISettings _uiSettings = new();
    private string _preference;
    private bool _disposed;

    public ThemeController(
        FrameworkElement root,
        AppWindow appWindow,
        DispatcherQueue dispatcherQueue,
        string? preference)
    {
        _root = root;
        _appWindow = appWindow;
        _dispatcherQueue = dispatcherQueue;
        _preference = Normalize(preference);
        _root.ActualThemeChanged += Root_ActualThemeChanged;
        _uiSettings.ColorValuesChanged += UiSettings_ColorValuesChanged;
        ApplyCurrentTheme();
    }

    public void ApplyPreference(string? preference)
    {
        _preference = Normalize(preference);
        ApplyCurrentTheme();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _root.ActualThemeChanged -= Root_ActualThemeChanged;
        _uiSettings.ColorValuesChanged -= UiSettings_ColorValuesChanged;
    }

    private void UiSettings_ColorValuesChanged(UISettings sender, object args)
    {
        _dispatcherQueue.TryEnqueue(() =>
        {
            if (!_disposed && _preference == "Auto") ApplyCurrentTheme();
        });
    }

    private void Root_ActualThemeChanged(FrameworkElement sender, object args) => UpdateTitleBar();

    private void ApplyCurrentTheme()
    {
        _root.RequestedTheme = _preference switch
        {
            "Light" => ElementTheme.Light,
            "Dark" => ElementTheme.Dark,
            _ => SystemUsesDarkTheme() ? ElementTheme.Dark : ElementTheme.Light
        };
        UpdateTitleBar();
    }

    private bool SystemUsesDarkTheme()
    {
        try
        {
            Windows.UI.Color background = _uiSettings.GetColorValue(UIColorType.Background);
            int perceivedBrightness = 5 * background.G + 2 * background.R + background.B;
            return perceivedBrightness <= 8 * 128;
        }
        catch
        {
            return Application.Current.RequestedTheme == ApplicationTheme.Dark;
        }
    }

    private void UpdateTitleBar()
    {
        try
        {
            bool dark = _root.ActualTheme == ElementTheme.Dark;
            _appWindow.TitleBar.ButtonForegroundColor = dark ? Colors.White : Colors.Black;
            _appWindow.TitleBar.ButtonInactiveForegroundColor = dark ? Colors.White : Colors.Black;
            _appWindow.TitleBar.ButtonBackgroundColor = Colors.Transparent;
            _appWindow.TitleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
        }
        catch
        {
        }
    }

    private static string Normalize(string? preference) => preference is "Light" or "Dark" ? preference : "Auto";
}
