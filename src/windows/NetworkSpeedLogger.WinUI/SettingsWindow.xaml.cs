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
    public SettingsSavedEventArgs(AppSettingsData settings, bool applyDefaultsNow)
    {
        Settings = settings;
        ApplyDefaultsNow = applyDefaultsNow;
    }

    public AppSettingsData Settings { get; }
    public bool ApplyDefaultsNow { get; }
}

public sealed partial class SettingsWindow : Window
{
    private readonly AppWindow _appWindow;
    private readonly nint _ownerHandle;
    private readonly ThemeController _themeController;
    private readonly UpdateService _updateService = new();
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private AppSettingsData _settings;
    private bool _initialFocusSet;
    private bool _isClosed;
    private UpdateReleaseInfo? _availableUpdate;

    public event EventHandler<SettingsSavedEventArgs>? SettingsSaved;

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
        OutputFolderText.Text = _settings.OutputFolder;
        OpenFolderButton.IsEnabled = Directory.Exists(_settings.OutputFolder);
        AutomaticUpdatesToggle.IsOn = _settings.AutomaticallyCheckForUpdates;
        string version = UpdateService.CurrentVersionText;
        VersionText.Text = T("版本 ", "Version ") + version + " · WinUI 3";
        UpdateStatusText.Text = version + " · WinUI 3";
    }

    private void ApplyLanguage()
    {
        Title = T("设置", "Settings");
        TitleBarText.Text = T("设置", "Settings");
        PageTitleText.Text = T("设置", "Settings");
        PageSubtitleText.Text = T("管理每次启动时使用的默认值和文件保存位置", "Manage launch defaults and file locations");
        GeneralSectionText.Text = T("常规", "General");
        LanguageLabel.Text = T("界面语言", "App language");
        LanguageDescription.Text = T("默认根据 Windows 显示语言自动选择", "By default, follows the Windows display language");
        LanguageAutoItem.Content = T("跟随系统", "Follow system");
        ThemeLabel.Text = T("应用外观", "App appearance");
        ThemeDescription.Text = T("默认跟随 Windows 浅色或深色模式", "By default, follows the Windows light or dark mode");
        ThemeAutoItem.Content = T("跟随系统", "Follow system");
        ThemeLightItem.Content = T("浅色", "Light");
        ThemeDarkItem.Content = T("深色", "Dark");
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
        SaveHintText.Text = T("保存后将在下次启动时使用", "Saved values are used at the next launch");
        CancelButton.Content = T("取消", "Cancel");
        SaveButton.Content = T("保存", "Save");
        ApplyDefaultsButton.Content = T("保存并立即应用", "Save and apply now");
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

    private void SaveButton_Click(object sender, RoutedEventArgs e) => Save(false);

    private void ApplyDefaultsButton_Click(object sender, RoutedEventArgs e) => Save(true);

    private void Save(bool applyDefaultsNow)
    {
        double duration = DefaultDurationNumber.Value;
        double intervalValue = DefaultIntervalNumber.Value;
        if (!AppSettingsStore.IsValidDuration(duration))
        {
            ShowValidation(T("参数有误", "Invalid setting"), T("运行时长必须是 0 到 8760 之间的数字。", "Duration must be from 0 to 8760."));
            DefaultDurationNumber.Focus(FocusState.Programmatic);
            return;
        }
        if (double.IsNaN(intervalValue) || intervalValue != Math.Truncate(intervalValue) || !AppSettingsStore.IsValidSampleInterval((int)intervalValue))
        {
            ShowValidation(T("参数有误", "Invalid setting"), T("采样间隔必须是 1 到 3600 之间的整数秒。", "Sample interval must be an integer from 1 to 3600 seconds."));
            DefaultIntervalNumber.Focus(FocusState.Programmatic);
            return;
        }
        if (!FolderService.TryValidate(OutputFolderText.Text, out string? folderError))
        {
            ShowValidation(T("文件夹不可用", "Folder unavailable"), folderError ?? string.Empty);
            return;
        }

        AppSettingsData candidate = _settings.Clone();
        candidate.Language = ReadComboTag(LanguageCombo, "Auto");
        candidate.Theme = ReadComboTag(ThemeCombo, "Auto");
        candidate.OutputFolder = FolderService.NormalizePath(OutputFolderText.Text);
        candidate.AutomaticallyCheckForUpdates = AutomaticUpdatesToggle.IsOn;
        candidate.Defaults.DurationHours = duration;
        candidate.Defaults.SampleIntervalSeconds = (int)intervalValue;
        candidate.Defaults.SpeedUnit = ReadComboTag(DefaultUnitCombo, "MB/s");
        if (!AppSettingsStore.TrySave(candidate, out string? saveError))
        {
            ShowValidation(T("保存失败", "Save failed"), saveError ?? string.Empty);
            return;
        }

        _settings = candidate;
        SettingsSaved?.Invoke(this, new SettingsSavedEventArgs(candidate.Clone(), applyDefaultsNow));
        Close();
    }

    private void ShowValidation(string title, string message)
    {
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
