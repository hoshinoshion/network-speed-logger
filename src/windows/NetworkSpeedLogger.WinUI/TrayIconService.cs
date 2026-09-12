using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;

namespace NetworkSpeedLogger;

internal sealed class TrayIconService : IDisposable
{
    private const uint CallbackMessage = 0x8001; // WM_APP + 1
    private const uint NimAdd = 0x00000000;
    private const uint NimModify = 0x00000001;
    private const uint NimDelete = 0x00000002;
    private const uint NifMessage = 0x00000001;
    private const uint NifIcon = 0x00000002;
    private const uint NifTip = 0x00000004;
    private const uint NifInfo = 0x00000010;
    private const uint NifRealtime = 0x00000040;
    private const uint NiifInfo = 0x00000001;
    private const uint WmNull = 0x0000;
    private const uint WmNcDestroy = 0x0082;
    private const uint WmLButtonUp = 0x0202;
    private const uint WmLButtonDoubleClick = 0x0203;
    private const uint WmRButtonUp = 0x0205;
    private const uint WmContextMenu = 0x007B;
    private const uint ImageIcon = 1;
    private const uint LrLoadFromFile = 0x00000010;
    private const uint LrDefaultSize = 0x00000040;
    private const uint MfString = 0x00000000;
    private const uint MfGrayed = 0x00000001;
    private const uint MfSeparator = 0x00000800;
    private const uint TpmRightButton = 0x0002;
    private const uint TpmNoNotify = 0x0080;
    private const uint TpmReturnCommand = 0x0100;
    private const uint StartCommand = 1;
    private const uint StopCommand = 2;
    private const uint ExitCommand = 3;
    private const int IdiApplication = 32512;
    private static readonly nuint SubclassId = 1;

    private readonly nint _windowHandle;
    private readonly DispatcherQueue _dispatcherQueue;
    private readonly DispatcherQueueTimer _notificationTimer;
    private readonly SubclassProcedure _subclassProcedure;
    private readonly uint _taskbarCreatedMessage;
    private nint _iconHandle;
    private bool _ownsIcon;
    private bool _isVisible;
    private bool _isRecording;
    private bool _subclassAttached;
    private bool _disposed;
    private string _toolTip = "Network Speed Logger";
    private string _startText = "Start";
    private string _stopText = "Stop";
    private string _exitText = "Exit";

    public TrayIconService(nint windowHandle, DispatcherQueue dispatcherQueue)
    {
        _windowHandle = windowHandle;
        _dispatcherQueue = dispatcherQueue;
        _notificationTimer = dispatcherQueue.CreateTimer();
        _notificationTimer.Interval = TimeSpan.FromSeconds(5);
        _notificationTimer.IsRepeating = false;
        _notificationTimer.Tick += (_, _) => ClearNotification();
        _subclassProcedure = WindowProc;
        _taskbarCreatedMessage = RegisterWindowMessageW("TaskbarCreated");
        _iconHandle = LoadTrayIcon(out _ownsIcon);
        if (!SetWindowSubclass(_windowHandle, _subclassProcedure, SubclassId, 0))
            throw new InvalidOperationException("Unable to attach the notification-area icon to the application window.");
        _subclassAttached = true;
    }

    public event Action? OpenRequested;
    public event Action? StartRequested;
    public event Action? StopRequested;
    public event Action? ExitRequested;

    public bool IsVisible => _isVisible;

    public void UpdateText(string toolTip, string startText, string stopText, string exitText)
    {
        _toolTip = toolTip;
        _startText = startText;
        _stopText = stopText;
        _exitText = exitText;
        if (_isVisible) ModifyToolTip();
    }

    public void SetRecordingState(bool isRecording) => _isRecording = isRecording;

    public bool Show(string notificationTitle, string notificationBody)
    {
        if (_disposed) return false;
        if (!_isVisible && !AddIcon()) return false;
        if (!string.IsNullOrEmpty(notificationBody))
            ShowNotification(notificationTitle, notificationBody);
        return true;
    }

    public void Hide()
    {
        if (!_isVisible) return;
        _notificationTimer.Stop();
        NotifyIconData data = CreateData();
        Shell_NotifyIconW(NimDelete, ref data);
        _isVisible = false;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _notificationTimer.Stop();
        Hide();

        if (_subclassAttached)
        {
            RemoveWindowSubclass(_windowHandle, _subclassProcedure, SubclassId);
            _subclassAttached = false;
        }

        if (_ownsIcon && _iconHandle != 0)
            DestroyIcon(_iconHandle);
        _iconHandle = 0;
    }

    private bool AddIcon()
    {
        if (_iconHandle == 0) return false;
        NotifyIconData data = CreateData();
        data.uFlags = NifMessage | NifIcon | NifTip;
        data.uCallbackMessage = CallbackMessage;
        data.hIcon = _iconHandle;
        data.szTip = Truncate(_toolTip, 127);
        _isVisible = Shell_NotifyIconW(NimAdd, ref data);
        return _isVisible;
    }

    private void ModifyToolTip()
    {
        NotifyIconData data = CreateData();
        data.uFlags = NifTip;
        data.szTip = Truncate(_toolTip, 127);
        Shell_NotifyIconW(NimModify, ref data);
    }

    private void ShowNotification(string title, string body)
    {
        NotifyIconData data = CreateData();
        data.uFlags = NifInfo | NifRealtime;
        data.szInfoTitle = Truncate(title, 63);
        data.szInfo = Truncate(body, 255);
        data.dwInfoFlags = NiifInfo;
        if (Shell_NotifyIconW(NimModify, ref data))
        {
            _notificationTimer.Stop();
            _notificationTimer.Start();
        }
    }

    private void ClearNotification()
    {
        _notificationTimer.Stop();
        if (!_isVisible) return;
        NotifyIconData data = CreateData();
        data.uFlags = NifInfo;
        data.szInfo = string.Empty;
        Shell_NotifyIconW(NimModify, ref data);
    }

    private NotifyIconData CreateData() => new()
    {
        cbSize = (uint)Marshal.SizeOf<NotifyIconData>(),
        hWnd = _windowHandle,
        uID = 1,
        szTip = string.Empty,
        szInfo = string.Empty,
        szInfoTitle = string.Empty
    };

    private nint WindowProc(
        nint windowHandle,
        uint message,
        nint wParam,
        nint lParam,
        nuint subclassId,
        nuint referenceData)
    {
        if (message == CallbackMessage)
        {
            uint notification = unchecked((uint)lParam.ToInt64());
            switch (notification)
            {
                case WmLButtonUp:
                case WmLButtonDoubleClick:
                    Enqueue(() => OpenRequested?.Invoke());
                    return 0;

                case WmRButtonUp:
                case WmContextMenu:
                    ShowContextMenu();
                    return 0;
            }
        }
        else if (message == _taskbarCreatedMessage && _isVisible)
        {
            _isVisible = false;
            AddIcon();
        }
        else if (message == WmNcDestroy && _subclassAttached)
        {
            Hide();
            RemoveWindowSubclass(windowHandle, _subclassProcedure, subclassId);
            _subclassAttached = false;
        }
        return DefSubclassProc(windowHandle, message, wParam, lParam);
    }

    private void ShowContextMenu()
    {
        if (!GetCursorPos(out Point cursor)) return;
        nint menu = CreatePopupMenu();
        if (menu == 0) return;

        try
        {
            AppendMenuW(menu, MfString | (_isRecording ? MfGrayed : 0), StartCommand, _startText);
            AppendMenuW(menu, MfString | (_isRecording ? 0 : MfGrayed), StopCommand, _stopText);
            AppendMenuW(menu, MfSeparator, 0, null);
            AppendMenuW(menu, MfString, ExitCommand, _exitText);

            SetForegroundWindow(_windowHandle);
            uint command = TrackPopupMenuEx(
                menu,
                TpmRightButton | TpmNoNotify | TpmReturnCommand,
                cursor.X,
                cursor.Y,
                _windowHandle,
                0);
            if (command != 0) HandleCommand(command);
            PostMessageW(_windowHandle, WmNull, 0, 0);
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    private void HandleCommand(uint command)
    {
        switch (command)
        {
            case StartCommand when !_isRecording:
                Enqueue(() => StartRequested?.Invoke());
                break;
            case StopCommand when _isRecording:
                Enqueue(() => StopRequested?.Invoke());
                break;
            case ExitCommand:
                Enqueue(() => ExitRequested?.Invoke());
                break;
        }
    }

    private void Enqueue(Action action)
    {
        if (!_dispatcherQueue.TryEnqueue(() =>
            {
                if (!_disposed) action();
            }))
        {
            // The application is already shutting down.
        }
    }

    private static nint LoadTrayIcon(out bool ownsIcon)
    {
        string iconPath = Path.Combine(AppContext.BaseDirectory, "NetworkSpeedLogger.ico");
        nint icon = LoadImageW(0, iconPath, ImageIcon, 0, 0, LrLoadFromFile | LrDefaultSize);
        if (icon != 0)
        {
            ownsIcon = true;
            return icon;
        }

        ownsIcon = false;
        return LoadIconW(0, (nint)IdiApplication);
    }

    private static string Truncate(string value, int maximumLength) =>
        value.Length <= maximumLength ? value : value[..maximumLength];

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint SubclassProcedure(
        nint windowHandle,
        uint message,
        nint wParam,
        nint lParam,
        nuint subclassId,
        nuint referenceData);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public uint cbSize;
        public nint hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public nint hIcon;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip;

        public uint dwState;
        public uint dwStateMask;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szInfo;

        public uint uTimeoutOrVersion;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string szInfoTitle;

        public uint dwInfoFlags;
        public Guid guidItem;
        public nint hBalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Shell_NotifyIconW(uint message, ref NotifyIconData data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern nint LoadImageW(nint instance, string name, uint type, int width, int height, uint load);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern nint LoadIconW(nint instance, nint iconName);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(nint icon);

    [DllImport("comctl32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowSubclass(
        nint windowHandle,
        SubclassProcedure subclassProcedure,
        nuint subclassId,
        nuint referenceData);

    [DllImport("comctl32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RemoveWindowSubclass(
        nint windowHandle,
        SubclassProcedure subclassProcedure,
        nuint subclassId);

    [DllImport("comctl32.dll", ExactSpelling = true)]
    private static extern nint DefSubclassProc(nint windowHandle, uint message, nint wParam, nint lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern uint RegisterWindowMessageW(string message);

    [DllImport("user32.dll")]
    private static extern nint CreatePopupMenu();

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AppendMenuW(nint menu, uint flags, nuint item, string? text);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyMenu(nint menu);

    [DllImport("user32.dll")]
    private static extern uint TrackPopupMenuEx(nint menu, uint flags, int x, int y, nint windowHandle, nint parameters);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(nint windowHandle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessageW(nint windowHandle, uint message, nint wParam, nint lParam);
}
