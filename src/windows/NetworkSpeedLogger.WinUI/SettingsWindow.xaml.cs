using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
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

public sealed class SettingsSavedEventArgs : EventArgs
{
    public SettingsSavedEventArgs(AppSettingsData settings)
    {
        Settings = settings;
    }

    public AppSettingsData Settings { get; }
}

public sealed partial class SettingsWindow : Window
{
    private readonly AppWindow _appWindow;
    private readonly nint _ownerHandle;
    private readonly NetworkAdapterService _taskbarAdapterService = new();
    private readonly ThemeController _themeController;
    private readonly UpdateService _updateService = new();
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private AppSettingsData _settings;
    private bool _initialFocusSet;
    private bool _isClosed;
    private UpdateReleaseInfo? _availableUpdate;

    public ObservableCollection<AdapterChoice> TaskbarAdapterChoices { get; } = [];

    public event EventHandler<SettingsSavedEventArgs>? SettingsSaved;

    public void HideWithOwner() => _appWindow.Hide();

    public void ShowWithOwner() => _appWindow.Show(true);

    public SettingsWindow(AppSettingsData settings, nint ownerHandle)
    {
        InitializeComponent();
        RootGrid.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(RootGrid_PointerPressed), true);
        RootGrid.Loaded += RootGrid_Loaded;
        _settings = settings;
        _ownerHandle = ownerHandle;

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(SettingsTitleBar);
        try
        {
            SystemBackdrop = new MicaBackdrop { Kind = MicaKind.BaseAlt };
        }
        catch
        {
        }

        nint windowHandle = WindowNative.GetWindowHandle(this);
        WindowId windowId = Win32Interop.GetWindowIdFromWindow(windowHandle);
        _appWindow = AppWindow.GetFromWindowId(windowId);
        WindowSizing.ResizeAndCenter(_appWindow, windowId, windowHandle, 900, 760);
        WindowIconService.Apply(windowHandle, _appWindow);
        try
        {
            if (_ownerHandle != 0) NativeMethods.SetOwner(windowHandle, _ownerHandle);
        }
        catch
        {
        }

        _themeController = new ThemeController(RootGrid, _appWindow, DispatcherQueue, _settings.Theme);
        Closed += (_, _) =>
        {
            _isClosed = true;
            _lifetimeCancellation.Cancel();
            _themeController.Dispose();
        };
        LoadSettings();
        ApplyLanguage();
        ShowSettingsPage("General");
    }

    private string T(string chinese, string english) => Localization.T(chinese, english);

    private void RootGrid_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (InputFocusHelper.ShouldClearFocus(RootGrid.XamlRoot, e.OriginalSource as DependencyObject))
            CancelButton.Focus(FocusState.Programmatic);
    }

    private void RootGrid_Loaded(object sender, RoutedEventArgs e)
    {
        if (_initialFocusSet) return;
        _initialFocusSet = true;
        RootGrid.Loaded -= RootGrid_Loaded;

        // Keep startup focus away from NumberBox so opening this window does not
        // ask the text input framework to select a numeric/English input mode.
        DispatcherQueue.TryEnqueue(() => CancelButton.Focus(FocusState.Programmatic));
    }

    private void LoadSettings()
    {
        SelectComboByTag(LanguageCombo, _settings.Language);
        SelectComboByTag(ThemeCombo, _settings.Theme);
        DefaultDurationNumber.Value = _settings.Defaults.DurationHours;
        DefaultIntervalNumber.Value = _settings.Defaults.SampleIntervalSeconds;
        SelectComboByTag(DefaultUnitCombo, _settings.Defaults.SpeedUnit);
        TaskbarIntervalNumber.Value = _settings.TaskbarSpeed.SampleIntervalSeconds;
        SelectComboByTag(TaskbarUnitCombo, _settings.TaskbarSpeed.SpeedUnit);
        SelectComboByTag(TaskbarLayoutCombo, _settings.TaskbarSpeed.SingleLine ? "SingleLine" : "TwoLine");
        TaskbarAutoModeRadio.IsChecked = !_settings.TaskbarSpeed.ManualMode;
        TaskbarManualModeRadio.IsChecked = _settings.TaskbarSpeed.ManualMode;
        RefreshTaskbarAdapters(false);
        TaskbarEnabledToggle.IsOn = _settings.TaskbarSpeed.Enabled;
        UpdateTaskbarOptionsUi();
        OutputFolderText.Text = _settings.OutputFolder;
        OpenFolderButton.IsEnabled = Directory.Exists(_settings.OutputFolder);
        AutomaticUpdatesToggle.IsOn = _settings.AutomaticallyCheckForUpdates;
        MinimizeToTrayToggle.IsOn = _settings.MinimizeToTray;
        LaunchAtLoginToggle.IsOn = _settings.LaunchAtLogin;
        string version = UpdateService.CurrentVersionText;
        VersionText.Text = T("版本 ", "Version ") + version + " · WinUI 3";
        UpdateStatusText.Text = version + " · WinUI 3";
    }

    private void ApplyLanguage()
    {
        Title = T("设置", "Settings");
        TitleBarText.Text = T("设置", "Settings");
        PageTitleText.Text = T("设置", "Settings");
        PageSubtitleText.Text = T("按类别管理应用行为、记录配置、系统栏显示与更新", "Manage app behavior, recording, system-bar display, and updates by category");
        GeneralNavigationItem.Content = T("通用", "General");
        RecordingNavigationItem.Content = T("记录", "Recording");
        TaskbarNavigationItem.Content = T("任务栏", "Taskbar");
        UpdatesNavigationItem.Content = T("更新", "Updates");
        GeneralSectionText.Text = T("常规", "General");
        LanguageLabel.Text = T("界面语言", "App language");
        LanguageDescription.Text = T("默认根据 Windows 显示语言自动选择", "By default, follows the Windows display language");
        LanguageAutoItem.Content = T("跟随系统", "Follow system");
        ThemeLabel.Text = T("应用外观", "App appearance");
        ThemeDescription.Text = T("默认跟随 Windows 浅色或深色模式", "By default, follows the Windows light or dark mode");
        ThemeAutoItem.Content = T("跟随系统", "Follow system");
        ThemeLightItem.Content = T("浅色", "Light");
        ThemeDarkItem.Content = T("深色", "Dark");
        MinimizeToTrayLabel.Text = T("最小化到托盘", "Minimize to notification area");
        MinimizeToTrayDescription.Text = T(
            "开启后，点击关闭按钮会让应用继续在后台运行",
            "When enabled, the Close button keeps the app running in the background");
        LaunchAtLoginLabel.Text = T("开机运行", "Run at sign-in");
        LaunchAtLoginDescription.Text = T(
            "登录 Windows 后自动启动并直接在托盘运行",
            "Start automatically after Windows sign-in and go directly to the notification area");
        TaskbarSectionText.Text = T("任务栏网速", "Taskbar speed");
        TaskbarSectionDescription.Text = T(
            "在主任务栏上持续显示独立采样的实时下载和上传速度",
            "Continuously show independently sampled download and upload speeds on the primary taskbar");
        TaskbarEnabledLabel.Text = T("显示任务栏网速", "Show taskbar speed");
        TaskbarEnabledDescription.Text = T(
            "应用运行期间显示；内容不会响应点击",
            "Shown while the app is running; the display does not respond to clicks");
        TaskbarLayoutLabel.Text = T("显示布局", "Display layout");
        TaskbarLayoutDescription.Text = T(
            "选择上传和下载的排列方式",
            "Choose how upload and download speeds are arranged");
        TaskbarLayoutTwoLineItem.Content = T("双行（上传在上）", "Two lines (upload on top)");
        TaskbarLayoutSingleLineItem.Content = T("单行（上传在左）", "Single line (upload on left)");
        TaskbarIntervalLabel.Text = T("采样频率", "Sample interval");
        TaskbarIntervalDescription.Text = T("1 到 3600 秒；默认为 1 秒", "1 to 3600 seconds; default is 1 second");
        TaskbarUnitLabel.Text = T("速度单位", "Speed unit");
        TaskbarUnitDescription.Text = T(
            "K、M、G 等前缀会根据实时速度自动变化",
            "K, M, and G prefixes change automatically with the current speed");
        TaskbarUnitByteItem.Content = T("Byte（B/s、KB/s、MB/s）", "Byte (B/s, KB/s, MB/s)");
        TaskbarUnitBitItem.Content = T("bit（bps、Kbps、Mbps）", "bit (bps, Kbps, Mbps)");
        TaskbarAdapterModeLabel.Text = T("网卡模式", "Adapter mode");
        TaskbarAdapterModeDescription.Text = T("与网速记录功能分开设置", "Configured separately from traffic logging");
        TaskbarAutoModeRadio.Content = T("自动（推荐）", "Auto (recommended)");
        TaskbarManualModeRadio.Content = T("手动", "Manual");
        TaskbarRefreshAdaptersText.Text = T("刷新网卡列表", "Refresh adapters");
        DefaultsSectionText.Text = T("启动默认值", "Launch defaults");
        DefaultsDescriptionText.Text = T("主窗口中的临时修改不会覆盖这些值", "Temporary changes in the main window do not overwrite these values");
        DefaultDurationLabel.Text = T("运行时长", "Duration");
        DefaultDurationDescription.Text = T("小时；0 表示不限时", "Hours; 0 means no time limit");
        DefaultIntervalLabel.Text = T("采样间隔", "Sample interval");
        DefaultIntervalDescription.Text = T("1 到 3600 秒", "1 to 3600 seconds");
        DefaultUnitLabel.Text = T("速度单位", "Speed unit");
        DefaultUnitDescription.Text = T("只影响显示和输出列单位", "Controls display and output column units");
        DefaultUnitMbItem.Content = T("MB/s（兆字节/秒）", "MB/s (megabytes/sec)");
        DefaultUnitMbpsItem.Content = T("Mbps（兆比特/秒）", "Mbps (megabits/sec)");
        FilesSectionText.Text = T("文件", "Files");
        OutputFolderLabel.Text = T("结果保存位置", "Output folder");
        OutputFolderDescription.Text = T("CSV 和 Markdown 汇总都会保存到此文件夹", "CSV logs and Markdown summaries are saved here");
        OpenFolderButtonText.Text = T("打开", "Open");
        BrowseButtonText.Text = T("更改", "Change");
        UpdatesSectionText.Text = T("更新", "Updates");
        AutomaticUpdatesLabel.Text = T("自动检查更新", "Automatically check for updates");
        AutomaticUpdatesDescription.Text = T(
            "应用启动后每天最多检查一次正式版",
            "Checks for a stable release at most once a day after launch");
        CurrentVersionLabel.Text = T("当前版本", "Current version");
        CheckUpdateButtonText.Text = T("检查更新", "Check for updates");
        ViewUpdateButtonText.Text = T("查看更新", "View update");
        AboutSectionText.Text = T("关于", "About");
        RepositoryButtonText.Text = T("GitHub 仓库", "GitHub repository");
        SaveHintText.Text = T("保存后立即应用可用设置", "Available settings are applied immediately after saving");
        CancelButton.Content = T("取消", "Cancel");
        SaveButton.Content = T("保存", "Save");
        UpdateTaskbarOptionsUi();
    }

    private void SettingsNavigation_SelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args)
    {
        if (GeneralSettingsPage is null) return;
        string page = Convert.ToString((args.SelectedItemContainer as NavigationViewItem)?.Tag) ?? "General";
        ShowSettingsPage(page);
    }

    private void ShowSettingsPage(string page)
    {
        GeneralSettingsPage.Visibility = page == "General" ? Visibility.Visible : Visibility.Collapsed;
        RecordingSettingsPage.Visibility = page == "Recording" ? Visibility.Visible : Visibility.Collapsed;
        TaskbarSettingsPage.Visibility = page == "Taskbar" ? Visibility.Visible : Visibility.Collapsed;
        UpdatesSettingsPage.Visibility = page == "Updates" ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SelectSettingsPage(NavigationViewItem item)
    {
        SettingsNavigation.SelectedItem = item;
        ShowSettingsPage(Convert.ToString(item.Tag) ?? "General");
    }

    private void TaskbarEnabledToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (TaskbarOptionsPanel is not null) UpdateTaskbarOptionsUi();
    }

    private void TaskbarAdapterMode_Changed(object sender, RoutedEventArgs e)
    {
        if (TaskbarAdapterList is not null) UpdateTaskbarOptionsUi();
    }

    private void TaskbarRefreshAdaptersButton_Click(object sender, RoutedEventArgs e) =>
        RefreshTaskbarAdapters(true);

    private void RefreshTaskbarAdapters(bool preserveCurrentSelection)
    {
        var selectedIds = new HashSet<string>(
            preserveCurrentSelection
                ? TaskbarAdapterChoices.Where(item => item.IsSelected).Select(item => item.Id)
                : _settings.TaskbarSpeed.SelectedAdapterIds,
            StringComparer.OrdinalIgnoreCase);
        IReadOnlySet<string>? previousSelection = selectedIds.Count > 0 ? selectedIds : null;
        IReadOnlyList<AdapterChoice> choices = _taskbarAdapterService.GetChoices(previousSelection);
        TaskbarAdapterChoices.Clear();
        foreach (AdapterChoice choice in choices) TaskbarAdapterChoices.Add(choice);
        UpdateTaskbarOptionsUi();
    }

    private void UpdateTaskbarOptionsUi()
    {
        if (TaskbarOptionsPanel is null || TaskbarAdapterList is null) return;
        bool enabled = TaskbarEnabledToggle.IsOn;
        bool manual = TaskbarManualModeRadio.IsChecked == true;
        TaskbarOptionsPanel.IsHitTestVisible = enabled;
        TaskbarOptionsPanel.Opacity = enabled ? 1.0 : 0.56;
        TaskbarAdapterList.IsHitTestVisible = enabled && manual;
        TaskbarAdapterList.Opacity = manual ? 1.0 : 0.72;
        TaskbarAdapterModeHint.Text = manual
            ? T(
                "勾选一个或多个网卡；选择虚拟网卡可能导致 VPN 流量重复计算。",
                "Select one or more adapters. Virtual adapters may double-count VPN traffic.")
            : _taskbarAdapterService.PhysicalDetectionFallback
                ? T(
                    "自动合并已连接网卡；当前系统使用兼容筛选规则识别物理网卡。",
                    "Combines connected adapters automatically; compatibility rules identify physical hardware.")
                : T(
                    "自动合并所有已连接的物理网卡，并排除虚拟网卡。",
                    "Combines all connected physical adapters and excludes virtual adapters.");
    }

    private async void BrowseButton_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
            SettingsIdentifier = "NetworkSpeedLoggerSettingsOutputFolder"
        };
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        StorageFolder? folder = await picker.PickSingleFolderAsync();
        if (folder is null) return;
        if (!FolderService.TryValidate(folder.Path, out string? error))
        {
            ShowValidation(T("文件夹不可用", "Folder unavailable"), error ?? string.Empty);
            return;
        }
        OutputFolderText.Text = FolderService.NormalizePath(folder.Path);
        OpenFolderButton.IsEnabled = true;
        ValidationInfoBar.IsOpen = false;
    }

    private void OpenFolderButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (!Directory.Exists(OutputFolderText.Text)) throw new DirectoryNotFoundException(OutputFolderText.Text);
            Process.Start(new ProcessStartInfo(OutputFolderText.Text) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            ShowValidation(T("打开失败", "Open failed"), exception.Message);
        }
    }

    private void RepositoryButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo("https://github.com/hoshinoshion/network-speed-logger") { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            ShowValidation(T("打开失败", "Open failed"), exception.Message);
        }
    }

    private async void CheckUpdateButton_Click(object sender, RoutedEventArgs e)
    {
        CheckUpdateButton.IsEnabled = false;
        UpdateProgressRing.IsActive = true;
        UpdateProgressRing.Visibility = Visibility.Visible;
        UpdateResultInfoBar.IsOpen = false;
        UpdateStatusText.Text = T("正在检查…", "Checking…");

        try
        {
            UpdateCheckResult? result = await _updateService.CheckAsync(
                manual: true,
                _lifetimeCancellation.Token);
            if (result is null) return;

            switch (result.Status)
            {
                case UpdateCheckStatus.UpToDate:
                    _availableUpdate = null;
                    ViewUpdateButton.Visibility = Visibility.Collapsed;
                    UpdateResultInfoBar.Severity = InfoBarSeverity.Success;
                    UpdateResultInfoBar.Title = T("当前已是最新正式版", "You’re up to date");
                    UpdateResultInfoBar.Message = T(
                        $"当前版本为 {UpdateService.CurrentVersionText}。",
                        $"You are using version {UpdateService.CurrentVersionText}.");
                    UpdateResultInfoBar.IsOpen = true;
                    break;

                case UpdateCheckStatus.UpdateAvailable when result.Release is not null:
                    _availableUpdate = result.Release;
                    _updateService.MarkReminded(result.Release);
                    ViewUpdateButton.Visibility = Visibility.Visible;
                    UpdateResultInfoBar.Severity = InfoBarSeverity.Informational;
                    UpdateResultInfoBar.Title = T(
                        $"发现新版本 {result.Release.Version}",
                        $"Version {result.Release.Version} is available");
                    UpdateResultInfoBar.Message = T(
                        "可前往 GitHub 查看更新内容并下载安装程序。",
                        "View the release on GitHub and download the installer.");
                    UpdateResultInfoBar.IsOpen = true;
                    break;

                default:
                    _availableUpdate = null;
                    ViewUpdateButton.Visibility = Visibility.Collapsed;
                    UpdateResultInfoBar.Severity = InfoBarSeverity.Error;
                    UpdateResultInfoBar.Title = T("无法检查更新", "Unable to check for updates");
                    UpdateResultInfoBar.Message = T("请稍后重试。", "Try again later.");
                    UpdateResultInfoBar.IsOpen = true;
                    break;
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            if (!_isClosed)
            {
                UpdateStatusText.Text = UpdateService.CurrentVersionText + " · WinUI 3";
                UpdateProgressRing.IsActive = false;
                UpdateProgressRing.Visibility = Visibility.Collapsed;
                CheckUpdateButton.IsEnabled = true;
            }
        }
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
        catch (Exception exception)
        {
            ShowValidation(T("打开失败", "Open failed"), exception.Message);
        }
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e) => Close();

    private void ThemeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _themeController?.ApplyPreference(ReadComboTag(ThemeCombo, "Auto"));
    }

    private void LaunchAtLoginToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (LaunchAtLoginToggle.IsOn)
            MinimizeToTrayToggle.IsOn = true;
    }

    private void SaveButton_Click(object sender, RoutedEventArgs e) => Save();

    private void Save()
    {
        double duration = DefaultDurationNumber.Value;
        double intervalValue = DefaultIntervalNumber.Value;
        double taskbarIntervalValue = TaskbarIntervalNumber.Value;
        if (!AppSettingsStore.IsValidDuration(duration))
        {
            ShowValidation(T("参数有误", "Invalid setting"), T("运行时长必须是 0 到 8760 之间的数字。", "Duration must be from 0 to 8760."), RecordingNavigationItem);
            DefaultDurationNumber.Focus(FocusState.Programmatic);
            return;
        }
        if (double.IsNaN(intervalValue) || intervalValue != Math.Truncate(intervalValue) || !AppSettingsStore.IsValidSampleInterval((int)intervalValue))
        {
            ShowValidation(T("参数有误", "Invalid setting"), T("采样间隔必须是 1 到 3600 之间的整数秒。", "Sample interval must be an integer from 1 to 3600 seconds."), RecordingNavigationItem);
            DefaultIntervalNumber.Focus(FocusState.Programmatic);
            return;
        }
        if (double.IsNaN(taskbarIntervalValue) ||
            taskbarIntervalValue != Math.Truncate(taskbarIntervalValue) ||
            !AppSettingsStore.IsValidSampleInterval((int)taskbarIntervalValue))
        {
            ShowValidation(
                T("参数有误", "Invalid setting"),
                T("任务栏网速的采样频率必须是 1 到 3600 之间的整数秒。", "The taskbar sample interval must be an integer from 1 to 3600 seconds."),
                TaskbarNavigationItem);
            TaskbarIntervalNumber.Focus(FocusState.Programmatic);
            return;
        }
        string[] taskbarSelectedAdapterIds = TaskbarAdapterChoices
            .Where(item => item.IsSelected)
            .Select(item => item.Id)
            .ToArray();
        if (TaskbarEnabledToggle.IsOn && TaskbarManualModeRadio.IsChecked == true && taskbarSelectedAdapterIds.Length == 0)
        {
            ShowValidation(
                T("无法开启任务栏网速", "Unable to enable taskbar speed"),
                T("手动模式下请至少勾选一个网卡。", "Select at least one adapter in manual mode."),
                TaskbarNavigationItem);
            return;
        }
        if (!FolderService.TryValidate(OutputFolderText.Text, out string? folderError))
        {
            ShowValidation(T("文件夹不可用", "Folder unavailable"), folderError ?? string.Empty, RecordingNavigationItem);
            return;
        }

        AppSettingsData candidate = _settings.Clone();
        candidate.Language = ReadComboTag(LanguageCombo, "Auto");
        candidate.Theme = ReadComboTag(ThemeCombo, "Auto");
        candidate.OutputFolder = FolderService.NormalizePath(OutputFolderText.Text);
        candidate.AutomaticallyCheckForUpdates = AutomaticUpdatesToggle.IsOn;
        candidate.LaunchAtLogin = LaunchAtLoginToggle.IsOn;
        candidate.MinimizeToTray = MinimizeToTrayToggle.IsOn || candidate.LaunchAtLogin;
        candidate.TaskbarSpeed.Enabled = TaskbarEnabledToggle.IsOn;
        candidate.TaskbarSpeed.SampleIntervalSeconds = (int)taskbarIntervalValue;
        candidate.TaskbarSpeed.SpeedUnit = ReadComboTag(TaskbarUnitCombo, "Byte");
        candidate.TaskbarSpeed.SingleLine = ReadComboTag(TaskbarLayoutCombo, "TwoLine") == "SingleLine";
        candidate.TaskbarSpeed.ManualMode = TaskbarManualModeRadio.IsChecked == true;
        candidate.TaskbarSpeed.SelectedAdapterIds = taskbarSelectedAdapterIds;
        candidate.Defaults.DurationHours = duration;
        candidate.Defaults.SampleIntervalSeconds = (int)intervalValue;
        candidate.Defaults.SpeedUnit = ReadComboTag(DefaultUnitCombo, "MB/s");
        if (!LaunchAtLoginService.TrySetEnabled(candidate.LaunchAtLogin, out string? launchError))
        {
            ShowValidation(
                T("无法更改开机运行", "Unable to change sign-in launch"),
                launchError ?? string.Empty,
                GeneralNavigationItem);
            return;
        }
        if (!AppSettingsStore.TrySave(candidate, out string? saveError))
        {
            _ = LaunchAtLoginService.TrySetEnabled(_settings.LaunchAtLogin, out _);
            ShowValidation(T("保存失败", "Save failed"), saveError ?? string.Empty);
            return;
        }

        _settings = candidate;
        SettingsSaved?.Invoke(this, new SettingsSavedEventArgs(candidate.Clone()));
        Close();
    }

    private void ShowValidation(string title, string message, NavigationViewItem? page = null)
    {
        if (page is not null) SelectSettingsPage(page);
        ValidationInfoBar.Title = title;
        ValidationInfoBar.Message = message;
        ValidationInfoBar.IsOpen = true;
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

    private static class NativeMethods
    {
        private const int GwlpHwndParent = -8;

        [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
        private static extern nint SetWindowLongPtr64(nint hWnd, int index, nint newLong);

        [DllImport("user32.dll", EntryPoint = "SetWindowLongW")]
        private static extern int SetWindowLong32(nint hWnd, int index, int newLong);

        public static void SetOwner(nint windowHandle, nint ownerHandle)
        {
            if (nint.Size == 8) SetWindowLongPtr64(windowHandle, GwlpHwndParent, ownerHandle);
            else SetWindowLong32(windowHandle, GwlpHwndParent, ownerHandle.ToInt32());
        }
    }
}
