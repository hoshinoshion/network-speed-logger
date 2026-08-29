using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace NetworkSpeedLogger;

public sealed class AdapterChoice : INotifyPropertyChanged
{
    private bool _isSelected;

    public AdapterChoice(string id, string name, string detail, bool isPhysical, bool isConnected, bool isSelected)
    {
        Id = id;
        Name = name;
        Detail = detail;
        IsPhysical = isPhysical;
        IsConnected = isConnected;
        _isSelected = isSelected;
    }

    public string Id { get; }
    public string Name { get; }
    public string Detail { get; }
    public bool IsPhysical { get; }
    public bool IsConnected { get; }

    public bool IsSelected
    {
        get => _isSelected;
        set
        {
            if (_isSelected == value) return;
            _isSelected = value;
            OnPropertyChanged();
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed class SampleRow
{
    public SampleRow(string time, string download, string upload, string adapters)
    {
        Time = time;
        Download = download;
        Upload = upload;
        Adapters = adapters;
    }

    public string Time { get; }
    public string Download { get; }
    public string Upload { get; }
    public string Adapters { get; }
}

public sealed record SessionOptions(
    double DurationHours,
    int SampleIntervalSeconds,
    string Unit,
    string OutputFolder,
    bool ManualMode,
    IReadOnlyCollection<string> SelectedAdapterIds,
    bool IsChinese);

public sealed record SessionSample(
    DateTime Time,
    double ElapsedSeconds,
    double DownloadValue,
    double UploadValue,
    double DownloadBytesPerSecond,
    double UploadBytesPerSecond,
    double TotalReceivedBytes,
    double TotalSentBytes,
    long SampleCount,
    string AdapterNames);

public sealed record SessionStatistics(
    double MinimumDownloadBytesPerSecond,
    double MaximumDownloadBytesPerSecond,
    double AverageDownloadBytesPerSecond,
    double MinimumUploadBytesPerSecond,
    double MaximumUploadBytesPerSecond,
    double AverageUploadBytesPerSecond);
