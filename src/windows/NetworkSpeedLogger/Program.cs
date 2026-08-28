using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Management;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Threading;
using System.Xml;
using Forms = System.Windows.Forms;
using Ellipse = System.Windows.Shapes.Ellipse;

[assembly: AssemblyTitle("Network Speed Logger")]
[assembly: AssemblyDescription("Bilingual Windows network speed logger / 双语 Windows 网速记录工具")]
[assembly: AssemblyProduct("Network Speed Logger")]
[assembly: AssemblyCompany("")]
[assembly: AssemblyCopyright("Copyright © 2026 hoshinoshion")]
[assembly: AssemblyVersion("0.1.0.0")]
[assembly: AssemblyFileVersion("0.1.0.0")]

namespace NetworkSpeedLogger
{
    internal sealed class AdapterChoice : INotifyPropertyChanged
    {
        private bool _isSelected;

        internal AdapterChoice(string id, string name, string detail, bool isPhysical, bool isSelected)
        {
            Id = id;
            Name = name;
            Detail = detail;
            IsPhysical = isPhysical;
            _isSelected = isSelected;
        }

        public string Id { get; private set; }
        public string Name { get; private set; }
        public string Detail { get; private set; }
        public bool IsPhysical { get; private set; }

        public bool IsSelected
        {
            get { return _isSelected; }
            set
            {
                if (_isSelected == value) return;
                _isSelected = value;
                if (PropertyChanged != null) PropertyChanged(this, new PropertyChangedEventArgs("IsSelected"));
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;
    }

    internal sealed class SampleRow
    {
        internal SampleRow(string time, string download, string upload, string adapters)
        {
            Time = time;
            Download = download;
            Upload = upload;
            Adapters = adapters;
        }

        public string Time { get; private set; }
        public string Download { get; private set; }
        public string Upload { get; private set; }
        public string Adapters { get; private set; }
    }

    internal sealed class CounterSnapshot
    {
        internal CounterSnapshot(NetworkInterface adapter, long received, long sent)
        {
            Adapter = adapter;
            Received = received;
            Sent = sent;
        }

        internal NetworkInterface Adapter;
        internal long Received;
        internal long Sent;
    }

    internal sealed class SpeedPoint
    {
        internal SpeedPoint(double download, double upload)
        {
            Download = download;
            Upload = upload;
        }

        internal double Download;
        internal double Upload;
    }

    internal sealed class SpeedChart : FrameworkElement
    {
        private readonly List<SpeedPoint> _points = new List<SpeedPoint>();
        private string _unit = "MB/s";
        private bool _isChinese = true;
        private readonly Pen _downloadPen = new Pen(new SolidColorBrush(Color.FromRgb(0x4F, 0x7C, 0xFF)), 2.4);
        private readonly Pen _uploadPen = new Pen(new SolidColorBrush(Color.FromRgb(0x20, 0xB4, 0x86)), 2.0);
        private readonly Brush _gridBrush = new SolidColorBrush(Color.FromRgb(0xE6, 0xEC, 0xF4));
        private readonly Brush _labelBrush = new SolidColorBrush(Color.FromRgb(0x8A, 0x97, 0xA9));

        internal SpeedChart()
        {
            _downloadPen.Freeze();
            _uploadPen.Freeze();
        }

        internal void Reset(string unit)
        {
            _unit = unit;
            _points.Clear();
            InvalidateVisual();
        }

        internal void SetLanguage(bool isChinese)
        {
            _isChinese = isChinese;
            InvalidateVisual();
        }

        internal void Add(double download, double upload)
        {
            _points.Add(new SpeedPoint(download, upload));
            while (_points.Count > 60) _points.RemoveAt(0);
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext drawingContext)
        {
            base.OnRender(drawingContext);

            double width = ActualWidth;
            double height = ActualHeight;
            if (width < 120 || height < 80) return;

            const double left = 54;
            const double right = 16;
            const double top = 15;
            const double bottom = 27;
            double plotWidth = width - left - right;
            double plotHeight = height - top - bottom;
            var gridPen = new Pen(_gridBrush, 1);

            double maximum = 0;
            foreach (var point in _points)
            {
                maximum = Math.Max(maximum, Math.Max(point.Download, point.Upload));
            }
            double minimumScale = _unit == "Mbps" ? 0.1 : 0.01;
            maximum = Math.Max(minimumScale, maximum * 1.15);

            for (int index = 0; index <= 4; index++)
            {
                double ratio = index / 4.0;
                double y = top + plotHeight * ratio;
                drawingContext.DrawLine(gridPen, new Point(left, y), new Point(width - right, y));
                double value = maximum * (1.0 - ratio);
                DrawLabel(drawingContext, FormatAxis(value), 4, y - 8);
            }

            DrawLabel(drawingContext, _unit, 5, height - 20);

            if (_points.Count == 0)
            {
                var emptyText = new FormattedText(
                    _isChinese ? "等待第一个采样点…" : "Waiting for the first sample…",
                    CultureInfo.CurrentUICulture,
                    FlowDirection.LeftToRight,
                    new Typeface("Microsoft YaHei UI"),
                    12,
                    _labelBrush,
                    VisualTreeHelper.GetDpi(this).PixelsPerDip);
                drawingContext.DrawText(emptyText, new Point(left + (plotWidth - emptyText.Width) / 2, top + (plotHeight - emptyText.Height) / 2));
                return;
            }

            DrawSeries(drawingContext, true, left, top, plotWidth, plotHeight, maximum, _downloadPen);
            DrawSeries(drawingContext, false, left, top, plotWidth, plotHeight, maximum, _uploadPen);
        }

        private void DrawSeries(DrawingContext drawingContext, bool download, double left, double top, double width, double height, double maximum, Pen pen)
        {
            var geometry = new StreamGeometry();
            using (var context = geometry.Open())
            {
                for (int index = 0; index < _points.Count; index++)
                {
                    double x = _points.Count == 1 ? left + width : left + width * index / (_points.Count - 1.0);
                    double value = download ? _points[index].Download : _points[index].Upload;
                    double y = top + height - (value / maximum * height);
                    if (index == 0) context.BeginFigure(new Point(x, y), false, false);
                    else context.LineTo(new Point(x, y), true, false);
                }
            }
            geometry.Freeze();
            drawingContext.DrawGeometry(null, pen, geometry);

            var last = _points[_points.Count - 1];
            double lastValue = download ? last.Download : last.Upload;
            double lastY = top + height - (lastValue / maximum * height);
            drawingContext.DrawEllipse(pen.Brush, null, new Point(left + width, lastY), 3.4, 3.4);
        }

        private void DrawLabel(DrawingContext drawingContext, string text, double x, double y)
        {
            var formatted = new FormattedText(
                text,
                CultureInfo.CurrentUICulture,
                FlowDirection.LeftToRight,
                new Typeface("Segoe UI"),
                10,
                _labelBrush,
                VisualTreeHelper.GetDpi(this).PixelsPerDip);
            drawingContext.DrawText(formatted, new Point(x, y));
        }

        private static string FormatAxis(double value)
        {
            if (value >= 100) return value.ToString("0", CultureInfo.InvariantCulture);
            if (value >= 10) return value.ToString("0.0", CultureInfo.InvariantCulture);
            if (value >= 1) return value.ToString("0.00", CultureInfo.InvariantCulture);
            return value.ToString("0.000", CultureInfo.InvariantCulture);
        }
    }

    internal sealed class MonitorController
    {
        private readonly Window _window;
        private readonly TextBox _durationText;
        private readonly TextBox _intervalText;
        private readonly ComboBox _languageCombo;
        private readonly ComboBox _unitCombo;
        private readonly RadioButton _autoModeRadio;
        private readonly RadioButton _manualModeRadio;
        private readonly TextBlock _adapterModeHint;
        private readonly ListBox _adapterList;
        private readonly Button _refreshAdaptersButton;
        private readonly TextBox _outputFolderText;
        private readonly Button _browseButton;
        private readonly Button _startButton;
        private readonly Button _stopButton;
        private readonly StackPanel _configInputs;
        private readonly TextBlock _sidebarStatusText;
        private readonly Ellipse _statusDot;
        private readonly TextBlock _statusText;
        private readonly TextBlock _currentDownloadText;
        private readonly TextBlock _currentUploadText;
        private readonly TextBlock _downloadUnitText;
        private readonly TextBlock _uploadUnitText;
        private readonly TextBlock _elapsedText;
        private readonly TextBlock _remainingText;
        private readonly TextBlock _sampleCountText;
        private readonly TextBlock _totalTrafficText;
        private readonly ProgressBar _runProgress;
        private readonly DataGrid _recentGrid;
        private readonly TextBlock _summaryStateText;
        private readonly TextBlock _minSpeedText;
        private readonly TextBlock _maxSpeedText;
        private readonly TextBlock _avgSpeedText;
        private readonly Button _openResultsButton;
        private readonly Border _sessionMessageBorder;
        private readonly TextBlock _sessionMessageText;
        private readonly SpeedChart _chart;

        private readonly ObservableCollection<AdapterChoice> _adapterChoices = new ObservableCollection<AdapterChoice>();
        private readonly ObservableCollection<SampleRow> _recentSamples = new ObservableCollection<SampleRow>();
        private HashSet<string> _physicalAdapterIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private Dictionary<string, CounterSnapshot> _previousSnapshot = new Dictionary<string, CounterSnapshot>(StringComparer.OrdinalIgnoreCase);
        private readonly HashSet<string> _observedAdapterNames = new HashSet<string>(StringComparer.CurrentCultureIgnoreCase);
        private readonly DispatcherTimer _sampleTimer = new DispatcherTimer(DispatcherPriority.Background);
        private readonly DispatcherTimer _uiTimer = new DispatcherTimer(DispatcherPriority.Background);
        private readonly Stopwatch _stopwatch = new Stopwatch();

        private bool _isRunning;
        private bool _hasCompletedSession;
        private bool _updatingLanguage;
        private bool _isChinese;
        private string _languagePreference = "Auto";
        private bool _physicalDetectionFallback;
        private bool _manualMode;
        private double _durationHours;
        private double _targetSeconds;
        private int _sampleIntervalSeconds;
        private string _unit = "MB/s";
        private DateTime _startTime;
        private double _lastSampleElapsed;
        private double _lastPhysicalRefreshElapsed;
        private long _sampleCount;
        private double _totalReceivedBytes;
        private double _totalSentBytes;
        private double _totalMeasuredSeconds;
        private double _minDownloadBytesPerSecond = double.PositiveInfinity;
        private double _maxDownloadBytesPerSecond;
        private double _minUploadBytesPerSecond = double.PositiveInfinity;
        private double _maxUploadBytesPerSecond;
        private StreamWriter _csvWriter;
        private string _csvPath;
        private string _summaryPath;

        internal MonitorController(Window window)
        {
            _window = window;
            _durationText = Find<TextBox>("DurationText");
            _intervalText = Find<TextBox>("IntervalText");
            _languageCombo = Find<ComboBox>("LanguageCombo");
            _unitCombo = Find<ComboBox>("UnitCombo");
            _autoModeRadio = Find<RadioButton>("AutoModeRadio");
            _manualModeRadio = Find<RadioButton>("ManualModeRadio");
            _adapterModeHint = Find<TextBlock>("AdapterModeHint");
            _adapterList = Find<ListBox>("AdapterList");
            _refreshAdaptersButton = Find<Button>("RefreshAdaptersButton");
            _outputFolderText = Find<TextBox>("OutputFolderText");
            _browseButton = Find<Button>("BrowseButton");
            _startButton = Find<Button>("StartButton");
            _stopButton = Find<Button>("StopButton");
            _configInputs = Find<StackPanel>("ConfigInputs");
            _sidebarStatusText = Find<TextBlock>("SidebarStatusText");
            _statusDot = Find<Ellipse>("StatusDot");
            _statusText = Find<TextBlock>("StatusText");
            _currentDownloadText = Find<TextBlock>("CurrentDownloadText");
            _currentUploadText = Find<TextBlock>("CurrentUploadText");
            _downloadUnitText = Find<TextBlock>("DownloadUnitText");
            _uploadUnitText = Find<TextBlock>("UploadUnitText");
            _elapsedText = Find<TextBlock>("ElapsedText");
            _remainingText = Find<TextBlock>("RemainingText");
            _sampleCountText = Find<TextBlock>("SampleCountText");
            _totalTrafficText = Find<TextBlock>("TotalTrafficText");
            _runProgress = Find<ProgressBar>("RunProgress");
            _recentGrid = Find<DataGrid>("RecentGrid");
            _summaryStateText = Find<TextBlock>("SummaryStateText");
            _minSpeedText = Find<TextBlock>("MinSpeedText");
            _maxSpeedText = Find<TextBlock>("MaxSpeedText");
            _avgSpeedText = Find<TextBlock>("AvgSpeedText");
            _openResultsButton = Find<Button>("OpenResultsButton");
            _sessionMessageBorder = Find<Border>("SessionMessageBorder");
            _sessionMessageText = Find<TextBlock>("SessionMessageText");

            var chartHost = Find<ContentControl>("ChartHost");
            _chart = new SpeedChart();
            chartHost.Content = _chart;
            _adapterList.ItemsSource = _adapterChoices;
            _recentGrid.ItemsSource = _recentSamples;
            _outputFolderText.Text = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);

            _languagePreference = LoadLanguagePreference();
            _isChinese = ResolveIsChinese(_languagePreference);
            SelectLanguagePreference(_languagePreference);

            _autoModeRadio.Checked += delegate { UpdateAdapterModeUi(); };
            _manualModeRadio.Checked += delegate { UpdateAdapterModeUi(); };
            _languageCombo.SelectionChanged += LanguageSelectionChanged;
            _unitCombo.SelectionChanged += delegate { UpdateUnitUi(); };
            _refreshAdaptersButton.Click += delegate { RefreshAdapters(true); };
            _browseButton.Click += BrowseButtonClick;
            _startButton.Click += StartButtonClick;
            _stopButton.Click += delegate { StopMonitoring(Tr("用户手动停止", "Stopped by user"), true, false); };
            _openResultsButton.Click += OpenResultsButtonClick;
            _window.Closing += WindowClosing;

            _sampleTimer.Tick += SampleTimerTick;
            _uiTimer.Interval = TimeSpan.FromMilliseconds(250);
            _uiTimer.Tick += UiTimerTick;

            ApplyLanguage();
            RefreshAdapters(false);
        }

        private T Find<T>(string name) where T : FrameworkElement
        {
            var value = _window.FindName(name) as T;
            if (value == null) throw new InvalidOperationException("Missing UI control: " + name);
            return value;
        }

        private string Tr(string chinese, string english)
        {
            return _isChinese ? chinese : english;
        }

        private void SetText(string name, string chinese, string english)
        {
            Find<TextBlock>(name).Text = Tr(chinese, english);
        }

        private void SelectLanguagePreference(string preference)
        {
            _updatingLanguage = true;
            try
            {
                foreach (ComboBoxItem item in _languageCombo.Items)
                {
                    if (string.Equals(Convert.ToString(item.Tag, CultureInfo.InvariantCulture), preference, StringComparison.OrdinalIgnoreCase))
                    {
                        _languageCombo.SelectedItem = item;
                        return;
                    }
                }
                _languageCombo.SelectedIndex = 0;
            }
            finally
            {
                _updatingLanguage = false;
            }
        }

        private void LanguageSelectionChanged(object sender, SelectionChangedEventArgs eventArgs)
        {
            if (_updatingLanguage) return;
            var item = _languageCombo.SelectedItem as ComboBoxItem;
            if (item == null || item.Tag == null) return;

            _languagePreference = item.Tag.ToString();
            _isChinese = ResolveIsChinese(_languagePreference);
            SaveLanguagePreference(_languagePreference);
            ApplyLanguage();
            if (!_isRunning) RefreshAdapters(false);
        }

        private void ApplyLanguage()
        {
            _window.Title = Tr("网速记录工具", "Network Speed Logger");
            SetText("AppTitleText", "网速记录工具", "Network Speed Logger");
            SetText("SettingsTitleText", "记录设置", "Settings");
            SetText("LanguageLabel", "界面语言", "Language");
            SetText("DurationLabel", "运行时长（小时）", "Duration (hours)");
            SetText("IntervalLabel", "采样间隔（秒）", "Sample interval (sec)");
            SetText("UnitLabel", "速度单位", "Speed unit");
            SetText("AdapterModeLabel", "网卡模式", "Adapter mode");
            SetText("OutputFolderLabel", "结果保存位置", "Output folder");
            SetText("MainTitleText", "网络流量监控", "Network traffic monitor");
            SetText("MainSubtitleText", "记录电脑物理网卡的实时上传与下载速度", "Track real-time download and upload speed on physical adapters");
            SetText("CurrentDownloadLabel", "当前下载", "Current download");
            SetText("CurrentUploadLabel", "当前上传", "Current upload");
            SetText("ElapsedLabel", "已运行", "Elapsed");
            SetText("SampleTrafficLabel", "样本与流量", "Samples & traffic");
            SetText("ChartTitleText", "实时速度趋势", "Real-time speed trend");
            SetText("ChartSubtitleText", "最近 60 个采样点，纵轴会自动调整", "Latest 60 samples with automatic scaling");
            SetText("DownloadLegendText", "下载", "Download");
            SetText("UploadLegendText", "上传", "Upload");
            SetText("RecentTitleText", "最近 5 条采样", "Latest 5 samples");
            SetText("RecentSubtitleText", "新记录显示在最上方", "Newest sample appears first");
            SetText("SummaryTitleText", "本次统计", "Session statistics");
            SetText("MinLabelText", "最小速度", "Minimum");
            SetText("MaxLabelText", "最大速度", "Maximum");
            SetText("AvgLabelText", "平均速度", "Average");

            Find<ComboBoxItem>("AutoLanguageItem").Content = Tr("自动（跟随系统）", "Auto (system language)");
            Find<ComboBoxItem>("ChineseLanguageItem").Content = Tr("简体中文", "Simplified Chinese");
            Find<ComboBoxItem>("EnglishLanguageItem").Content = "English";
            Find<ComboBoxItem>("UnitMbItem").Content = Tr("MB/s（兆字节/秒）", "MB/s (megabytes/sec)");
            Find<ComboBoxItem>("UnitMbpsItem").Content = Tr("Mbps（兆比特/秒）", "Mbps (megabits/sec)");
            _autoModeRadio.Content = Tr("自动（推荐）", "Auto (recommended)");
            _manualModeRadio.Content = Tr("手动", "Manual");
            _refreshAdaptersButton.Content = Tr("刷新网卡列表", "Refresh adapters");
            _browseButton.Content = Tr("选择", "Browse");
            _startButton.Content = Tr("开始记录", "Start");
            _stopButton.Content = Tr("结束记录", "Stop");
            _openResultsButton.Content = Tr("打开结果文件夹", "Open results folder");
            _durationText.ToolTip = Tr("输入 0 表示不限时", "Enter 0 for no time limit");

            _recentGrid.Columns[0].Header = Tr("时间", "Time");
            if (_recentGrid.Columns.Count >= 4) _recentGrid.Columns[3].Header = Tr("网卡", "Adapter");
            _chart.SetLanguage(_isChinese);
            UpdateAdapterModeUi();
            UpdateUnitUi(false);

            if (_isRunning)
            {
                _statusText.Text = Tr("正在记录", "Recording");
                _summaryStateText.Text = Tr("正在采样并实时写入 CSV", "Sampling and writing to CSV");
            }
            else if (_hasCompletedSession)
            {
                _statusText.Text = Tr("记录已结束", "Finished");
                _summaryStateText.Text = Tr("记录已结束", "Session complete") + " · " + _sampleCount + Tr(" 个有效样本", " valid samples");
                _sidebarStatusText.Text = Tr("记录已结束，结果文件已经保存", "Session finished; result files were saved");
                _remainingText.Text = Tr("记录已结束", "Finished");
                _sessionMessageText.Text = Tr("结果已保存。CSV：", "Results saved. CSV: ") + _csvPath + Tr("　汇总：", "  Summary: ") + _summaryPath;
                UpdateStatisticsUi();
            }
            else
            {
                _statusText.Text = Tr("未运行", "Not running");
                _sidebarStatusText.Text = Tr("准备就绪", "Ready");
                _remainingText.Text = Tr("尚未开始", "Not started");
                _summaryStateText.Text = Tr("开始记录后显示统计结果", "Statistics appear after recording starts");
                _sampleCountText.Text = Tr("0 个样本", "0 samples");
                _totalTrafficText.Text = Tr("下载 0 MB · 上传 0 MB", "Download 0 MB · Upload 0 MB");
                _minSpeedText.Text = Tr("下载 —  ·  上传 —", "Download —  ·  Upload —");
                _maxSpeedText.Text = _minSpeedText.Text;
                _avgSpeedText.Text = _minSpeedText.Text;
                _sessionMessageText.Text = Tr(
                    "设置参数后点击“开始记录”。CSV 会在每次采样后立即保存，结束时同时生成 Markdown 汇总。",
                    "Choose your settings and click Start. CSV is flushed after each sample, and a Markdown summary is created when recording ends.");
            }
        }

        private static bool ResolveIsChinese(string preference)
        {
            if (string.Equals(preference, "zh-CN", StringComparison.OrdinalIgnoreCase)) return true;
            if (string.Equals(preference, "en-US", StringComparison.OrdinalIgnoreCase)) return false;
            return string.Equals(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName, "zh", StringComparison.OrdinalIgnoreCase);
        }

        private static string LanguageSettingsPath
        {
            get
            {
                return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NetworkSpeedLogger", "language.txt");
            }
        }

        private static string LoadLanguagePreference()
        {
            try
            {
                string value = File.ReadAllText(LanguageSettingsPath, Encoding.UTF8).Trim();
                if (value == "Auto" || value == "zh-CN" || value == "en-US") return value;
            }
            catch
            {
            }
            return "Auto";
        }

        private static void SaveLanguagePreference(string preference)
        {
            try
            {
                string folder = Path.GetDirectoryName(LanguageSettingsPath);
                if (!Directory.Exists(folder)) Directory.CreateDirectory(folder);
                File.WriteAllText(LanguageSettingsPath, preference, new UTF8Encoding(false));
            }
            catch
            {
            }
        }

        private void UpdateAdapterModeUi()
        {
            bool manual = _manualModeRadio.IsChecked == true;
            // 自动模式下仅禁止点击，不使用 WPF 的禁用态，以免文字被系统主题淡化。
            _adapterList.IsEnabled = true;
            _adapterList.IsHitTestVisible = manual && !_isRunning;
            _adapterList.Opacity = manual ? 1.0 : 0.90;
            if (manual)
            {
                _adapterModeHint.Text = Tr(
                    "勾选一个或多个网卡；选择虚拟网卡可能导致 VPN 流量重复计算。",
                    "Select one or more adapters. Virtual adapters may double-count VPN traffic.");
            }
            else
            {
                _adapterModeHint.Text = _physicalDetectionFallback
                    ? Tr("自动合并已连接网卡；当前系统使用兼容筛选规则识别物理网卡。", "Combines connected adapters automatically; compatibility rules are being used to identify physical hardware.")
                    : Tr("自动合并所有已连接的物理网卡，并排除虚拟网卡。", "Combines all connected physical adapters and excludes virtual adapters.");
            }
        }

        private void UpdateUnitUi(bool resetChart = true)
        {
            string unit = ReadSelectedUnit();
            _downloadUnitText.Text = unit;
            _uploadUnitText.Text = unit;
            if (_recentGrid.Columns.Count >= 3)
            {
                _recentGrid.Columns[1].Header = Tr("下载 ", "Download ") + unit;
                _recentGrid.Columns[2].Header = Tr("上传 ", "Upload ") + unit;
            }
            if (resetChart && !_isRunning) _chart.Reset(unit);
        }

        private string ReadSelectedUnit()
        {
            var item = _unitCombo.SelectedItem as ComboBoxItem;
            if (item != null && item.Tag != null) return item.Tag.ToString();
            return "MB/s";
        }

        private void RefreshAdapters(bool showMessage)
        {
            var selectedIds = new HashSet<string>(
                _adapterChoices.Where(item => item.IsSelected).Select(item => item.Id),
                StringComparer.OrdinalIgnoreCase);
            bool hadChoices = _adapterChoices.Count > 0;

            _physicalAdapterIds = DetectPhysicalAdapters(out _physicalDetectionFallback);
            var adapters = NetworkInterface.GetAllNetworkInterfaces()
                .Where(item => item.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                               item.NetworkInterfaceType != NetworkInterfaceType.Tunnel)
                .OrderByDescending(item => item.OperationalStatus == OperationalStatus.Up)
                .ThenBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToArray();

            _adapterChoices.Clear();
            foreach (var adapter in adapters)
            {
                string id = NormalizeId(adapter.Id);
                bool physical = _physicalAdapterIds.Contains(id);
                bool selected = hadChoices ? selectedIds.Contains(id) : physical && adapter.OperationalStatus == OperationalStatus.Up;
                string state = adapter.OperationalStatus == OperationalStatus.Up ? Tr("已连接", "Connected") : Tr("未连接", "Disconnected");
                string kind = physical ? Tr("物理网卡", "Physical") : Tr("虚拟/其他", "Virtual/other");
                string description = string.IsNullOrWhiteSpace(adapter.Description) ? adapter.NetworkInterfaceType.ToString() : adapter.Description;
                _adapterChoices.Add(new AdapterChoice(id, adapter.Name, state + " · " + kind + " · " + description, physical, selected));
            }

            UpdateAdapterModeUi();
            if (showMessage)
            {
                int connectedPhysical = adapters.Count(item => item.OperationalStatus == OperationalStatus.Up && _physicalAdapterIds.Contains(NormalizeId(item.Id)));
                _sidebarStatusText.Text = _isChinese
                    ? "已刷新：发现 " + adapters.Length + " 个网卡，其中 " + connectedPhysical + " 个物理网卡已连接"
                    : "Refreshed: " + adapters.Length + " adapters found; " + connectedPhysical + " physical adapters connected";
            }
        }

        private static HashSet<string> DetectPhysicalAdapters(out bool fallback)
        {
            var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            fallback = false;
            try
            {
                using (var searcher = new ManagementObjectSearcher("SELECT GUID, PhysicalAdapter FROM Win32_NetworkAdapter WHERE PhysicalAdapter = TRUE"))
                using (var objects = searcher.Get())
                {
                    foreach (ManagementObject item in objects)
                    {
                        string guid = item["GUID"] as string;
                        if (!string.IsNullOrWhiteSpace(guid)) result.Add(NormalizeId(guid));
                    }
                }
            }
            catch
            {
                fallback = true;
            }

            if (result.Count > 0) return result;

            fallback = true;
            foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (IsLikelyPhysical(adapter)) result.Add(NormalizeId(adapter.Id));
            }
            return result;
        }

        private static bool IsLikelyPhysical(NetworkInterface adapter)
        {
            string text = (adapter.Name + " " + adapter.Description).ToLowerInvariant();
            string[] virtualWords = { "virtual", "vmware", "hyper-v", "vethernet", "vpn", " tap", "tun", "wsl", "docker", "loopback" };
            if (virtualWords.Any(text.Contains)) return false;

            switch (adapter.NetworkInterfaceType)
            {
                case NetworkInterfaceType.Ethernet:
                case NetworkInterfaceType.Ethernet3Megabit:
                case NetworkInterfaceType.FastEthernetFx:
                case NetworkInterfaceType.FastEthernetT:
                case NetworkInterfaceType.GigabitEthernet:
                case NetworkInterfaceType.Wireless80211:
                case NetworkInterfaceType.Wman:
                case NetworkInterfaceType.Wwanpp:
                case NetworkInterfaceType.Wwanpp2:
                    return true;
                default:
                    return false;
            }
        }

        private void BrowseButtonClick(object sender, RoutedEventArgs eventArgs)
        {
            using (var dialog = new Forms.FolderBrowserDialog())
            {
                dialog.Description = Tr("选择 CSV 和 Markdown 汇总的保存位置", "Choose where CSV logs and Markdown summaries are saved");
                dialog.ShowNewFolderButton = true;
                if (Directory.Exists(_outputFolderText.Text)) dialog.SelectedPath = _outputFolderText.Text;
                if (dialog.ShowDialog() == Forms.DialogResult.OK) _outputFolderText.Text = dialog.SelectedPath;
            }
        }

        private void StartButtonClick(object sender, RoutedEventArgs eventArgs)
        {
            if (_isRunning) return;

            double duration;
            int interval;
            if (!TryReadDouble(_durationText.Text, out duration) || duration < 0 || duration > 8760)
            {
                ShowValidation(Tr("运行时长必须是 0 到 8760 之间的数字；输入 0 表示不限时。", "Duration must be a number from 0 to 8760. Enter 0 for no time limit."), _durationText);
                return;
            }
            if (!int.TryParse(_intervalText.Text.Trim(), NumberStyles.Integer, CultureInfo.CurrentCulture, out interval) || interval < 1 || interval > 3600)
            {
                ShowValidation(Tr("采样间隔必须是 1 到 3600 之间的整数秒。", "Sample interval must be an integer from 1 to 3600 seconds."), _intervalText);
                return;
            }
            if (!Directory.Exists(_outputFolderText.Text))
            {
                MessageBox.Show(_window, Tr("结果保存位置不存在，请重新选择。", "The output folder does not exist. Please choose another folder."), Tr("无法开始", "Unable to start"), MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            RefreshAdapters(false);
            bool manual = _manualModeRadio.IsChecked == true;
            if (manual && !_adapterChoices.Any(item => item.IsSelected))
            {
                MessageBox.Show(_window, Tr("手动模式下请至少勾选一个网卡。", "Select at least one adapter in manual mode."), Tr("无法开始", "Unable to start"), MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            var activeAdapters = ResolveActiveAdapters(manual);
            if (activeAdapters.Count == 0)
            {
                MessageBox.Show(_window,
                    manual ? Tr("勾选的网卡目前均未连接。", "None of the selected adapters is connected.") : Tr("没有检测到已连接的物理网卡。", "No connected physical adapter was detected."),
                    Tr("无法开始", "Unable to start"), MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            var baseline = SnapshotAdapters(activeAdapters);
            if (baseline.Count == 0)
            {
                MessageBox.Show(_window, Tr("无法读取所选网卡的流量计数器。", "Unable to read traffic counters for the selected adapters."), Tr("无法开始", "Unable to start"), MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }

            try
            {
                _durationHours = duration;
                _targetSeconds = duration * 3600.0;
                _sampleIntervalSeconds = interval;
                _manualMode = manual;
                _unit = ReadSelectedUnit();
                _previousSnapshot = baseline;
                _startTime = DateTime.Now;
                CreateOutputPaths(_outputFolderText.Text, _startTime, out _csvPath, out _summaryPath);
                _csvWriter = new StreamWriter(_csvPath, false, new UTF8Encoding(true));
                string columnUnit = _unit == "Mbps" ? "Mbps" : "MBps";
                _csvWriter.WriteLine("Timestamp,ElapsedSeconds,Download_" + columnUnit + ",Upload_" + columnUnit + ",ActiveAdapters");
                _csvWriter.Flush();

                ResetSessionUi();
                foreach (var adapter in activeAdapters) _observedAdapterNames.Add(adapter.Name);
                _isRunning = true;
                _hasCompletedSession = false;
                _configInputs.IsEnabled = false;
                _startButton.IsEnabled = false;
                _stopButton.IsEnabled = true;
                _statusDot.Fill = new SolidColorBrush(Color.FromRgb(0x20, 0xB4, 0x86));
                _statusText.Text = Tr("正在记录", "Recording");
                _statusText.Foreground = new SolidColorBrush(Color.FromRgb(0x17, 0x78, 0x5C));
                _summaryStateText.Text = Tr("正在采样并实时写入 CSV", "Sampling and writing to CSV");
                _sidebarStatusText.Text = Tr("正在记录 · ", "Recording · ") + string.Join(_isChinese ? "、" : ", ", activeAdapters.Select(item => item.Name));
                _sessionMessageBorder.Background = new SolidColorBrush(Color.FromRgb(0xEA, 0xF0, 0xFF));
                _sessionMessageText.Text = Tr("正在写入：", "Writing: ") + Path.GetFileName(_csvPath) + Tr("。每次采样后都会立即保存。", ". Data is flushed after every sample.");
                _runProgress.IsIndeterminate = _targetSeconds <= 0;

                _lastSampleElapsed = 0;
                _lastPhysicalRefreshElapsed = 0;
                _stopwatch.Restart();
                _sampleTimer.Interval = TimeSpan.FromSeconds(_sampleIntervalSeconds);
                _sampleTimer.Start();
                _uiTimer.Start();
                UpdateRuntimeUi();
            }
            catch (Exception exception)
            {
                if (_csvWriter != null)
                {
                    _csvWriter.Dispose();
                    _csvWriter = null;
                }
                MessageBox.Show(_window, Tr("无法创建记录文件。\n\n", "Unable to create the log file.\n\n") + exception.Message, Tr("无法开始", "Unable to start"), MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void ResetSessionUi()
        {
            _sampleCount = 0;
            _totalReceivedBytes = 0;
            _totalSentBytes = 0;
            _totalMeasuredSeconds = 0;
            _minDownloadBytesPerSecond = double.PositiveInfinity;
            _maxDownloadBytesPerSecond = 0;
            _minUploadBytesPerSecond = double.PositiveInfinity;
            _maxUploadBytesPerSecond = 0;
            _observedAdapterNames.Clear();
            _recentSamples.Clear();
            _chart.Reset(_unit);
            _currentDownloadText.Text = "0.000";
            _currentUploadText.Text = "0.000";
            _downloadUnitText.Text = _unit;
            _uploadUnitText.Text = _unit;
            _elapsedText.Text = "00:00:00";
            _sampleCountText.Text = Tr("0 个样本", "0 samples");
            _totalTrafficText.Text = Tr("下载 0 MB · 上传 0 MB", "Download 0 MB · Upload 0 MB");
            _minSpeedText.Text = Tr("下载 —  ·  上传 —", "Download —  ·  Upload —");
            _maxSpeedText.Text = _minSpeedText.Text;
            _avgSpeedText.Text = _minSpeedText.Text;
            _openResultsButton.Visibility = Visibility.Collapsed;
            _runProgress.Value = 0;
            if (_recentGrid.Columns.Count >= 3)
            {
                _recentGrid.Columns[1].Header = Tr("下载 ", "Download ") + _unit;
                _recentGrid.Columns[2].Header = Tr("上传 ", "Upload ") + _unit;
            }
        }

        private void SampleTimerTick(object sender, EventArgs eventArgs)
        {
            if (!_isRunning) return;
            try
            {
                TakeSample();
            }
            catch (Exception exception)
            {
                StopMonitoring(Tr("发生错误：", "Error: ") + exception.Message, false, false);
                MessageBox.Show(_window, Tr("采样时发生错误，记录已停止。\n\n", "A sampling error occurred and recording was stopped.\n\n") + exception.Message, Tr("记录已停止", "Recording stopped"), MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void UiTimerTick(object sender, EventArgs eventArgs)
        {
            if (!_isRunning) return;
            UpdateRuntimeUi();
            if (_targetSeconds > 0 && _stopwatch.Elapsed.TotalSeconds >= _targetSeconds)
            {
                StopMonitoring(Tr("达到设定时长", "Duration reached"), true, true);
            }
        }

        private void TakeSample()
        {
            double currentElapsed = _stopwatch.Elapsed.TotalSeconds;
            double interval = currentElapsed - _lastSampleElapsed;
            if (interval <= 0.05) return;
            _lastSampleElapsed = currentElapsed;

            var currentAdapters = ResolveActiveAdapters(_manualMode);
            foreach (var adapter in currentAdapters) _observedAdapterNames.Add(adapter.Name);

            var adaptersToQuery = new Dictionary<string, NetworkInterface>(StringComparer.OrdinalIgnoreCase);
            foreach (var pair in _previousSnapshot) adaptersToQuery[pair.Key] = pair.Value.Adapter;
            foreach (var adapter in currentAdapters) adaptersToQuery[NormalizeId(adapter.Id)] = adapter;

            var snapshot = SnapshotAdapters(adaptersToQuery.Values.ToList());
            double receivedDelta = 0;
            double sentDelta = 0;
            foreach (var pair in snapshot)
            {
                CounterSnapshot oldValue;
                if (!_previousSnapshot.TryGetValue(pair.Key, out oldValue)) continue;
                CounterSnapshot newValue = pair.Value;
                if (newValue.Received >= oldValue.Received) receivedDelta += newValue.Received - oldValue.Received;
                if (newValue.Sent >= oldValue.Sent) sentDelta += newValue.Sent - oldValue.Sent;
            }

            var nextSnapshot = new Dictionary<string, CounterSnapshot>(StringComparer.OrdinalIgnoreCase);
            foreach (var adapter in currentAdapters)
            {
                string key = NormalizeId(adapter.Id);
                CounterSnapshot value;
                if (snapshot.TryGetValue(key, out value)) nextSnapshot[key] = value;
            }
            _previousSnapshot = nextSnapshot;

            double downloadBytesPerSecond = receivedDelta / interval;
            double uploadBytesPerSecond = sentDelta / interval;
            _sampleCount++;
            _totalReceivedBytes += receivedDelta;
            _totalSentBytes += sentDelta;
            _totalMeasuredSeconds += interval;
            _minDownloadBytesPerSecond = Math.Min(_minDownloadBytesPerSecond, downloadBytesPerSecond);
            _maxDownloadBytesPerSecond = Math.Max(_maxDownloadBytesPerSecond, downloadBytesPerSecond);
            _minUploadBytesPerSecond = Math.Min(_minUploadBytesPerSecond, uploadBytesPerSecond);
            _maxUploadBytesPerSecond = Math.Max(_maxUploadBytesPerSecond, uploadBytesPerSecond);

            string adapterNames = currentAdapters.Count == 0 ? Tr("(无活动网卡)", "(no active adapter)") : string.Join("; ", currentAdapters.Select(item => item.Name));
            double downloadValue = ConvertRate(downloadBytesPerSecond);
            double uploadValue = ConvertRate(uploadBytesPerSecond);
            string timestamp = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffzzz", CultureInfo.InvariantCulture);
            _csvWriter.WriteLine(
                timestamp + "," +
                currentElapsed.ToString("F3", CultureInfo.InvariantCulture) + "," +
                downloadValue.ToString("F6", CultureInfo.InvariantCulture) + "," +
                uploadValue.ToString("F6", CultureInfo.InvariantCulture) + ",\"" +
                EscapeCsv(adapterNames) + "\"");
            _csvWriter.Flush();

            _currentDownloadText.Text = FormatRateValue(downloadValue);
            _currentUploadText.Text = FormatRateValue(uploadValue);
            _sampleCountText.Text = _sampleCount + Tr(" 个样本", " samples");
            _totalTrafficText.Text = Tr("下载 ", "Download ") + FormatBytes(_totalReceivedBytes) + Tr(" · 上传 ", " · Upload ") + FormatBytes(_totalSentBytes);
            _recentSamples.Insert(0, new SampleRow(DateTime.Now.ToString("HH:mm:ss"), FormatRateValue(downloadValue), FormatRateValue(uploadValue), adapterNames));
            while (_recentSamples.Count > 5) _recentSamples.RemoveAt(_recentSamples.Count - 1);
            _chart.Add(downloadValue, uploadValue);
            UpdateStatisticsUi();
            _summaryStateText.Text = Tr("最近采样：", "Latest sample: ") + DateTime.Now.ToString("HH:mm:ss") + " · " + adapterNames;
            _sidebarStatusText.Text = Tr("正在记录 · 下载 ", "Recording · Download ") + FormatRateValue(downloadValue) + " " + _unit + Tr(" · 上传 ", " · Upload ") + FormatRateValue(uploadValue) + " " + _unit;
        }

        private void UpdateStatisticsUi()
        {
            if (_sampleCount <= 0 || _totalMeasuredSeconds <= 0) return;
            double averageDownload = _totalReceivedBytes / _totalMeasuredSeconds;
            double averageUpload = _totalSentBytes / _totalMeasuredSeconds;
            _minSpeedText.Text = Tr("下载 ", "Download ") + FormatRate(_minDownloadBytesPerSecond) + Tr(" · 上传 ", " · Upload ") + FormatRate(_minUploadBytesPerSecond);
            _maxSpeedText.Text = Tr("下载 ", "Download ") + FormatRate(_maxDownloadBytesPerSecond) + Tr(" · 上传 ", " · Upload ") + FormatRate(_maxUploadBytesPerSecond);
            _avgSpeedText.Text = Tr("下载 ", "Download ") + FormatRate(averageDownload) + Tr(" · 上传 ", " · Upload ") + FormatRate(averageUpload);
        }

        private void UpdateRuntimeUi()
        {
            double elapsed = _stopwatch.Elapsed.TotalSeconds;
            _elapsedText.Text = FormatDuration(elapsed);
            if (_targetSeconds > 0)
            {
                double remaining = Math.Max(0, _targetSeconds - elapsed);
                _remainingText.Text = Tr("剩余 ", "Remaining ") + FormatDuration(remaining);
                _runProgress.IsIndeterminate = false;
                _runProgress.Value = Math.Min(100, elapsed / _targetSeconds * 100.0);
            }
            else
            {
                _remainingText.Text = Tr("不限时运行", "No time limit");
                _runProgress.IsIndeterminate = true;
            }
        }

        private void StopMonitoring(string reason, bool takeFinalSample, bool durationReached)
        {
            if (!_isRunning) return;
            _sampleTimer.Stop();
            _uiTimer.Stop();

            if (takeFinalSample && _stopwatch.Elapsed.TotalSeconds - _lastSampleElapsed > 0.20)
            {
                try { TakeSample(); }
                catch (Exception exception) { reason += Tr("（末次采样失败：", " (final sample failed: ") + exception.Message + Tr("）", ")"); }
            }

            _stopwatch.Stop();
            _isRunning = false;
            _hasCompletedSession = true;
            DateTime endTime = DateTime.Now;
            if (_csvWriter != null)
            {
                _csvWriter.Flush();
                _csvWriter.Dispose();
                _csvWriter = null;
            }

            string summaryError = null;
            try { WriteSummary(endTime, reason); }
            catch (Exception exception) { summaryError = exception.Message; }

            _configInputs.IsEnabled = true;
            _startButton.IsEnabled = true;
            _stopButton.IsEnabled = false;
            RefreshAdapters(false);
            _runProgress.IsIndeterminate = false;
            if (_targetSeconds > 0 && durationReached) _runProgress.Value = 100;
            _statusDot.Fill = new SolidColorBrush(summaryError == null ? Color.FromRgb(0x4F, 0x7C, 0xFF) : Color.FromRgb(0xE4, 0x58, 0x58));
            _statusText.Text = summaryError == null ? Tr("记录已结束", "Finished") : Tr("结束时出错", "Completion error");
            _statusText.Foreground = new SolidColorBrush(summaryError == null ? Color.FromRgb(0x31, 0x59, 0xC8) : Color.FromRgb(0xB9, 0x3D, 0x3D));
            _summaryStateText.Text = reason + " · " + _sampleCount + Tr(" 个有效样本", " valid samples");
            _sidebarStatusText.Text = summaryError == null ? Tr("记录已结束，结果文件已经保存", "Session finished; result files were saved") : Tr("CSV 已保存，但 Markdown 汇总生成失败", "CSV was saved, but the Markdown summary failed");
            _openResultsButton.Visibility = Visibility.Visible;
            _sessionMessageBorder.Background = new SolidColorBrush(summaryError == null ? Color.FromRgb(0xE9, 0xF8, 0xF2) : Color.FromRgb(0xFE, 0xEC, 0xEC));
            _sessionMessageText.Foreground = new SolidColorBrush(summaryError == null ? Color.FromRgb(0x3B, 0x71, 0x60) : Color.FromRgb(0x9E, 0x3B, 0x3B));
            _sessionMessageText.Text = summaryError == null
                ? reason + Tr("。CSV：", ". CSV: ") + _csvPath + Tr("　汇总：", "  Summary: ") + _summaryPath
                : reason + Tr("。CSV 已保存，但汇总失败：", ". CSV was saved, but the summary failed: ") + summaryError;
            _elapsedText.Text = FormatDuration(_stopwatch.Elapsed.TotalSeconds);
            _remainingText.Text = Tr("记录已结束", "Finished");
        }

        private void WriteSummary(DateTime endTime, string reason)
        {
            double minDownload = _sampleCount > 0 ? _minDownloadBytesPerSecond : 0;
            double minUpload = _sampleCount > 0 ? _minUploadBytesPerSecond : 0;
            double averageDownload = _totalMeasuredSeconds > 0 ? _totalReceivedBytes / _totalMeasuredSeconds : 0;
            double averageUpload = _totalMeasuredSeconds > 0 ? _totalSentBytes / _totalMeasuredSeconds : 0;
            string mode = _manualMode ? Tr("手动选择网卡", "Manually selected adapters") : Tr("自动物理网卡", "Automatic physical adapters");
            string adapters = _observedAdapterNames.Count > 0 ? string.Join(_isChinese ? "、" : ", ", _observedAdapterNames.OrderBy(item => item)) : Tr("无", "None");

            using (var writer = new StreamWriter(_summaryPath, false, new UTF8Encoding(true)))
            {
                if (_isChinese)
                {
                    writer.WriteLine("# 网络速度监控汇总");
                    writer.WriteLine();
                    writer.WriteLine("- 开始时间：" + _startTime.ToString("yyyy-MM-dd HH:mm:ss zzz"));
                    writer.WriteLine("- 结束时间：" + endTime.ToString("yyyy-MM-dd HH:mm:ss zzz"));
                    writer.WriteLine("- 实际运行时间：" + FormatDuration(_stopwatch.Elapsed.TotalSeconds));
                    writer.WriteLine("- 结束原因：" + reason);
                    writer.WriteLine("- 采样间隔：" + _sampleIntervalSeconds + " 秒");
                    writer.WriteLine("- 速度单位：" + _unit);
                    writer.WriteLine("- 网卡模式：" + mode);
                    writer.WriteLine("- 监控过的网卡：" + adapters.Replace("|", "\\|"));
                    writer.WriteLine("- 有效样本数：" + _sampleCount);
                    writer.WriteLine("- 详细记录：" + Path.GetFileName(_csvPath));
                    writer.WriteLine();
                    writer.WriteLine("| 指标 | 下载 | 上传 |");
                    writer.WriteLine("|---|---:|---:|");
                    writer.WriteLine("| 最小速度 | " + FormatRate(minDownload) + " | " + FormatRate(minUpload) + " |");
                    writer.WriteLine("| 最大速度 | " + FormatRate(_maxDownloadBytesPerSecond) + " | " + FormatRate(_maxUploadBytesPerSecond) + " |");
                    writer.WriteLine("| 平均速度 | " + FormatRate(averageDownload) + " | " + FormatRate(averageUpload) + " |");
                    writer.WriteLine("| 总数据量 | " + FormatBytes(_totalReceivedBytes) + " | " + FormatBytes(_totalSentBytes) + " |");
                    writer.WriteLine();
                    writer.WriteLine("> 数据为所选网卡的实际收发流量，包含互联网和局域网流量。自动模式会排除虚拟网卡以避免重复计数。");
                }
                else
                {
                    writer.WriteLine("# Network Speed Monitoring Summary");
                    writer.WriteLine();
                    writer.WriteLine("- Start time: " + _startTime.ToString("yyyy-MM-dd HH:mm:ss zzz"));
                    writer.WriteLine("- End time: " + endTime.ToString("yyyy-MM-dd HH:mm:ss zzz"));
                    writer.WriteLine("- Actual duration: " + FormatDuration(_stopwatch.Elapsed.TotalSeconds));
                    writer.WriteLine("- Stop reason: " + reason);
                    writer.WriteLine("- Sample interval: " + _sampleIntervalSeconds + " seconds");
                    writer.WriteLine("- Speed unit: " + _unit);
                    writer.WriteLine("- Adapter mode: " + mode);
                    writer.WriteLine("- Monitored adapters: " + adapters.Replace("|", "\\|"));
                    writer.WriteLine("- Valid samples: " + _sampleCount);
                    writer.WriteLine("- Detailed log: " + Path.GetFileName(_csvPath));
                    writer.WriteLine();
                    writer.WriteLine("| Metric | Download | Upload |");
                    writer.WriteLine("|---|---:|---:|");
                    writer.WriteLine("| Minimum speed | " + FormatRate(minDownload) + " | " + FormatRate(minUpload) + " |");
                    writer.WriteLine("| Maximum speed | " + FormatRate(_maxDownloadBytesPerSecond) + " | " + FormatRate(_maxUploadBytesPerSecond) + " |");
                    writer.WriteLine("| Average speed | " + FormatRate(averageDownload) + " | " + FormatRate(averageUpload) + " |");
                    writer.WriteLine("| Total data | " + FormatBytes(_totalReceivedBytes) + " | " + FormatBytes(_totalSentBytes) + " |");
                    writer.WriteLine();
                    writer.WriteLine("> Values are actual traffic on the selected adapters and include both internet and local-network traffic. Auto mode excludes virtual adapters to avoid double counting.");
                }
            }
        }

        private List<NetworkInterface> ResolveActiveAdapters(bool manualMode)
        {
            // 活动状态每次采样都会重新读取；物理网卡清单每 30 秒刷新一次，
            // 因而运行中插入 USB 网卡或新增物理网卡也能被自动模式发现。
            if (!manualMode && _isRunning &&
                _stopwatch.Elapsed.TotalSeconds - _lastPhysicalRefreshElapsed >= 30.0)
            {
                bool fallback;
                HashSet<string> refreshed = DetectPhysicalAdapters(out fallback);
                if (refreshed.Count > 0)
                {
                    _physicalAdapterIds = refreshed;
                    _physicalDetectionFallback = fallback;
                }
                _lastPhysicalRefreshElapsed = _stopwatch.Elapsed.TotalSeconds;
            }

            var allowedIds = manualMode
                ? new HashSet<string>(_adapterChoices.Where(item => item.IsSelected).Select(item => item.Id), StringComparer.OrdinalIgnoreCase)
                : _physicalAdapterIds;

            return NetworkInterface.GetAllNetworkInterfaces()
                .Where(item => item.OperationalStatus == OperationalStatus.Up &&
                               item.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                               item.NetworkInterfaceType != NetworkInterfaceType.Tunnel &&
                               allowedIds.Contains(NormalizeId(item.Id)))
                .OrderBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToList();
        }

        private static Dictionary<string, CounterSnapshot> SnapshotAdapters(IList<NetworkInterface> adapters)
        {
            var result = new Dictionary<string, CounterSnapshot>(StringComparer.OrdinalIgnoreCase);
            foreach (var adapter in adapters)
            {
                try
                {
                    IPv4InterfaceStatistics statistics = adapter.GetIPv4Statistics();
                    result[NormalizeId(adapter.Id)] = new CounterSnapshot(adapter, statistics.BytesReceived, statistics.BytesSent);
                }
                catch
                {
                }
            }
            return result;
        }

        private double ConvertRate(double bytesPerSecond)
        {
            return _unit == "Mbps" ? bytesPerSecond * 8.0 / 1000000.0 : bytesPerSecond / 1000000.0;
        }

        private string FormatRate(double bytesPerSecond)
        {
            return FormatRateValue(ConvertRate(bytesPerSecond)) + " " + _unit;
        }

        private static string FormatRateValue(double value)
        {
            return value.ToString("0.000", CultureInfo.InvariantCulture);
        }

        private static string FormatBytes(double bytes)
        {
            if (bytes >= 1000000000.0) return (bytes / 1000000000.0).ToString("0.00", CultureInfo.InvariantCulture) + " GB";
            if (bytes >= 1000000.0) return (bytes / 1000000.0).ToString("0.00", CultureInfo.InvariantCulture) + " MB";
            if (bytes >= 1000.0) return (bytes / 1000.0).ToString("0.00", CultureInfo.InvariantCulture) + " KB";
            return bytes.ToString("0", CultureInfo.InvariantCulture) + " B";
        }

        private string FormatDuration(double seconds)
        {
            var span = TimeSpan.FromSeconds(Math.Max(0, seconds));
            if (span.TotalDays >= 1)
            {
                return Math.Floor(span.TotalDays).ToString(CultureInfo.InvariantCulture) + Tr(" 天 ", " d ") +
                       span.Hours.ToString("00") + ":" + span.Minutes.ToString("00") + ":" + span.Seconds.ToString("00");
            }
            return span.Hours.ToString("00") + ":" + span.Minutes.ToString("00") + ":" + span.Seconds.ToString("00");
        }

        private static bool TryReadDouble(string text, out double value)
        {
            return double.TryParse(text.Trim(), NumberStyles.Float, CultureInfo.CurrentCulture, out value) ||
                   double.TryParse(text.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out value);
        }

        private static string NormalizeId(string id)
        {
            return (id ?? string.Empty).Trim().Trim('{', '}').ToUpperInvariant();
        }

        private static string EscapeCsv(string text)
        {
            return (text ?? string.Empty).Replace("\"", "\"\"");
        }

        private static void CreateOutputPaths(string folder, DateTime startTime, out string csvPath, out string summaryPath)
        {
            string stamp = startTime.ToString("yyyyMMdd_HHmmss");
            string baseName = "NetworkSpeed_" + stamp;
            csvPath = Path.Combine(folder, baseName + ".csv");
            summaryPath = Path.Combine(folder, baseName + "_summary.md");
            int suffix = 1;
            while (File.Exists(csvPath) || File.Exists(summaryPath))
            {
                csvPath = Path.Combine(folder, baseName + "_" + suffix + ".csv");
                summaryPath = Path.Combine(folder, baseName + "_" + suffix + "_summary.md");
                suffix++;
            }
        }

        private void ShowValidation(string message, TextBox field)
        {
            MessageBox.Show(_window, message, Tr("参数有误", "Invalid setting"), MessageBoxButton.OK, MessageBoxImage.Warning);
            field.Focus();
            field.SelectAll();
        }

        private void OpenResultsButtonClick(object sender, RoutedEventArgs eventArgs)
        {
            try
            {
                if (!string.IsNullOrWhiteSpace(_summaryPath) && File.Exists(_summaryPath))
                {
                    Process.Start("explorer.exe", "/select,\"" + _summaryPath + "\"");
                }
                else if (Directory.Exists(_outputFolderText.Text))
                {
                    Process.Start("explorer.exe", "\"" + _outputFolderText.Text + "\"");
                }
            }
            catch (Exception exception)
            {
                MessageBox.Show(_window, Tr("无法打开结果文件夹。\n\n", "Unable to open the results folder.\n\n") + exception.Message, Tr("打开失败", "Open failed"), MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        private void WindowClosing(object sender, CancelEventArgs eventArgs)
        {
            if (!_isRunning) return;
            var result = MessageBox.Show(_window, Tr("当前仍在记录网速。是否结束记录并退出？", "Recording is still in progress. Stop and exit?"), Tr("确认退出", "Confirm exit"), MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (result != MessageBoxResult.Yes)
            {
                eventArgs.Cancel = true;
                return;
            }
            StopMonitoring(Tr("关闭程序", "Application closed"), true, false);
        }
    }

    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            try
            {
                Window window;
                Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("NetworkSpeedLogger.MainWindow.xaml");
                if (stream == null) throw new InvalidOperationException("无法加载内置界面资源。");
                using (stream)
                using (var reader = XmlReader.Create(stream))
                {
                    window = (Window)XamlReader.Load(reader);
                }

                var application = new Application();
                application.ShutdownMode = ShutdownMode.OnMainWindowClose;
                var controller = new MonitorController(window);
                application.Run(window);
                GC.KeepAlive(controller);
            }
            catch (Exception exception)
            {
                bool isChinese = string.Equals(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName, "zh", StringComparison.OrdinalIgnoreCase);
                MessageBox.Show(
                    (isChinese ? "程序无法启动。\n\n" : "The application could not start.\n\n") + exception.Message,
                    isChinese ? "网速记录工具" : "Network Speed Logger",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            }
        }
    }
}
