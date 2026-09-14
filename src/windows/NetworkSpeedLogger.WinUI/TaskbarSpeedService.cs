using System.Diagnostics;
using System.Globalization;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.UI.Dispatching;
using Microsoft.Win32;

namespace NetworkSpeedLogger;

internal sealed class TaskbarSpeedService : IDisposable
{
    private readonly NetworkAdapterService _adapterService;
    private readonly DispatcherQueueTimer _sampleTimer;
    private readonly DispatcherQueueTimer _layoutTimer;
    private readonly TaskbarSpeedOverlay? _overlay;
    private readonly Stopwatch _stopwatch = new();
    private Dictionary<string, CounterSnapshot> _previousSnapshot = new(StringComparer.OrdinalIgnoreCase);
    private TaskbarSpeedSettings _settings = new();
    private double _lastSampleElapsed;
    private double _lastPhysicalRefreshElapsed;
    private double _downloadBytesPerSecond;
    private double _uploadBytesPerSecond;
    private bool _disposed;

    public TaskbarSpeedService(DispatcherQueue dispatcherQueue, NetworkAdapterService adapterService)
    {
        _adapterService = adapterService;
        _sampleTimer = dispatcherQueue.CreateTimer();
        _sampleTimer.IsRepeating = true;
        _sampleTimer.Tick += SampleTimer_Tick;
        _layoutTimer = dispatcherQueue.CreateTimer();
        _layoutTimer.Interval = TimeSpan.FromSeconds(1);
        _layoutTimer.IsRepeating = true;
        _layoutTimer.Tick += LayoutTimer_Tick;

        try
        {
            _overlay = new TaskbarSpeedOverlay();
        }
        catch (Exception exception)
        {
            Debug.WriteLine("Unable to create the taskbar speed overlay: " + exception);
        }
    }

    public void ApplySettings(TaskbarSpeedSettings settings)
    {
        if (_disposed) return;
        _sampleTimer.Stop();
        _layoutTimer.Stop();
        _stopwatch.Stop();
        _overlay?.Hide();

        _settings = settings.Clone();
        _previousSnapshot.Clear();
        _lastSampleElapsed = 0;
        _lastPhysicalRefreshElapsed = 0;
        _downloadBytesPerSecond = 0;
        _uploadBytesPerSecond = 0;

        if (!_settings.Enabled || _overlay is null) return;

        EstablishBaseline();
        _sampleTimer.Interval = TimeSpan.FromSeconds(_settings.SampleIntervalSeconds);
        _stopwatch.Restart();
        UpdateOverlay();
        _sampleTimer.Start();
        _layoutTimer.Start();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _sampleTimer.Stop();
        _layoutTimer.Stop();
        _stopwatch.Stop();
        _overlay?.Dispose();
    }

    private void EstablishBaseline()
    {
        try
        {
            if (!_settings.ManualMode) _adapterService.RefreshPhysicalAdapterIds();
            List<NetworkInterface> adapters = _adapterService.ResolveActiveAdapters(
                _settings.ManualMode,
                _settings.SelectedAdapterIds);
            _previousSnapshot = NetworkAdapterService.SnapshotAdapters(adapters);
        }
        catch
        {
            _previousSnapshot = new Dictionary<string, CounterSnapshot>(StringComparer.OrdinalIgnoreCase);
        }
    }

    private void SampleTimer_Tick(DispatcherQueueTimer sender, object args)
    {
        if (_disposed || !_settings.Enabled) return;

        try
        {
            double currentElapsed = _stopwatch.Elapsed.TotalSeconds;
            double interval = currentElapsed - _lastSampleElapsed;
            if (interval <= 0.05) return;
            _lastSampleElapsed = currentElapsed;

            if (!_settings.ManualMode && currentElapsed - _lastPhysicalRefreshElapsed >= 30.0)
            {
                _adapterService.RefreshPhysicalAdapterIds();
                _lastPhysicalRefreshElapsed = currentElapsed;
            }

            List<NetworkInterface> currentAdapters = _adapterService.ResolveActiveAdapters(
                _settings.ManualMode,
                _settings.SelectedAdapterIds);

            var adaptersToQuery = new Dictionary<string, NetworkInterface>(StringComparer.OrdinalIgnoreCase);
            foreach ((string id, CounterSnapshot snapshot) in _previousSnapshot)
                adaptersToQuery[id] = snapshot.Adapter;
            foreach (NetworkInterface adapter in currentAdapters)
                adaptersToQuery[NetworkAdapterService.NormalizeId(adapter.Id)] = adapter;

            Dictionary<string, CounterSnapshot> snapshotNow =
                NetworkAdapterService.SnapshotAdapters(adaptersToQuery.Values);
            double receivedDelta = 0;
            double sentDelta = 0;
            foreach ((string id, CounterSnapshot current) in snapshotNow)
            {
                if (!_previousSnapshot.TryGetValue(id, out CounterSnapshot? previous)) continue;
                if (current.Received >= previous.Received) receivedDelta += current.Received - previous.Received;
                if (current.Sent >= previous.Sent) sentDelta += current.Sent - previous.Sent;
            }

            var nextSnapshot = new Dictionary<string, CounterSnapshot>(StringComparer.OrdinalIgnoreCase);
            foreach (NetworkInterface adapter in currentAdapters)
            {
                string id = NetworkAdapterService.NormalizeId(adapter.Id);
                if (snapshotNow.TryGetValue(id, out CounterSnapshot? snapshot)) nextSnapshot[id] = snapshot;
            }
            _previousSnapshot = nextSnapshot;

            _downloadBytesPerSecond = receivedDelta / interval;
            _uploadBytesPerSecond = sentDelta / interval;
            UpdateOverlay();
        }
        catch (Exception exception)
        {
            Debug.WriteLine("Unable to sample taskbar network speed: " + exception);
            EstablishBaseline();
            _stopwatch.Restart();
            _lastSampleElapsed = 0;
            _lastPhysicalRefreshElapsed = 0;
            _downloadBytesPerSecond = 0;
            _uploadBytesPerSecond = 0;
            UpdateOverlay();
        }
    }

    private void LayoutTimer_Tick(DispatcherQueueTimer sender, object args) => UpdateOverlay();

    private void UpdateOverlay()
    {
        _overlay?.Update(
            "↑ " + TaskbarSpeedFormatter.Format(_uploadBytesPerSecond, _settings.SpeedUnit),
            "↓ " + TaskbarSpeedFormatter.Format(_downloadBytesPerSecond, _settings.SpeedUnit),
            _settings.SingleLine);
    }
}

internal static class TaskbarSpeedFormatter
{
    public static string Format(double bytesPerSecond, string unit)
    {
        bool bits = string.Equals(unit, "bit", StringComparison.Ordinal);
        double value = Math.Max(0, double.IsFinite(bytesPerSecond) ? bytesPerSecond : 0) * (bits ? 8.0 : 1.0);
        string[] suffixes = bits
            ? ["bps", "Kbps", "Mbps", "Gbps", "Tbps"]
            : ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"];
        int suffixIndex = 0;
        while (value >= 1000.0 && suffixIndex < suffixes.Length - 1)
        {
            value /= 1000.0;
            suffixIndex++;
        }

        string format = value switch
        {
            0 => "0",
            >= 100 => "0",
            >= 10 => "0.0",
            _ => "0.00"
        };
        return value.ToString(format, CultureInfo.InvariantCulture) + " " + suffixes[suffixIndex];
    }
}

internal sealed class TaskbarSpeedOverlay : IDisposable
{
    private const uint WsPopup = 0x80000000;
    private const uint WsExTransparent = 0x00000020;
    private const uint WsExToolWindow = 0x00000080;
    private const uint WsExLayered = 0x00080000;
    private const uint WsExNoActivate = 0x08000000;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private const uint SwpNoOwnerZOrder = 0x0200;
    private const int SwHide = 0;
    private const uint WmMouseActivate = 0x0021;
    private const uint WmNcHitTest = 0x0084;
    private const uint EventSystemForeground = 0x0003;
    private const uint WinEventOutOfContext = 0x0000;
    private const uint WinEventSkipOwnProcess = 0x0002;
    private const int HtTransparent = -1;
    private const int MaNoActivate = 3;
    private const int DefaultCharset = 1;
    private const int OutDefaultPrecis = 0;
    private const int ClipDefaultPrecis = 0;
    private const int AntialiasedQuality = 4;
    private const int DefaultPitch = 0;
    private const int TransparentBackground = 1;
    private const uint DtCenter = 0x00000001;
    private const uint DtRight = 0x00000002;
    private const uint DtVCenter = 0x00000004;
    private const uint DtSingleLine = 0x00000020;
    private const uint DtNoPrefix = 0x00000800;
    private const uint DibRgbColors = 0;
    private const uint BiRgb = 0;
    private const uint UlwAlpha = 0x00000002;
    private const byte AcSrcOver = 0;
    private const byte AcSrcAlpha = 1;
    private const int ColorWindowText = 8;
    private const uint SpiGetHighContrast = 0x0042;
    private const uint HcfHighContrastOn = 0x00000001;
    private const uint MonitorDefaultToNearest = 2;
    private const int GwlpHwndParent = -8;
    private const int CenteredTaskbarLeftReserveDip = 184;
    private const int TaskbarControlGapDip = 8;
    private const int TwoLineWidthDip = 164;
    private const int SingleLineWidthDip = 236;
    private const int SingleLineGapDip = 18;
    private const int TwoLineFontSizeDip = 12;
    private const int SingleLineFontSizeDip = 14;
    private const int TextRenderScale = 4;
    private const string TaskbarAlignmentPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";
    private static readonly nint HwndTop = 0;
    private static readonly bool Windows11OrLater = DetectWindows11OrLater();
    private static readonly WindowProcedureDelegate WindowProcedureInstance = WindowProcedure;

    private readonly string _className = "NetworkSpeedLogger.TaskbarSpeed." + Environment.ProcessId;
    private readonly nint _instanceHandle;
    private readonly WinEventProcedureDelegate _foregroundChanged;
    private nint _windowHandle;
    private nint _foregroundHook;
    private nint _taskbarOwner;
    private bool _registeredClass;
    private bool _disposed;

    public TaskbarSpeedOverlay()
    {
        _foregroundChanged = ForegroundWindowChanged;
        _instanceHandle = GetModuleHandleW(null);
        var windowClass = new WindowClassEx
        {
            cbSize = (uint)Marshal.SizeOf<WindowClassEx>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(WindowProcedureInstance),
            hInstance = _instanceHandle,
            lpszClassName = _className
        };
        ushort atom = RegisterClassExW(ref windowClass);
        if (atom == 0)
            throw new InvalidOperationException("Unable to register the taskbar speed window class.");
        _registeredClass = true;

        if (!CreateOverlayWindow())
        {
            UnregisterClassW(_className, _instanceHandle);
            _registeredClass = false;
            throw new InvalidOperationException("Unable to create the taskbar speed window.");
        }

        _foregroundHook = SetWinEventHook(
            EventSystemForeground,
            EventSystemForeground,
            0,
            _foregroundChanged,
            0,
            0,
            WinEventOutOfContext | WinEventSkipOwnProcess);
    }

    public void Update(string topText, string bottomText, bool singleLine)
    {
        if (_disposed || !EnsureOverlayWindow()) return;
        TaskbarPlacementStatus status = TryGetPlacement(singleLine, out TaskbarPlacement placement);
        if (status == TaskbarPlacementStatus.Hidden)
        {
            Hide();
            return;
        }
        if (status != TaskbarPlacementStatus.Visible) return;

        EnsureTaskbarOwner(placement.TaskbarHandle);
        Render(topText, bottomText, singleLine, placement);
    }

    public void Hide()
    {
        if (!_disposed && _windowHandle != 0 && IsWindow(_windowHandle)) ShowWindow(_windowHandle, SwHide);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_foregroundHook != 0)
        {
            UnhookWinEvent(_foregroundHook);
            _foregroundHook = 0;
        }
        if (_windowHandle != 0 && IsWindow(_windowHandle)) DestroyWindow(_windowHandle);
        _windowHandle = 0;
        if (_registeredClass)
        {
            UnregisterClassW(_className, _instanceHandle);
            _registeredClass = false;
        }
    }

    private void ForegroundWindowChanged(
        nint hook,
        uint eventType,
        nint window,
        int objectId,
        int childId,
        uint eventThread,
        uint eventTime)
    {
        if (_disposed || _windowHandle == 0 || !IsWindow(_windowHandle) || !IsWindowVisible(_windowHandle)) return;
        SetWindowPos(
            _windowHandle,
            HwndTop,
            0,
            0,
            0,
            0,
            SwpNoMove | SwpNoSize | SwpNoActivate | SwpNoOwnerZOrder);
    }

    private bool EnsureOverlayWindow()
    {
        if (_windowHandle != 0 && IsWindow(_windowHandle)) return true;
        _windowHandle = 0;
        return CreateOverlayWindow();
    }

    private bool CreateOverlayWindow()
    {
        _taskbarOwner = FindWindowW("Shell_TrayWnd", null);
        _windowHandle = CreateWindowExW(
            WsExLayered | WsExTransparent | WsExToolWindow | WsExNoActivate,
            _className,
            string.Empty,
            WsPopup,
            0,
            0,
            0,
            0,
            _taskbarOwner,
            0,
            _instanceHandle,
            0);
        return _windowHandle != 0;
    }

    private void EnsureTaskbarOwner(nint taskbar)
    {
        if (taskbar == 0 || taskbar == _taskbarOwner) return;
        SetWindowLongPtrW(_windowHandle, GwlpHwndParent, taskbar);
        _taskbarOwner = taskbar;
    }

    private void Render(string topText, string bottomText, bool singleLine, TaskbarPlacement placement)
    {
        nint screenDc = GetDC(0);
        if (screenDc == 0) return;
        nint renderDc = CreateCompatibleDC(screenDc);
        nint renderBitmap = 0;
        nint previousRenderBitmap = 0;
        nint outputDc = 0;
        nint outputBitmap = 0;
        nint previousOutputBitmap = 0;
        nint font = 0;
        nint previousFont = 0;

        try
        {
            if (renderDc == 0) return;

            bool horizontalSingleLine = singleLine && !placement.IsVertical;
            // Layered windows need grayscale alpha instead of ClearType color fringes. Render the
            // taskbar text at higher resolution, then average coverage back to device pixels.
            int renderScale = TextRenderScale;
            int renderWidth = checked(placement.Width * renderScale);
            int renderHeight = checked(placement.Height * renderScale);
            var renderBitmapInfo = new BitmapInfo
            {
                Header = new BitmapInfoHeader
                {
                    Size = (uint)Marshal.SizeOf<BitmapInfoHeader>(),
                    Width = renderWidth,
                    Height = -renderHeight,
                    Planes = 1,
                    BitCount = 32,
                    Compression = BiRgb
                }
            };
            renderBitmap = CreateDIBSection(renderDc, ref renderBitmapInfo, DibRgbColors, out nint renderBits, 0, 0);
            if (renderBitmap == 0 || renderBits == 0) return;
            previousRenderBitmap = SelectObject(renderDc, renderBitmap);
            PatBlt(renderDc, 0, 0, renderWidth, renderHeight, 0x00000042);

            int fontSizeDip = horizontalSingleLine
                ? SingleLineFontSizeDip
                : TwoLineFontSizeDip;
            int fontHeight = -checked(ScaleDip(fontSizeDip, placement.Dpi) * renderScale);
            font = CreateFontW(
                fontHeight,
                0,
                0,
                0,
                400,
                0,
                0,
                0,
                DefaultCharset,
                OutDefaultPrecis,
                ClipDefaultPrecis,
                AntialiasedQuality,
                DefaultPitch,
                Windows11OrLater ? "Segoe UI Variable Text" : "Segoe UI");
            if (font == 0) return;
            previousFont = SelectObject(renderDc, font);
            SetBkMode(renderDc, TransparentBackground);
            SetTextColor(renderDc, 0x00FFFFFF);

            int inset = checked(ScaleDip(6, placement.Dpi) * renderScale);
            uint baseFlags = DtSingleLine | DtVCenter | DtNoPrefix;
            if (horizontalSingleLine)
            {
                int gap = checked(ScaleDip(SingleLineGapDip, placement.Dpi) * renderScale);
                int uploadWidth = MeasureTextWidth(renderDc, topText);
                int downloadLeft = Math.Min(
                    renderWidth - inset,
                    inset + uploadWidth + gap);
                var uploadRect = new NativeRect(inset, 0, renderWidth - inset, renderHeight);
                var downloadRect = new NativeRect(
                    downloadLeft,
                    0,
                    renderWidth - inset,
                    renderHeight);
                DrawTextW(renderDc, topText, -1, ref uploadRect, baseFlags);
                DrawTextW(renderDc, bottomText, -1, ref downloadRect, baseFlags);
            }
            else
            {
                uint alignment = placement.AlignRight ? DtRight : placement.IsVertical ? DtCenter : 0;
                uint flags = baseFlags | alignment;
                int verticalInset = Math.Min(
                    checked(ScaleDip(3, placement.Dpi) * renderScale),
                    Math.Max(0, (renderHeight - 2) / 4));
                int contentHeight = Math.Max(2, renderHeight - verticalInset * 2);
                int rowHeight = contentHeight / 2;
                var topRect = new NativeRect(inset, verticalInset, renderWidth - inset, verticalInset + rowHeight);
                var bottomRect = new NativeRect(
                    inset,
                    verticalInset + rowHeight,
                    renderWidth - inset,
                    renderHeight - verticalInset);
                DrawTextW(renderDc, topText, -1, ref topRect, flags);
                DrawTextW(renderDc, bottomText, -1, ref bottomRect, flags);
            }

            int renderPixelCount = checked(renderWidth * renderHeight);
            var sourcePixels = new int[renderPixelCount];
            var sourceAlpha = new byte[renderPixelCount];
            Marshal.Copy(renderBits, sourcePixels, 0, renderPixelCount);
            for (int index = 0; index < renderPixelCount; index++)
            {
                int pixel = sourcePixels[index];
                sourceAlpha[index] = (byte)Math.Max(
                    pixel & 0xFF,
                    Math.Max((pixel >> 8) & 0xFF, (pixel >> 16) & 0xFF));
            }

            int pixelCount = checked(placement.Width * placement.Height);
            var alphaMask = new byte[pixelCount];
            int sampleCount = renderScale * renderScale;
            int rounding = sampleCount / 2;
            for (int y = 0; y < placement.Height; y++)
            {
                int sourceTop = y * renderScale;
                for (int x = 0; x < placement.Width; x++)
                {
                    int sourceLeft = x * renderScale;
                    int coverage = 0;
                    for (int sampleY = 0; sampleY < renderScale; sampleY++)
                    {
                        int sourceIndex = (sourceTop + sampleY) * renderWidth + sourceLeft;
                        for (int sampleX = 0; sampleX < renderScale; sampleX++)
                            coverage += sourceAlpha[sourceIndex + sampleX];
                    }
                    alphaMask[y * placement.Width + x] = (byte)((coverage + rounding) / sampleCount);
                }
            }

            RgbColor foreground = ResolveForegroundColor();
            var outputPixels = new int[pixelCount];
            for (int index = 0; index < pixelCount; index++)
            {
                int alpha = alphaMask[index];
                int red = foreground.R * alpha / 255;
                int green = foreground.G * alpha / 255;
                int blue = foreground.B * alpha / 255;
                outputPixels[index] = blue | (green << 8) | (red << 16) | (alpha << 24);
            }

            outputDc = CreateCompatibleDC(screenDc);
            if (outputDc == 0) return;
            var outputBitmapInfo = new BitmapInfo
            {
                Header = new BitmapInfoHeader
                {
                    Size = (uint)Marshal.SizeOf<BitmapInfoHeader>(),
                    Width = placement.Width,
                    Height = -placement.Height,
                    Planes = 1,
                    BitCount = 32,
                    Compression = BiRgb
                }
            };
            outputBitmap = CreateDIBSection(outputDc, ref outputBitmapInfo, DibRgbColors, out nint outputBits, 0, 0);
            if (outputBitmap == 0 || outputBits == 0) return;
            previousOutputBitmap = SelectObject(outputDc, outputBitmap);
            Marshal.Copy(outputPixels, 0, outputBits, pixelCount);

            var destination = new NativePoint(placement.X, placement.Y);
            var source = new NativePoint(0, 0);
            var size = new NativeSize(placement.Width, placement.Height);
            var blend = new BlendFunction
            {
                BlendOp = AcSrcOver,
                SourceConstantAlpha = 255,
                AlphaFormat = AcSrcAlpha
            };
            if (UpdateLayeredWindow(
                    _windowHandle,
                    screenDc,
                    ref destination,
                    ref size,
                    outputDc,
                    ref source,
                    0,
                    ref blend,
                    UlwAlpha))
            {
                SetWindowPos(
                    _windowHandle,
                    HwndTop,
                    0,
                    0,
                    0,
                    0,
                    SwpNoMove | SwpNoSize | SwpNoActivate | SwpShowWindow | SwpNoOwnerZOrder);
            }
        }
        finally
        {
            if (previousFont != 0) SelectObject(renderDc, previousFont);
            if (font != 0) DeleteObject(font);
            if (previousRenderBitmap != 0) SelectObject(renderDc, previousRenderBitmap);
            if (renderBitmap != 0) DeleteObject(renderBitmap);
            if (previousOutputBitmap != 0) SelectObject(outputDc, previousOutputBitmap);
            if (outputBitmap != 0) DeleteObject(outputBitmap);
            if (outputDc != 0) DeleteDC(outputDc);
            if (renderDc != 0) DeleteDC(renderDc);
            ReleaseDC(0, screenDc);
        }
    }

    private static int MeasureTextWidth(nint deviceContext, string text)
    {
        return GetTextExtentPoint32W(deviceContext, text, text.Length, out NativeSize size)
            ? Math.Max(0, size.Width)
            : 0;
    }

    private static TaskbarPlacementStatus TryGetPlacement(bool singleLine, out TaskbarPlacement placement)
    {
        placement = default;
        nint taskbar = FindWindowW("Shell_TrayWnd", null);
        if (taskbar == 0 || !IsWindowVisible(taskbar) || !GetWindowRect(taskbar, out NativeRect taskbarRect))
            return TaskbarPlacementStatus.Unavailable;

        nint monitor = MonitorFromWindow(taskbar, MonitorDefaultToNearest);
        var monitorInfo = new MonitorInfo { Size = (uint)Marshal.SizeOf<MonitorInfo>() };
        if (monitor == 0 || !GetMonitorInfoW(monitor, ref monitorInfo)) return TaskbarPlacementStatus.Unavailable;

        int visibleWidth = Math.Max(0, Math.Min(taskbarRect.Right, monitorInfo.Monitor.Right) - Math.Max(taskbarRect.Left, monitorInfo.Monitor.Left));
        int visibleHeight = Math.Max(0, Math.Min(taskbarRect.Bottom, monitorInfo.Monitor.Bottom) - Math.Max(taskbarRect.Top, monitorInfo.Monitor.Top));
        bool horizontal = taskbarRect.Width >= taskbarRect.Height * 3;
        if (horizontal && visibleHeight < Math.Max(4, taskbarRect.Height / 2)) return TaskbarPlacementStatus.Hidden;
        if (!horizontal && visibleWidth < Math.Max(4, taskbarRect.Width / 2)) return TaskbarPlacementStatus.Hidden;
        uint dpi = GetDpiForWindow(taskbar);
        if (dpi == 0) dpi = 96;
        bool centeredTaskbar = IsTaskbarCentered(taskbar, taskbarRect);

        if (horizontal)
        {
            int preferredWidth = singleLine ? SingleLineWidthDip : TwoLineWidthDip;
            int width = Math.Min(ScaleDip(preferredWidth, dpi), Math.Max(1, taskbarRect.Width - ScaleDip(16, dpi)));
            int height = Math.Min(ScaleDip(42, dpi), Math.Max(1, taskbarRect.Height - ScaleDip(2, dpi)));
            int x;
            bool alignRight;
            if (centeredTaskbar)
            {
                x = GetCenteredOverlayLeft(taskbar, taskbarRect, width, dpi);
                alignRight = false;
            }
            else
            {
                nint tray = FindTaskbarDescendant(taskbar, "TrayNotifyWnd");
                int rightBoundary = GetWindowRect(tray, out NativeRect trayRect)
                    ? trayRect.Left
                    : taskbarRect.Right - ScaleDip(150, dpi);
                x = rightBoundary - width - ScaleDip(8, dpi);
                x = Math.Clamp(x, taskbarRect.Left + ScaleDip(4, dpi), taskbarRect.Right - width - ScaleDip(4, dpi));
                alignRight = true;
            }
            int y = taskbarRect.Top + Math.Max(0, (taskbarRect.Height - height) / 2);
            placement = new TaskbarPlacement(taskbar, x, y, width, height, dpi, alignRight, false);
            return TaskbarPlacementStatus.Visible;
        }

        int verticalWidth = Math.Max(1, taskbarRect.Width - ScaleDip(4, dpi));
        int verticalHeight = Math.Min(ScaleDip(42, dpi), Math.Max(1, taskbarRect.Height - ScaleDip(16, dpi)));
        nint verticalTray = FindTaskbarDescendant(taskbar, "TrayNotifyWnd");
        int bottomBoundary = GetWindowRect(verticalTray, out NativeRect verticalTrayRect)
            ? verticalTrayRect.Top
            : taskbarRect.Bottom - ScaleDip(72, dpi);
        int verticalY = Math.Clamp(
            bottomBoundary - verticalHeight - ScaleDip(6, dpi),
            taskbarRect.Top + ScaleDip(4, dpi),
            taskbarRect.Bottom - verticalHeight - ScaleDip(4, dpi));
        placement = new TaskbarPlacement(
            taskbar,
            taskbarRect.Left + ScaleDip(2, dpi),
            verticalY,
            verticalWidth,
            verticalHeight,
            dpi,
            false,
            true);
        return TaskbarPlacementStatus.Visible;
    }

    private static int GetCenteredOverlayLeft(nint taskbar, NativeRect taskbarRect, int overlayWidth, uint dpi)
    {
        int reservedLeft = taskbarRect.Left + ScaleDip(CenteredTaskbarLeftReserveDip, dpi);
        int leftControlsRight = FindLeftTaskbarControlsRight(taskbar, taskbarRect, dpi);
        if (leftControlsRight > taskbarRect.Left)
            reservedLeft = Math.Max(reservedLeft, leftControlsRight + ScaleDip(TaskbarControlGapDip, dpi));

        return Math.Clamp(
            reservedLeft,
            taskbarRect.Left + ScaleDip(4, dpi),
            taskbarRect.Right - overlayWidth - ScaleDip(4, dpi));
    }

    private static int FindLeftTaskbarControlsRight(nint taskbar, NativeRect taskbarRect, uint dpi)
    {
        int rightBoundary = taskbarRect.Left;
        int edgeTolerance = ScaleDip(28, dpi);
        int minimumWidth = ScaleDip(32, dpi);
        int maximumWidth = ScaleDip(280, dpi);
        EnumWindowsProcedure callback = (window, _) =>
        {
            if (!IsWindowVisible(window) || !GetWindowRect(window, out NativeRect rectangle)) return true;

            int clippedLeft = Math.Max(rectangle.Left, taskbarRect.Left);
            int clippedRight = Math.Min(rectangle.Right, taskbarRect.Right);
            int clippedTop = Math.Max(rectangle.Top, taskbarRect.Top);
            int clippedBottom = Math.Min(rectangle.Bottom, taskbarRect.Bottom);
            int width = clippedRight - clippedLeft;
            int height = clippedBottom - clippedTop;
            if (clippedLeft <= taskbarRect.Left + edgeTolerance &&
                width >= minimumWidth && width <= maximumWidth &&
                height >= Math.Max(1, taskbarRect.Height / 2))
            {
                rightBoundary = Math.Max(rightBoundary, clippedRight);
            }

            return true;
        };
        EnumChildWindows(taskbar, callback, 0);
        GC.KeepAlive(callback);
        return rightBoundary;
    }

    private static bool IsTaskbarCentered(nint taskbar, NativeRect taskbarRect)
    {
        try
        {
            using RegistryKey? key = Registry.CurrentUser.OpenSubKey(TaskbarAlignmentPath);
            object? rawAlignment = key?.GetValue("TaskbarAl");
            if (rawAlignment is int alignment) return alignment != 0;
        }
        catch
        {
            // Fall through to the live layout and operating-system defaults.
        }

        if (TryDetectCenteredTaskList(taskbar, taskbarRect, out bool centered)) return centered;

        // Windows 11 defaults to centered buttons and may omit TaskbarAl until the
        // user changes the setting. Windows 10 and earlier default to left alignment.
        return Windows11OrLater;
    }

    private static bool TryDetectCenteredTaskList(nint taskbar, NativeRect taskbarRect, out bool centered)
    {
        centered = false;
        nint taskList = FindTaskbarDescendant(taskbar, "MSTaskListWClass");
        if (taskList == 0 || !GetWindowRect(taskList, out NativeRect taskListRect) || taskListRect.Width <= 0)
            return false;

        int taskbarCenter = taskbarRect.Left + taskbarRect.Width / 2;
        int taskListCenter = taskListRect.Left + taskListRect.Width / 2;
        int centerTolerance = Math.Max(1, taskbarRect.Width / 8);
        if (Math.Abs(taskListCenter - taskbarCenter) <= centerTolerance &&
            taskListRect.Left > taskbarRect.Left + taskbarRect.Width / 8)
        {
            centered = true;
            return true;
        }

        // A task-list host can span most of the taskbar even when its visual
        // buttons are centered, so only treat a clearly centered host as proof.
        return false;
    }

    private static bool DetectWindows11OrLater()
    {
        var version = new OsVersionInfo
        {
            Size = (uint)Marshal.SizeOf<OsVersionInfo>(),
            ServicePack = string.Empty
        };
        return RtlGetVersion(ref version) == 0 &&
               (version.MajorVersion > 10 || version.MajorVersion == 10 && version.BuildNumber >= 22000);
    }

    private static nint FindTaskbarDescendant(nint taskbar, string className)
    {
        nint found = 0;
        EnumWindowsProcedure callback = (window, _) =>
        {
            var buffer = new StringBuilder(128);
            GetClassNameW(window, buffer, buffer.Capacity);
            if (!string.Equals(buffer.ToString(), className, StringComparison.Ordinal)) return true;
            found = window;
            return false;
        };
        EnumChildWindows(taskbar, callback, 0);
        GC.KeepAlive(callback);
        return found;
    }

    private static RgbColor ResolveForegroundColor()
    {
        var highContrast = new HighContrast
        {
            Size = (uint)Marshal.SizeOf<HighContrast>()
        };
        if (SystemParametersInfoW(SpiGetHighContrast, highContrast.Size, ref highContrast, 0) &&
            (highContrast.Flags & HcfHighContrastOn) != 0)
        {
            uint color = GetSysColor(ColorWindowText);
            return new RgbColor((byte)(color & 0xFF), (byte)((color >> 8) & 0xFF), (byte)((color >> 16) & 0xFF));
        }

        try
        {
            using RegistryKey? key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            bool light = key?.GetValue("SystemUsesLightTheme") is int value && value != 0;
            return light ? new RgbColor(30, 30, 30) : new RgbColor(245, 245, 245);
        }
        catch
        {
            return new RgbColor(245, 245, 245);
        }
    }

    private static int ScaleDip(int value, uint dpi) => Math.Max(1, (int)Math.Round(value * dpi / 96.0));

    private static nint WindowProcedure(nint window, uint message, nint wParam, nint lParam)
    {
        return message switch
        {
            WmNcHitTest => HtTransparent,
            WmMouseActivate => MaNoActivate,
            _ => DefWindowProcW(window, message, wParam, lParam)
        };
    }

    private readonly record struct TaskbarPlacement(
        nint TaskbarHandle,
        int X,
        int Y,
        int Width,
        int Height,
        uint Dpi,
        bool AlignRight,
        bool IsVertical);

    private enum TaskbarPlacementStatus
    {
        Unavailable,
        Hidden,
        Visible
    }

    private readonly record struct RgbColor(byte R, byte G, byte B);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate nint WindowProcedureDelegate(nint window, uint message, nint wParam, nint lParam);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private delegate bool EnumWindowsProcedure(nint window, nint parameter);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void WinEventProcedureDelegate(
        nint hook,
        uint eventType,
        nint window,
        int objectId,
        int childId,
        uint eventThread,
        uint eventTime);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClassEx
    {
        public uint cbSize;
        public uint style;
        public nint lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public nint hInstance;
        public nint hIcon;
        public nint hCursor;
        public nint hbrBackground;
        public nint lpszMenuName;

        [MarshalAs(UnmanagedType.LPWStr)]
        public string lpszClassName;

        public nint hIconSm;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        public uint Size;
        public int Width;
        public int Height;
        public ushort Planes;
        public ushort BitCount;
        public uint Compression;
        public uint SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public uint ColorsUsed;
        public uint ColorsImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public BitmapInfoHeader Header;
        public uint Colors;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BlendFunction
    {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public NativePoint(int x, int y)
        {
            X = x;
            Y = y;
        }

        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeSize
    {
        public NativeSize(int width, int height)
        {
            Width = width;
            Height = height;
        }

        public int Width;
        public int Height;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public NativeRect(int left, int top, int right, int bottom)
        {
            Left = left;
            Top = top;
            Right = right;
            Bottom = bottom;
        }

        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
        public readonly int Width => Right - Left;
        public readonly int Height => Bottom - Top;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfo
    {
        public uint Size;
        public NativeRect Monitor;
        public NativeRect WorkArea;
        public uint Flags;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct HighContrast
    {
        public uint Size;
        public uint Flags;
        public nint DefaultScheme;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct OsVersionInfo
    {
        public uint Size;
        public uint MajorVersion;
        public uint MinorVersion;
        public uint BuildNumber;
        public uint PlatformId;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string ServicePack;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern nint GetModuleHandleW(string? moduleName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern ushort RegisterClassExW(ref WindowClassEx windowClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterClassW(string className, nint instance);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern nint CreateWindowExW(
        uint extendedStyle,
        string className,
        string windowName,
        uint style,
        int x,
        int y,
        int width,
        int height,
        nint parent,
        nint menu,
        nint instance,
        nint parameter);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern nint DefWindowProcW(nint window, uint message, nint wParam, nint lParam);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyWindow(nint window);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(nint window, int command);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(nint window, nint insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern nint SetWindowLongPtrW(nint window, int index, nint newLong);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern nint SetWinEventHook(
        uint eventMinimum,
        uint eventMaximum,
        nint eventHookModule,
        WinEventProcedureDelegate eventProcedure,
        uint processId,
        uint threadId,
        uint flags);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWinEvent(nint eventHook);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern nint FindWindowW(string className, string? windowName);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(nint window);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(nint window);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(nint window, out NativeRect rectangle);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumChildWindows(nint parent, EnumWindowsProcedure callback, nint parameter);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int GetClassNameW(nint window, StringBuilder className, int maximumCount);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern nint MonitorFromWindow(nint window, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfoW(nint monitor, ref MonitorInfo monitorInfo);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern uint GetDpiForWindow(nint window);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern nint GetDC(nint window);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern int ReleaseDC(nint window, nint deviceContext);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    private static extern nint CreateCompatibleDC(nint deviceContext);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteDC(nint deviceContext);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    private static extern nint CreateDIBSection(
        nint deviceContext,
        ref BitmapInfo bitmapInfo,
        uint usage,
        out nint bits,
        nint section,
        uint offset);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    private static extern nint SelectObject(nint deviceContext, nint drawingObject);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteObject(nint drawingObject);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PatBlt(nint deviceContext, int x, int y, int width, int height, uint rasterOperation);

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern nint CreateFontW(
        int height,
        int width,
        int escapement,
        int orientation,
        int weight,
        uint italic,
        uint underline,
        uint strikeOut,
        uint charSet,
        uint outputPrecision,
        uint clipPrecision,
        uint quality,
        uint pitchAndFamily,
        string faceName);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    private static extern int SetBkMode(nint deviceContext, int mode);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    private static extern uint SetTextColor(nint deviceContext, uint color);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int DrawTextW(nint deviceContext, string text, int count, ref NativeRect rectangle, uint format);

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTextExtentPoint32W(
        nint deviceContext,
        string text,
        int count,
        out NativeSize size);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UpdateLayeredWindow(
        nint window,
        nint destinationDeviceContext,
        ref NativePoint destinationPoint,
        ref NativeSize size,
        nint sourceDeviceContext,
        ref NativePoint sourcePoint,
        uint colorKey,
        ref BlendFunction blend,
        uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfoW(uint action, uint parameter, ref HighContrast data, uint update);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern uint GetSysColor(int index);

    [DllImport("ntdll.dll", ExactSpelling = true)]
    private static extern int RtlGetVersion(ref OsVersionInfo versionInfo);

}
