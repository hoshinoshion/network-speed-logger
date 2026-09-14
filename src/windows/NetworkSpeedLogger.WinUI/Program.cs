using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace NetworkSpeedLogger;

public static class Program
{
    private const string InstanceKey = "NetworkSpeedLogger.Main";
    private static nint _redirectEventHandle;
    private static App? _app;

    [STAThread]
    public static int Main(string[] args)
    {
        WinRT.ComWrappersSupport.InitializeComWrappers();
        if (DecideRedirection()) return 0;

        Application.Start(_ =>
        {
            var context = new DispatcherQueueSynchronizationContext(
                DispatcherQueue.GetForCurrentThread());
            SynchronizationContext.SetSynchronizationContext(context);
            _app = new App();
        });

        return 0;
    }

    private static bool DecideRedirection()
    {
        AppActivationArguments activationArguments =
            AppInstance.GetCurrent().GetActivatedEventArgs();
        AppInstance mainInstance = AppInstance.FindOrRegisterForKey(InstanceKey);

        if (mainInstance.IsCurrent)
        {
            mainInstance.Activated += OnActivated;
            return false;
        }

        RedirectActivationTo(activationArguments, mainInstance);
        return true;
    }

    private static void OnActivated(object? sender, AppActivationArguments args)
    {
        if (Application.Current is App app)
        {
            app.HandleRedirectedActivation();
        }
    }

    private static void RedirectActivationTo(
        AppActivationArguments activationArguments,
        AppInstance mainInstance)
    {
        _redirectEventHandle = CreateEvent(nint.Zero, true, false, null);
        if (_redirectEventHandle == nint.Zero)
        {
            mainInstance.RedirectActivationToAsync(activationArguments)
                .AsTask()
                .GetAwaiter()
                .GetResult();
            BringProcessWindowToForeground(mainInstance.ProcessId);
            return;
        }

        _ = Task.Run(() =>
        {
            try
            {
                mainInstance.RedirectActivationToAsync(activationArguments)
                    .AsTask()
                    .GetAwaiter()
                    .GetResult();
            }
            finally
            {
                SetEvent(_redirectEventHandle);
            }
        });

        _ = CoWaitForMultipleObjects(
            0,
            0xFFFFFFFF,
            1,
            [_redirectEventHandle],
            out _);

        BringProcessWindowToForeground(mainInstance.ProcessId);
        CloseHandle(_redirectEventHandle);
        _redirectEventHandle = nint.Zero;
    }

    private static void BringProcessWindowToForeground(uint processId)
    {
        try
        {
            using Process process = Process.GetProcessById((int)processId);
            nint windowHandle = process.MainWindowHandle;
            if (windowHandle != nint.Zero) SetForegroundWindow(windowHandle);
        }
        catch
        {
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint CreateEvent(
        nint eventAttributes,
        bool manualReset,
        bool initialState,
        string? name);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetEvent(nint eventHandle);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(nint handle);

    [DllImport("ole32.dll")]
    private static extern uint CoWaitForMultipleObjects(
        uint flags,
        uint milliseconds,
        ulong handleCount,
        nint[] handles,
        out uint index);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(nint windowHandle);
}
