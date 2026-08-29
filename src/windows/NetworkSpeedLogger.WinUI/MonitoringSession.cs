using System.Diagnostics;
using System.Globalization;
using System.Net.NetworkInformation;
using System.Text;

namespace NetworkSpeedLogger;

public sealed class MonitoringSession : IDisposable
{
    private readonly NetworkAdapterService _adapterService;
    private readonly SessionOptions _options;
    private readonly Stopwatch _stopwatch = new();
    private readonly HashSet<string> _observedAdapterNames = new(StringComparer.CurrentCultureIgnoreCase);
    private Dictionary<string, CounterSnapshot> _previousSnapshot = new(StringComparer.OrdinalIgnoreCase);
    private StreamWriter? _csvWriter;
    private double _lastSampleElapsed;
    private double _lastPhysicalRefreshElapsed;
    private long _sampleCount;
    private double _totalReceivedBytes;
    private double _totalSentBytes;
    private double _totalMeasuredSeconds;
    private double _minimumDownloadBytesPerSecond = double.PositiveInfinity;
    private double _maximumDownloadBytesPerSecond;
    private double _minimumUploadBytesPerSecond = double.PositiveInfinity;
    private double _maximumUploadBytesPerSecond;

    public MonitoringSession(NetworkAdapterService adapterService, SessionOptions options)
    {
        _adapterService = adapterService;
        _options = options;
    }

    public bool IsRunning { get; private set; }
    public DateTime StartTime { get; private set; }
    public double ElapsedSeconds => _stopwatch.Elapsed.TotalSeconds;
    public double TargetSeconds => _options.DurationHours * 3600.0;
    public string Unit => _options.Unit;
    public string CsvPath { get; private set; } = string.Empty;
    public string SummaryPath { get; private set; } = string.Empty;
    public long SampleCount => _sampleCount;
    public double TotalReceivedBytes => _totalReceivedBytes;
    public double TotalSentBytes => _totalSentBytes;

    public IReadOnlyList<string> Start()
    {
        if (IsRunning) throw new InvalidOperationException("The session is already running.");
        if (!_options.ManualMode) _adapterService.RefreshPhysicalAdapterIds();

        List<NetworkInterface> activeAdapters = _adapterService.ResolveActiveAdapters(
            _options.ManualMode,
            _options.SelectedAdapterIds);
        if (activeAdapters.Count == 0)
        {
            throw new InvalidOperationException(_options.ManualMode
                ? T("勾选的网卡目前均未连接。", "None of the selected adapters is connected.")
                : T("没有检测到已连接的物理网卡。", "No connected physical adapter was detected."));
        }

        _previousSnapshot = NetworkAdapterService.SnapshotAdapters(activeAdapters);
        if (_previousSnapshot.Count == 0)
            throw new InvalidOperationException(T("无法读取所选网卡的流量计数器。", "Unable to read traffic counters for the selected adapters."));

        StartTime = DateTime.Now;
        CreateOutputPaths(_options.OutputFolder, StartTime, out string csvPath, out string summaryPath);
        CsvPath = csvPath;
        SummaryPath = summaryPath;
        _csvWriter = new StreamWriter(CsvPath, false, new UTF8Encoding(true));
        string columnUnit = Unit == "Mbps" ? "Mbps" : "MBps";
        _csvWriter.WriteLine("Timestamp,ElapsedSeconds,Download_" + columnUnit + ",Upload_" + columnUnit + ",ActiveAdapters");
        _csvWriter.Flush();

        foreach (NetworkInterface adapter in activeAdapters) _observedAdapterNames.Add(adapter.Name);
        _lastSampleElapsed = 0;
        _lastPhysicalRefreshElapsed = 0;
        _stopwatch.Restart();
        IsRunning = true;
        return activeAdapters.Select(item => item.Name).ToArray();
    }

    public SessionSample? TakeSample()
    {
        if (!IsRunning) return null;
        double currentElapsed = _stopwatch.Elapsed.TotalSeconds;
        double interval = currentElapsed - _lastSampleElapsed;
        if (interval <= 0.05) return null;
        _lastSampleElapsed = currentElapsed;

        if (!_options.ManualMode && currentElapsed - _lastPhysicalRefreshElapsed >= 30.0)
        {
            _adapterService.RefreshPhysicalAdapterIds();
            _lastPhysicalRefreshElapsed = currentElapsed;
        }

        List<NetworkInterface> currentAdapters = _adapterService.ResolveActiveAdapters(
            _options.ManualMode,
            _options.SelectedAdapterIds);
        foreach (NetworkInterface adapter in currentAdapters) _observedAdapterNames.Add(adapter.Name);

        var adaptersToQuery = new Dictionary<string, NetworkInterface>(StringComparer.OrdinalIgnoreCase);
        foreach ((string key, CounterSnapshot value) in _previousSnapshot) adaptersToQuery[key] = value.Adapter;
        foreach (NetworkInterface adapter in currentAdapters)
            adaptersToQuery[NetworkAdapterService.NormalizeId(adapter.Id)] = adapter;

        Dictionary<string, CounterSnapshot> snapshot = NetworkAdapterService.SnapshotAdapters(adaptersToQuery.Values);
        double receivedDelta = 0;
        double sentDelta = 0;
        foreach ((string key, CounterSnapshot current) in snapshot)
        {
            if (!_previousSnapshot.TryGetValue(key, out CounterSnapshot? previous)) continue;
            if (current.Received >= previous.Received) receivedDelta += current.Received - previous.Received;
            if (current.Sent >= previous.Sent) sentDelta += current.Sent - previous.Sent;
        }

        var nextSnapshot = new Dictionary<string, CounterSnapshot>(StringComparer.OrdinalIgnoreCase);
        foreach (NetworkInterface adapter in currentAdapters)
        {
            string key = NetworkAdapterService.NormalizeId(adapter.Id);
            if (snapshot.TryGetValue(key, out CounterSnapshot? value)) nextSnapshot[key] = value;
        }
        _previousSnapshot = nextSnapshot;

        double downloadBytesPerSecond = receivedDelta / interval;
        double uploadBytesPerSecond = sentDelta / interval;
        _sampleCount++;
        _totalReceivedBytes += receivedDelta;
        _totalSentBytes += sentDelta;
        _totalMeasuredSeconds += interval;
        _minimumDownloadBytesPerSecond = Math.Min(_minimumDownloadBytesPerSecond, downloadBytesPerSecond);
        _maximumDownloadBytesPerSecond = Math.Max(_maximumDownloadBytesPerSecond, downloadBytesPerSecond);
        _minimumUploadBytesPerSecond = Math.Min(_minimumUploadBytesPerSecond, uploadBytesPerSecond);
        _maximumUploadBytesPerSecond = Math.Max(_maximumUploadBytesPerSecond, uploadBytesPerSecond);

        string adapterNames = currentAdapters.Count == 0
            ? T("(无活动网卡)", "(no active adapter)")
            : string.Join("; ", currentAdapters.Select(item => item.Name));
        double downloadValue = ConvertRate(downloadBytesPerSecond);
        double uploadValue = ConvertRate(uploadBytesPerSecond);
        string timestamp = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffzzz", CultureInfo.InvariantCulture);
        _csvWriter!.WriteLine(
            timestamp + "," +
            currentElapsed.ToString("F3", CultureInfo.InvariantCulture) + "," +
            downloadValue.ToString("F6", CultureInfo.InvariantCulture) + "," +
            uploadValue.ToString("F6", CultureInfo.InvariantCulture) + ",\"" +
            EscapeCsv(adapterNames) + "\"");
        _csvWriter.Flush();

        return new SessionSample(
            DateTime.Now,
            currentElapsed,
            downloadValue,
            uploadValue,
            downloadBytesPerSecond,
            uploadBytesPerSecond,
            _totalReceivedBytes,
            _totalSentBytes,
            _sampleCount,
            adapterNames);
    }

    public string Stop(string reason, bool takeFinalSample)
    {
        if (!IsRunning) return reason;
        if (takeFinalSample && _stopwatch.Elapsed.TotalSeconds - _lastSampleElapsed > 0.20)
        {
            try
            {
                TakeSample();
            }
            catch (Exception exception)
            {
                reason += T("（末次采样失败：", " (final sample failed: ") + exception.Message + T("）", ")");
            }
        }

        _stopwatch.Stop();
        IsRunning = false;
        _csvWriter?.Flush();
        _csvWriter?.Dispose();
        _csvWriter = null;
        WriteSummary(DateTime.Now, reason);
        return reason;
    }

    public SessionStatistics GetStatistics()
    {
        double minimumDownload = _sampleCount > 0 ? _minimumDownloadBytesPerSecond : 0;
        double minimumUpload = _sampleCount > 0 ? _minimumUploadBytesPerSecond : 0;
        double averageDownload = _totalMeasuredSeconds > 0 ? _totalReceivedBytes / _totalMeasuredSeconds : 0;
        double averageUpload = _totalMeasuredSeconds > 0 ? _totalSentBytes / _totalMeasuredSeconds : 0;
        return new SessionStatistics(
            minimumDownload,
            _maximumDownloadBytesPerSecond,
            averageDownload,
            minimumUpload,
            _maximumUploadBytesPerSecond,
            averageUpload);
    }

    public double ConvertRate(double bytesPerSecond) =>
        Unit == "Mbps" ? bytesPerSecond * 8.0 / 1_000_000.0 : bytesPerSecond / 1_000_000.0;

    public string FormatRate(double bytesPerSecond) => FormatRateValue(ConvertRate(bytesPerSecond)) + " " + Unit;

    public static string FormatRateValue(double value) => value.ToString("0.000", CultureInfo.InvariantCulture);

    public static string FormatBytes(double bytes)
    {
        if (bytes >= 1_000_000_000.0) return (bytes / 1_000_000_000.0).ToString("0.00", CultureInfo.InvariantCulture) + " GB";
        if (bytes >= 1_000_000.0) return (bytes / 1_000_000.0).ToString("0.00", CultureInfo.InvariantCulture) + " MB";
        if (bytes >= 1_000.0) return (bytes / 1_000.0).ToString("0.00", CultureInfo.InvariantCulture) + " KB";
        return bytes.ToString("0", CultureInfo.InvariantCulture) + " B";
    }

    public static string FormatDuration(double seconds, bool isChinese)
    {
        TimeSpan span = TimeSpan.FromSeconds(Math.Max(0, seconds));
        if (span.TotalDays >= 1)
        {
            return Math.Floor(span.TotalDays).ToString(CultureInfo.InvariantCulture) + (isChinese ? " 天 " : " d ") +
                   span.Hours.ToString("00") + ":" + span.Minutes.ToString("00") + ":" + span.Seconds.ToString("00");
        }
        return span.Hours.ToString("00") + ":" + span.Minutes.ToString("00") + ":" + span.Seconds.ToString("00");
    }

    public void Dispose()
    {
        _csvWriter?.Dispose();
        _csvWriter = null;
        _stopwatch.Stop();
        IsRunning = false;
    }

    private string T(string chinese, string english) => _options.IsChinese ? chinese : english;

    private void WriteSummary(DateTime endTime, string reason)
    {
        SessionStatistics statistics = GetStatistics();
        string mode = _options.ManualMode ? T("手动选择网卡", "Manually selected adapters") : T("自动物理网卡", "Automatic physical adapters");
        string adapters = _observedAdapterNames.Count > 0
            ? string.Join(_options.IsChinese ? "、" : ", ", _observedAdapterNames.OrderBy(item => item))
            : T("无", "None");

        using var writer = new StreamWriter(SummaryPath, false, new UTF8Encoding(true));
        if (_options.IsChinese)
        {
            writer.WriteLine("# 网络速度监控汇总");
            writer.WriteLine();
            writer.WriteLine("- 开始时间：" + StartTime.ToString("yyyy-MM-dd HH:mm:ss zzz"));
            writer.WriteLine("- 结束时间：" + endTime.ToString("yyyy-MM-dd HH:mm:ss zzz"));
            writer.WriteLine("- 实际运行时间：" + FormatDuration(_stopwatch.Elapsed.TotalSeconds, true));
            writer.WriteLine("- 结束原因：" + reason);
            writer.WriteLine("- 采样间隔：" + _options.SampleIntervalSeconds + " 秒");
            writer.WriteLine("- 速度单位：" + Unit);
            writer.WriteLine("- 网卡模式：" + mode);
            writer.WriteLine("- 监控过的网卡：" + adapters.Replace("|", "\\|"));
            writer.WriteLine("- 有效样本数：" + _sampleCount);
            writer.WriteLine("- 详细记录：" + Path.GetFileName(CsvPath));
            writer.WriteLine();
            writer.WriteLine("| 指标 | 下载 | 上传 |");
            writer.WriteLine("|---|---:|---:|");
            writer.WriteLine("| 最小速度 | " + FormatRate(statistics.MinimumDownloadBytesPerSecond) + " | " + FormatRate(statistics.MinimumUploadBytesPerSecond) + " |");
            writer.WriteLine("| 最大速度 | " + FormatRate(statistics.MaximumDownloadBytesPerSecond) + " | " + FormatRate(statistics.MaximumUploadBytesPerSecond) + " |");
            writer.WriteLine("| 平均速度 | " + FormatRate(statistics.AverageDownloadBytesPerSecond) + " | " + FormatRate(statistics.AverageUploadBytesPerSecond) + " |");
            writer.WriteLine("| 总数据量 | " + FormatBytes(_totalReceivedBytes) + " | " + FormatBytes(_totalSentBytes) + " |");
            writer.WriteLine();
            writer.WriteLine("> 数据为所选网卡的实际收发流量，包含互联网和局域网流量。自动模式会排除虚拟网卡以避免重复计数。");
        }
        else
        {
            writer.WriteLine("# Network Speed Monitoring Summary");
            writer.WriteLine();
            writer.WriteLine("- Start time: " + StartTime.ToString("yyyy-MM-dd HH:mm:ss zzz"));
            writer.WriteLine("- End time: " + endTime.ToString("yyyy-MM-dd HH:mm:ss zzz"));
            writer.WriteLine("- Actual duration: " + FormatDuration(_stopwatch.Elapsed.TotalSeconds, false));
            writer.WriteLine("- Stop reason: " + reason);
            writer.WriteLine("- Sample interval: " + _options.SampleIntervalSeconds + " seconds");
            writer.WriteLine("- Speed unit: " + Unit);
            writer.WriteLine("- Adapter mode: " + mode);
            writer.WriteLine("- Monitored adapters: " + adapters.Replace("|", "\\|"));
            writer.WriteLine("- Valid samples: " + _sampleCount);
            writer.WriteLine("- Detailed log: " + Path.GetFileName(CsvPath));
            writer.WriteLine();
            writer.WriteLine("| Metric | Download | Upload |");
            writer.WriteLine("|---|---:|---:|");
            writer.WriteLine("| Minimum speed | " + FormatRate(statistics.MinimumDownloadBytesPerSecond) + " | " + FormatRate(statistics.MinimumUploadBytesPerSecond) + " |");
            writer.WriteLine("| Maximum speed | " + FormatRate(statistics.MaximumDownloadBytesPerSecond) + " | " + FormatRate(statistics.MaximumUploadBytesPerSecond) + " |");
            writer.WriteLine("| Average speed | " + FormatRate(statistics.AverageDownloadBytesPerSecond) + " | " + FormatRate(statistics.AverageUploadBytesPerSecond) + " |");
            writer.WriteLine("| Total data | " + FormatBytes(_totalReceivedBytes) + " | " + FormatBytes(_totalSentBytes) + " |");
            writer.WriteLine();
            writer.WriteLine("> Values are actual traffic on the selected adapters and include both internet and local-network traffic. Auto mode excludes virtual adapters to avoid double counting.");
        }
    }

    private static string EscapeCsv(string text) => text.Replace("\"", "\"\"");

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
}
