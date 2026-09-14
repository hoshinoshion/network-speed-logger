using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace NetworkSpeedLogger;

public partial class App : Application
{
    private readonly DispatcherQueue _dispatcherQueue;
    private Window? _window;
    private bool _redirectedActivationPending;

    public App()
    {
        _dispatcherQueue = DispatcherQueue.GetForCurrentThread();
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            WriteCrashLog("AppDomain.UnhandledException", args.ExceptionObject as Exception);
        UnhandledException += OnUnhandledException;
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            var mainWindow = new MainWindow();
            _window = mainWindow;
            mainWindow.Activate();
            if (_redirectedActivationPending)
            {
                _redirectedActivationPending = false;
                mainWindow.ActivateFromSecondaryLaunch();
            }
        }
        catch (Exception exception)
        {
            WriteCrashLog("App.OnLaunched", exception);
            throw;
        }
    }

    internal void HandleRedirectedActivation()
    {
        _dispatcherQueue.TryEnqueue(() =>
        {
            if (_window is MainWindow mainWindow)
            {
                mainWindow.ActivateFromSecondaryLaunch();
            }
            else
            {
                _redirectedActivationPending = true;
            }
        });
    }

    private static void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        WriteCrashLog("Application.UnhandledException", e.Exception);
        System.Diagnostics.Debug.WriteLine(e.Exception);
    }

    private static void WriteCrashLog(string source, Exception? exception)
    {
        try
        {
            string folder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "NetworkSpeedLogger");
            Directory.CreateDirectory(folder);
            string entry = $"[{DateTimeOffset.Now:O}] {source}{Environment.NewLine}" +
                           (exception?.ToString() ?? "Unknown exception") +
                           Environment.NewLine + Environment.NewLine;
            File.AppendAllText(Path.Combine(folder, "crash.log"), entry);
        }
        catch
        {
        }
    }
}
