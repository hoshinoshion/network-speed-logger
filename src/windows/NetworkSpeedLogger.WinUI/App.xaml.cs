using Microsoft.UI.Xaml;

namespace NetworkSpeedLogger;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            WriteCrashLog("AppDomain.UnhandledException", args.ExceptionObject as Exception);
        UnhandledException += OnUnhandledException;
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            _window = new MainWindow();
            _window.Activate();
        }
        catch (Exception exception)
        {
            WriteCrashLog("App.OnLaunched", exception);
            throw;
        }
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
