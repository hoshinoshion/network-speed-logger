using System.Collections.ObjectModel;
using System.Diagnostics;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace NetworkSpeedLogger;

public sealed partial class MainWindow : Window
{
    private readonly NetworkAdapterService _adapterService = new();
    private readonly DispatcherQueueTimer _sampleTimer;
    private readonly DispatcherQueueTimer _uiTimer;
    private readonly AppWindow _appWindow;
    private readonly ThemeController _themeController;
    private readonly UpdateService _updateService = new();
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private readonly InputMethodSnapshot _startupInputMethod = InputMethodSnapshot.CaptureForeground();
    private AppSettingsData _settings;
    private MonitoringSession? _session;
    private SettingsWindow? _settingsWindow;
    private bool _allowClose;
    private bool _hasCompletedSession;
    private bool _initialFocusSet;
    private UpdateReleaseInfo? _availableUpdate;

    public ObservableCollection<AdapterChoice> AdapterChoices { get; } = [];
    public ObservableCollection<SampleRow> RecentSamples { get; } = [];

    public MainWindow()
    {
        InitializeComponent();
        MainContentGrid.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(RootGrid_PointerPressed), true);
        RootGrid.Loaded += RootGrid_Loaded;

        _settings = AppSettingsStore.Load();
        Localization.ApplyPreference(_settings.Language);

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        try
        {
            SystemBackdrop = new MicaBackdrop { Kind = MicaKind.Base };
        }
        catch
        {
        }

        nint windowHandle = WindowNative.GetWindowHandle(this);
        WindowId windowId = Win32Interop.GetWindowIdFromWindow(windowHandle);
        _appWindow = AppWindow.GetFromWindowId(windowId);
        WindowSizing.ResizeAndCenter(_appWindow, windowId, windowHandle, 1480, 880);
        _appWindow.Closing += AppWindow_Closing;
        WindowIconService.Apply(windowHandle, _appWindow);
        _themeController = new ThemeController(RootGrid, _appWindow, DispatcherQueue, _settings.Theme);

        _sampleTimer = DispatcherQueue.CreateTimer();
        _sampleTimer.IsRepeating = true;
        _sampleTimer.Tick += SampleTimer_Tick;
        _uiTimer = DispatcherQueue.CreateTimer();
        _uiTimer.IsRepeating = true;
        _uiTimer.Interval = TimeSpan.FromMilliseconds(250);
        _uiTimer.Tick += UiTimer_Tick;

        ApplyDefaultsToCurrentSession();
        OutputFolderText.Text = _settings.OutputFolder;
        ApplyLanguage();
        RefreshAdapters(false);
        UpdateOutputFolderState();
    }

    private string T(string chinese, string english) => Localization.T(chinese, english);

    private void RootGrid_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (InputFocusHelper.IsNonInteractivePointerTarget(e.OriginalSource as DependencyObject))
        {
            // ScrollViewer performs its own focus navigation after PointerPressed.
            // Capture before it can alter focus, then restore after routed input.
            InputMethodSnapshot inputMethod = InputMethodSnapshot.CaptureForeground();
            DispatcherQueue.TryEnqueue(() =>
            {
                SettingsButton.Focus(FocusState.Programmatic);
                inputMethod.Restore(WindowNative.GetWindowHandle(this));
            });
        }
    }

    private void RootGrid_Loaded(object sender, RoutedEventArgs e)
    {
        if (_initialFocusSet) return;
        _initialFocusSet = true;
        RootGrid.Loaded -= RootGrid_Loaded;

        // NumberBox starts outside tab navigation in XAML so it cannot become the
        // automatic launch target. Restore normal keyboard navigation only after
        // a neutral control owns focus and the original IME state is restored.
        SettingsButton.Focus(FocusState.Programmatic);
        DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () =>
        {
            SettingsButton.Focus(FocusState.Programmatic);
            DurationNumber.IsTabStop = true;
            IntervalNumber.IsTabStop = true;
            _startupInputMethod.Restore(WindowNative.GetWindowHandle(this));
        });

        _ = CheckForUpdatesAfterLaunchAsync();
    }

    private void ApplyLanguage()
    {
        Title = T("网速记录工具", "Network Speed Logger");
        TitleBarText.Text = T("网速记录工具", "Network Speed Logger");
        CurrentSessionTitle.Text = T("本次记录", "Current session");
        CurrentSessionDescription.Text = T("主窗口中的修改只在本次启动期间有效", "Changes here remain temporary until the app closes");
        DurationLabel.Text = T("运行时长（小时）", "Duration (hours)");
        IntervalLabel.Text = T("采样间隔（秒）", "Sample interval (sec)");
        UnitLabel.Text = T("速度单位", "Speed unit");
        AdapterModeLabel.Text = T("网卡模式", "Adapter mode");
        OutputFolderLabel.Text = T("结果保存位置", "Output folder");
        MainTitleText.Text = T("网络流量监控", "Network traffic monitor");
        MainSubtitleText.Text = T("记录电脑实际发送与接收的流量，包括互联网和局域网流量", "Record actual sent and received traffic, including internet and local-network traffic");
        CurrentDownloadLabel.Text = T("当前下载", "Current download");
        CurrentUploadLabel.Text = T("当前上传", "Current upload");
        ElapsedLabel.Text = T("已运行", "Elapsed");
        ChartTitleText.Text = T("实时速度趋势", "Real-time speed trend");
        ChartSubtitleText.Text = T("最近 60 个采样点，纵轴会自动调整", "Latest 60 samples with automatic scaling");
        DownloadLegendText.Text = T("下载", "Download");
        UploadLegendText.Text = T("上传", "Upload");
        RecentTitleText.Text = T("最近 5 条采样", "Latest 5 samples");
        RecentSubtitleText.Text = T("新记录显示在最上方", "Newest sample appears first");
        SummaryTitleText.Text = T("本次统计", "Session statistics");
        SampleTrafficLabel.Text = T("样本与流量", "Samples & traffic");
        MinimumLabel.Text = T("最小速度", "Minimum");
        MaximumLabel.Text = T("最大速度", "Maximum");
        AverageLabel.Text = T("平均速度", "Average");
        UnitMbItem.Content = T("MB/s（兆字节/秒）", "MB/s (megabytes/sec)");
        UnitMbpsItem.Content = T("Mbps（兆比特/秒）", "Mbps (megabits/sec)");
        AutoModeRadio.Content = T("自动（推荐）", "Auto (recommended)");
        ManualModeRadio.Content = T("手动", "Manual");
        RefreshAdaptersText.Text = T("刷新网卡列表", "Refresh adapters");
        BrowseButtonText.Text = T("更改", "Change");
        OpenFolderButtonText.Text = T("打开", "Open");
        ChooseFolderButton.Content = T("选择文件夹", "Choose folder");
        StartButtonText.Text = T("开始记录", "Start");
        StopButtonText.Text = T("结束记录", "Stop");
        OpenResultsButton.Content = T("打开结果文件夹", "Open results folder");
        ToolTipService.SetToolTip(SettingsButton, T("设置", "Settings"));
        ToolTipService.SetToolTip(DurationNumber, T("输入 0 表示不限时", "Enter 0 for no time limit"));
        RecentTimeHeader.Text = T("时间", "Time");
        RecentAdapterHeader.Text = T("网卡", "Adapter");
        Chart.SetLanguage(Localization.IsChinese);
        ViewUpdateButtonText.Text = T("查看更新", "View update");
        RefreshUpdateInfoBarText();
        UpdateAdapterModeUi();
        UpdateUnitUi(false);
        UpdateOutputFolderState();

        if (_session?.IsRunning == true)
        {
            StatusText.Text = T("正在记录", "Recording");
            SummaryStateText.Text = T("正在采样并实时写入 CSV", "Sampling and writing to CSV");
        }
        else if (_hasCompletedSession && _session is not null)
        {
            StatusText.Text = T("记录已结束", "Finished");
            SummaryStateText.Text = T("记录已结束", "Session complete") + " · " + _session.SampleCount + T(" 个有效样本", " valid samples");
            RemainingText.Text = T("记录已结束", "Finished");
            UpdateStatisticsUi();
        }
        else
        {
            StatusText.Text = T("未运行", "Not running");
            SidebarStatusText.Text = T("准备就绪", "Ready");
            RemainingText.Text = T("尚未开始", "Not started");
            SummaryStateText.Text = T("开始记录后显示统计结果", "Statistics appear after recording starts");
            SampleCountText.Text = T("0 个样本", "0 samples");
            TotalTrafficText.Text = T("下载 0 MB · 上传 0 MB", "Download 0 MB · Upload 0 MB");
            SetEmptyStatistics();
            SessionInfoBar.Message = T(
                "设置参数后点击“开始记录”。CSV 会在每次采样后立即保存，结束时同时生成 Markdown 汇总。",
                "Choose settings and click Start. CSV is flushed after every sample, and a Markdown summary is created when recording ends.");
        }
    }

    private void ApplyDefaultsToCurrentSession()
    {
        DurationNumber.Value = _settings.Defaults.DurationHours;
        IntervalNumber.Value = _settings.Defaults.SampleIntervalSeconds;
        SelectComboByTag(UnitCombo, _settings.Defaults.SpeedUnit);
    }

    private void RefreshAdapters(bool showMessage)
    {
        var selectedIds = new HashSet<string>(
            AdapterChoices.Where(item => item.IsSelected).Select(item => item.Id),
            StringComparer.OrdinalIgnoreCase);
        bool hadChoices = AdapterChoices.Count > 0;
        IReadOnlyList<AdapterChoice> choices = _adapterService.GetChoices(hadChoices ? selectedIds : null);
        AdapterChoices.Clear();
        foreach (AdapterChoice choice in choices) AdapterChoices.Add(choice);
        UpdateAdapterModeUi();

        if (showMessage)
        {
            int connectedPhysical = choices.Count(item => item.IsPhysical && item.IsConnected);
            SidebarStatusText.Text = Localization.IsChinese
                ? $"已刷新：发现 {choices.Count} 个网卡，其中 {connectedPhysical} 个物理网卡已连接"
                : $"Refreshed: {choices.Count} adapters found; {connectedPhysical} physical adapters connected";
        }
    }

    private void UpdateAdapterModeUi()
    {
        bool manual = ManualModeRadio.IsChecked == true;
        AdapterList.IsHitTestVisible = manual && _session?.IsRunning != true;
        AdapterList.Opacity = manual ? 1.0 : 0.82;
        AdapterModeHint.Text = manual
            ? T("勾选一个或多个网卡；选择虚拟网卡可能导致 VPN 流量重复计算。", "Select one or more adapters. Virtual adapters may double-count VPN traffic.")
            : _adapterService.PhysicalDetectionFallback
                ? T("自动合并已连接网卡；当前系统使用兼容筛选规则识别物理网卡。", "Combines connected adapters automatically; compatibility rules identify physical hardware.")
                : T("自动合并所有已连接的物理网卡，并排除虚拟网卡。", "Combines connected physical adapters and excludes virtual adapters.");
    }

    private void UpdateUnitUi(bool resetChart = true)
    {
        string unit = ReadComboTag(UnitCombo, "MB/s");
        DownloadUnitText.Text = unit;
        UploadUnitText.Text = unit;
        RecentDownloadHeader.Text = T("下载 ", "Download ") + unit;
        RecentUploadHeader.Text = T("上传 ", "Upload ") + unit;
        if (resetChart && _session?.IsRunning != true) Chart.Reset(unit);
    }

    private void UpdateOutputFolderState()
    {
        bool available = FolderService.TryValidate(_settings.OutputFolder, out _);
        FolderInfoBar.IsOpen = !available;
        FolderInfoBar.Title = available ? string.Empty : T("需要选择结果保存位置", "Choose an output folder");
        FolderInfoBar.Message = available
            ? string.Empty
            : T("每个采样会立即写入这里，应用会记住这个文件夹。", "Every sample is written here immediately, and the app remembers this folder.");
        OpenFolderButton.IsEnabled = available;
        if (_session?.IsRunning != true) StartButton.IsEnabled = available;
    }

    private async void StartButton_Click(object sender, RoutedEventArgs e)
    {
        if (_session?.IsRunning == true) return;
        double duration = DurationNumber.Value;
        double intervalValue = IntervalNumber.Value;
        if (!AppSettingsStore.IsValidDuration(duration))
        {
            await ShowMessageAsync(T("参数有误", "Invalid setting"), T("运行时长必须是 0 到 8760 之间的数字；输入 0 表示不限时。", "Duration must be from 0 to 8760. Enter 0 for no time limit."));
            DurationNumber.Focus(FocusState.Programmatic);
            return;
        }
        if (double.IsNaN(intervalValue) || intervalValue != Math.Truncate(intervalValue) || !AppSettingsStore.IsValidSampleInterval((int)intervalValue))
        {
            await ShowMessageAsync(T("参数有误", "Invalid setting"), T("采样间隔必须是 1 到 3600 之间的整数秒。", "Sample interval must be an integer from 1 to 3600 seconds."));
            IntervalNumber.Focus(FocusState.Programmatic);
            return;
        }
        if (!FolderService.TryValidate(_settings.OutputFolder, out string? folderError))
        {
            await ShowMessageAsync(T("无法开始", "Unable to start"), T("结果保存位置不可用，请重新选择。", "The output folder is unavailable. Choose another folder.") + "\n\n" + folderError);
            UpdateOutputFolderState();
            return;
        }

        bool manual = ManualModeRadio.IsChecked == true;
        string[] selectedIds = AdapterChoices.Where(item => item.IsSelected).Select(item => item.Id).ToArray();
        if (manual && selectedIds.Length == 0)
        {
            await ShowMessageAsync(T("无法开始", "Unable to start"), T("手动模式下请至少勾选一个网卡。", "Select at least one adapter in manual mode."));
            return;
        }

        var options = new SessionOptions(
            duration,
            (int)intervalValue,
            ReadComboTag(UnitCombo, "MB/s"),
            _settings.OutputFolder,
            manual,
            selectedIds,
            Localization.IsChinese);

        try
        {
            _session?.Dispose();
            _session = new MonitoringSession(_adapterService, options);
            IReadOnlyList<string> activeAdapters = _session.Start();
            ResetSessionUi();
            SetConfigurationEnabled(false);
            StatusDot.Fill = ResolveBrush("SuccessBrush", Colors.SeaGreen);
            SidebarStatusDot.Fill = ResolveBrush("SuccessBrush", Colors.SeaGreen);
            StatusText.Text = T("正在记录", "Recording");
            SummaryStateText.Text = T("正在采样并实时写入 CSV", "Sampling and writing to CSV");
            SidebarStatusText.Text = T("正在记录 · ", "Recording · ") + string.Join(Localization.IsChinese ? "、" : ", ", activeAdapters);
            SessionInfoBar.Severity = InfoBarSeverity.Informational;
            SessionInfoBar.Message = T("正在写入：", "Writing: ") + Path.GetFileName(_session.CsvPath) + T("。每次采样后都会立即保存。", ". Data is flushed after every sample.");
            _sampleTimer.Interval = TimeSpan.FromSeconds(options.SampleIntervalSeconds);
            _sampleTimer.Start();
            _uiTimer.Start();
            UpdateRuntimeUi();
        }
        catch (Exception exception)
        {
            _session?.Dispose();
            _session = null;
            await ShowMessageAsync(T("无法开始", "Unable to start"), exception.Message);
        }
    }

    private async void StopButton_Click(object sender, RoutedEventArgs e) =>
        await StopSessionAsync(T("用户手动停止", "Stopped by user"), true);

    private async void SampleTimer_Tick(DispatcherQueueTimer sender, object args)
    {
        if (_session?.IsRunning != true) return;
        try
        {
            SessionSample? sample = _session.TakeSample();
            if (sample is not null) ApplySample(sample);
        }
        catch (Exception exception)
        {
            await StopSessionAsync(T("发生错误：", "Error: ") + exception.Message, false);
            await ShowMessageAsync(T("记录已停止", "Recording stopped"), T("采样时发生错误，记录已停止。", "A sampling error occurred and recording was stopped.") + "\n\n" + exception.Message);
        }
    }

    private async void UiTimer_Tick(DispatcherQueueTimer sender, object args)
    {
        if (_session?.IsRunning != true) return;
        UpdateRuntimeUi();
        if (_session.TargetSeconds > 0 && _session.ElapsedSeconds >= _session.TargetSeconds)
            await StopSessionAsync(T("达到设定时长", "Duration reached"), true);
    }

    private void ApplySample(SessionSample sample)
    {
        CurrentDownloadText.Text = MonitoringSession.FormatRateValue(sample.DownloadValue);
        CurrentUploadText.Text = MonitoringSession.FormatRateValue(sample.UploadValue);
        SampleCountText.Text = sample.SampleCount + T(" 个样本", " samples");
        TotalTrafficText.Text = T("下载 ", "Download ") + MonitoringSession.FormatBytes(sample.TotalReceivedBytes) +
                                T(" · 上传 ", " · Upload ") + MonitoringSession.FormatBytes(sample.TotalSentBytes);
        RecentSamples.Insert(0, new SampleRow(
            sample.Time.ToString("HH:mm:ss"),
            MonitoringSession.FormatRateValue(sample.DownloadValue),
            MonitoringSession.FormatRateValue(sample.UploadValue),
            sample.AdapterNames));
        while (RecentSamples.Count > 5) RecentSamples.RemoveAt(RecentSamples.Count - 1);
        Chart.Add(sample.DownloadValue, sample.UploadValue);
        UpdateStatisticsUi();
        SummaryStateText.Text = T("最近采样：", "Latest sample: ") + sample.Time.ToString("HH:mm:ss") + " · " + sample.AdapterNames;
        SidebarStatusText.Text = T("正在记录 · 下载 ", "Recording · Download ") + MonitoringSession.FormatRateValue(sample.DownloadValue) + " " + _session!.Unit +
                                 T(" · 上传 ", " · Upload ") + MonitoringSession.FormatRateValue(sample.UploadValue) + " " + _session.Unit;
    }

    private async Task StopSessionAsync(string reason, bool takeFinalSample)
    {
        if (_session?.IsRunning != true) return;
        _sampleTimer.Stop();
        _uiTimer.Stop();

        string? summaryError = null;
        try
        {
            reason = _session.Stop(reason, takeFinalSample);
        }
        catch (Exception exception)
        {
            summaryError = exception.Message;
        }

        _hasCompletedSession = true;
        SetConfigurationEnabled(true);
        RefreshAdapters(false);
        StatusDot.Fill = summaryError is null ? ResolveBrush("DownloadBrush", Colors.DodgerBlue) : new SolidColorBrush(Colors.IndianRed);
        SidebarStatusDot.Fill = StatusDot.Fill;
        StatusText.Text = summaryError is null ? T("记录已结束", "Finished") : T("结束时出错", "Completion error");
        SummaryStateText.Text = reason + " · " + _session.SampleCount + T(" 个有效样本", " valid samples");
        SidebarStatusText.Text = summaryError is null
            ? T("记录已结束，结果文件已经保存", "Session finished; result files were saved")
            : T("CSV 已保存，但 Markdown 汇总生成失败", "CSV was saved, but the Markdown summary failed");
        SessionInfoBar.Severity = summaryError is null ? InfoBarSeverity.Success : InfoBarSeverity.Error;
        SessionInfoBar.Message = summaryError is null
            ? reason + T("。CSV 和 Markdown 汇总已保存到结果文件夹。", ". CSV and Markdown summary saved to the output folder.")
            : reason + T("。CSV 已保存，但汇总失败：", ". CSV was saved, but the summary failed: ") + summaryError;
        OpenResultsButton.Visibility = Visibility.Visible;
        ElapsedText.Text = MonitoringSession.FormatDuration(_session.ElapsedSeconds, Localization.IsChinese);
        RemainingText.Text = T("记录已结束", "Finished");
        UpdateStatisticsUi();
        UpdateOutputFolderState();
        await Task.CompletedTask;
    }

    private void ResetSessionUi()
    {
        _hasCompletedSession = false;
        RecentSamples.Clear();
        Chart.Reset(_session!.Unit);
        CurrentDownloadText.Text = "0.000";
        CurrentUploadText.Text = "0.000";
        DownloadUnitText.Text = _session.Unit;
        UploadUnitText.Text = _session.Unit;
        ElapsedText.Text = "00:00:00";
        RemainingText.Text = _session.TargetSeconds > 0 ? T("正在计算", "Calculating") : T("不限时运行", "No time limit");
        SampleCountText.Text = T("0 个样本", "0 samples");
        TotalTrafficText.Text = T("下载 0 MB · 上传 0 MB", "Download 0 MB · Upload 0 MB");
        SetEmptyStatistics();
        OpenResultsButton.Visibility = Visibility.Collapsed;
    }

    private void UpdateRuntimeUi()
    {
        if (_session is null) return;
        double elapsed = _session.ElapsedSeconds;
        ElapsedText.Text = MonitoringSession.FormatDuration(elapsed, Localization.IsChinese);
        if (_session.TargetSeconds > 0)
        {
            double remaining = Math.Max(0, _session.TargetSeconds - elapsed);
            RemainingText.Text = T("剩余 ", "Remaining ") + MonitoringSession.FormatDuration(remaining, Localization.IsChinese);
        }
        else
        {
            RemainingText.Text = T("不限时运行", "No time limit");
        }
    }

    private void UpdateStatisticsUi()
    {
        if (_session is null || _session.SampleCount <= 0)
        {
            SetEmptyStatistics();
            return;
        }
        SessionStatistics statistics = _session.GetStatistics();
        MinimumSpeedText.Text = T("下载 ", "Download ") + _session.FormatRate(statistics.MinimumDownloadBytesPerSecond) +
                                T(" · 上传 ", " · Upload ") + _session.FormatRate(statistics.MinimumUploadBytesPerSecond);
        MaximumSpeedText.Text = T("下载 ", "Download ") + _session.FormatRate(statistics.MaximumDownloadBytesPerSecond) +
                                T(" · 上传 ", " · Upload ") + _session.FormatRate(statistics.MaximumUploadBytesPerSecond);
        AverageSpeedText.Text = T("下载 ", "Download ") + _session.FormatRate(statistics.AverageDownloadBytesPerSecond) +
                                T(" · 上传 ", " · Upload ") + _session.FormatRate(statistics.AverageUploadBytesPerSecond);
    }

    private void SetEmptyStatistics()
    {
        MinimumSpeedText.Text = T("下载 — · 上传 —", "Download — · Upload —");
        MaximumSpeedText.Text = MinimumSpeedText.Text;
        AverageSpeedText.Text = MinimumSpeedText.Text;
    }

    private void SetConfigurationEnabled(bool enabled)
    {
        DurationNumber.IsEnabled = enabled;
        IntervalNumber.IsEnabled = enabled;
        UnitCombo.IsEnabled = enabled;
        AutoModeRadio.IsEnabled = enabled;
        ManualModeRadio.IsEnabled = enabled;
        RefreshAdaptersButton.IsEnabled = enabled;
        BrowseButton.IsEnabled = enabled;
        ChooseFolderButton.IsEnabled = enabled;
        SettingsButton.IsEnabled = enabled;
        AdapterList.IsHitTestVisible = enabled && ManualModeRadio.IsChecked == true;
        StartButton.IsEnabled = enabled;
        StopButton.IsEnabled = !enabled;
    }

    private async void BrowseButton_Click(object sender, RoutedEventArgs e)
    {
        string? selected = await PickFolderAsync();
        if (selected is null) return;
        if (!FolderService.TryValidate(selected, out string? validationError))
        {
            await ShowMessageAsync(T("文件夹不可用", "Folder unavailable"), validationError ?? string.Empty);
            return;
        }

        AppSettingsData candidate = _settings.Clone();
        candidate.OutputFolder = FolderService.NormalizePath(selected);
        if (!AppSettingsStore.TrySave(candidate, out string? saveError))
        {
            await ShowMessageAsync(T("保存失败", "Save failed"), T("文件夹已经选择，但应用无法记住该位置。", "The folder was selected, but the app could not remember it.") + "\n\n" + saveError);
            return;
        }

        _settings = candidate;
        OutputFolderText.Text = _settings.OutputFolder;
        UpdateOutputFolderState();
    }

    private async Task<string?> PickFolderAsync()
    {
        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
            SettingsIdentifier = "NetworkSpeedLoggerOutputFolder"
        };
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        StorageFolder? folder = await picker.PickSingleFolderAsync();
        return folder?.Path;
    }

    private async void OpenFolderButton_Click(object sender, RoutedEventArgs e) =>
        await OpenFolderAsync(_settings.OutputFolder);

    private async void OpenResultsButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (_session is not null && File.Exists(_session.SummaryPath))
            {
                Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + _session.SummaryPath + "\"") { UseShellExecute = true });
                return;
            }
            await OpenFolderAsync(_settings.OutputFolder);
        }
        catch (Exception exception)
        {
            await ShowMessageAsync(T("打开失败", "Open failed"), exception.Message);
        }
    }

    private async Task OpenFolderAsync(string folder)
    {
        try
        {
            if (!Directory.Exists(folder)) throw new DirectoryNotFoundException(folder);
            Process.Start(new ProcessStartInfo(folder) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            await ShowMessageAsync(T("打开失败", "Open failed"), T("无法打开保存文件夹。", "Unable to open the output folder.") + "\n\n" + exception.Message);
        }
    }

    private void SettingsButton_Click(object sender, RoutedEventArgs e)
    {
        if (_settingsWindow is not null)
        {
            _settingsWindow.Activate();
            return;
        }

        _settingsWindow = new SettingsWindow(_settings.Clone(), WindowNative.GetWindowHandle(this));
        _settingsWindow.SettingsSaved += SettingsWindow_SettingsSaved;
        _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow.Activate();
    }

    private void SettingsWindow_SettingsSaved(object? sender, SettingsSavedEventArgs e)
    {
        _settings = e.Settings.Clone();
        Localization.ApplyPreference(_settings.Language);
        _themeController.ApplyPreference(_settings.Theme);
        OutputFolderText.Text = _settings.OutputFolder;
        if (e.ApplyDefaultsNow && _session?.IsRunning != true) ApplyDefaultsToCurrentSession();
        ApplyLanguage();
        RefreshAdapters(false);
    }

    private async Task CheckForUpdatesAfterLaunchAsync()
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(10), _lifetimeCancellation.Token);
            if (!_settings.AutomaticallyCheckForUpdates) return;

            UpdateCheckResult? result = await _updateService.CheckAsync(
                manual: false,
                _lifetimeCancellation.Token);
            if (result?.Status == UpdateCheckStatus.UpdateAvailable &&
                result.Release is not null &&
                _updateService.ShouldPresentAutomatically(result.Release))
            {
                _availableUpdate = result.Release;
                _updateService.MarkReminded(result.Release);
                RefreshUpdateInfoBarText();
                UpdateInfoBar.IsOpen = true;
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    private void RefreshUpdateInfoBarText()
    {
        if (_availableUpdate is null) return;
        UpdateInfoBar.Title = T(
            $"发现新版本 {_availableUpdate.Version}",
            $"Version {_availableUpdate.Version} is available");
        UpdateInfoBar.Message = T(
            $"当前版本为 {UpdateService.CurrentVersionText}。可前往 GitHub 查看更新内容并下载安装程序。",
            $"You are using {UpdateService.CurrentVersionText}. View the release on GitHub and download the installer.");
    }

    private void OpenUpdateReleaseButton_Click(object sender, RoutedEventArgs e)
    {
        if (_availableUpdate is null) return;
        try
        {
            _updateService.MarkReminded(_availableUpdate);
            Process.Start(new ProcessStartInfo(_availableUpdate.ReleasePage.AbsoluteUri)
            {
                UseShellExecute = true
            });
        }
        catch
        {
        }
    }

    private void RefreshAdaptersButton_Click(object sender, RoutedEventArgs e) => RefreshAdapters(true);

    private void AdapterMode_Changed(object sender, RoutedEventArgs e)
    {
        if (AdapterList is not null) UpdateAdapterModeUi();
    }

    private void UnitCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (DownloadUnitText is not null) UpdateUnitUi();
    }

    private async void AppWindow_Closing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_allowClose || _session?.IsRunning != true)
        {
            _lifetimeCancellation.Cancel();
            _themeController.Dispose();
            _session?.Dispose();
            return;
        }

        args.Cancel = true;
        bool confirmed = await ShowConfirmationAsync(
            T("确认退出", "Confirm exit"),
            T("当前仍在记录网速。是否结束记录并退出？", "Recording is still in progress. Stop and exit?"),
            T("结束并退出", "Stop and exit"));
        if (!confirmed) return;
        await StopSessionAsync(T("关闭程序", "Application closed"), true);
        _allowClose = true;
        _lifetimeCancellation.Cancel();
        Close();
    }

    private async Task ShowMessageAsync(string title, string message)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Title = title,
            Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
            CloseButtonText = T("确定", "OK")
        };
        await dialog.ShowAsync();
    }

    private async Task<bool> ShowConfirmationAsync(string title, string message, string primaryText)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = RootGrid.XamlRoot,
            Title = title,
            Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = primaryText,
            CloseButtonText = T("取消", "Cancel"),
            DefaultButton = ContentDialogButton.Close
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    private static void SelectComboByTag(ComboBox comboBox, string tag)
    {
        foreach (object entry in comboBox.Items)
        {
            if (entry is ComboBoxItem item && string.Equals(Convert.ToString(item.Tag), tag, StringComparison.OrdinalIgnoreCase))
            {
                comboBox.SelectedItem = item;
                return;
            }
        }
        comboBox.SelectedIndex = 0;
    }

    private static string ReadComboTag(ComboBox comboBox, string fallback) =>
        comboBox.SelectedItem is ComboBoxItem item && item.Tag is not null ? item.Tag.ToString()! : fallback;

    private static Brush ResolveBrush(string key, Windows.UI.Color fallback)
    {
        if (Application.Current.Resources.TryGetValue(key, out object value) && value is Brush brush) return brush;
        return new SolidColorBrush(fallback);
    }
}
