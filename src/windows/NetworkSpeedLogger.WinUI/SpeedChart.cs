using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;

namespace NetworkSpeedLogger;

public sealed class SpeedChart : Canvas
{
    private readonly List<(double Download, double Upload)> _points = [];
    private string _unit = "MB/s";
    private bool _isChinese = true;

    public SpeedChart()
    {
        MinHeight = 220;
        SizeChanged += (_, _) => RenderChart();
        ActualThemeChanged += (_, _) => RenderChart();
    }

    public void Reset(string unit)
    {
        _unit = unit;
        _points.Clear();
        RenderChart();
    }

    public void SetLanguage(bool isChinese)
    {
        _isChinese = isChinese;
        RenderChart();
    }

    public void Add(double download, double upload)
    {
        _points.Add((download, upload));
        while (_points.Count > 60) _points.RemoveAt(0);
        RenderChart();
    }

    private void RenderChart()
    {
        Children.Clear();
        double width = ActualWidth;
        double height = ActualHeight;
        if (width < 120 || height < 80) return;

        const double left = 56;
        const double right = 16;
        const double top = 14;
        const double bottom = 30;
        double plotWidth = width - left - right;
        double plotHeight = height - top - bottom;

        bool dark = ActualTheme == ElementTheme.Dark;
        Brush gridBrush = new SolidColorBrush(dark
            ? ColorHelper.FromArgb(0x16, 0xFF, 0xFF, 0xFF)
            : ColorHelper.FromArgb(0x12, 0x00, 0x00, 0x00));
        Brush downloadBrush = ResolveBrush("DownloadBrush", Colors.DodgerBlue);
        Brush uploadBrush = ResolveBrush("UploadBrush", Colors.SeaGreen);

        double maximum = _points.Count == 0 ? 0 : _points.Max(point => Math.Max(point.Download, point.Upload));
        double minimumScale = _unit == "Mbps" ? 0.1 : 0.01;
        maximum = Math.Max(minimumScale, maximum * 1.15);

        for (int index = 0; index <= 4; index++)
        {
            double ratio = index / 4.0;
            double y = top + plotHeight * ratio;
            Children.Add(new Line
            {
                X1 = left,
                X2 = width - right,
                Y1 = y,
                Y2 = y,
                Stroke = gridBrush,
                StrokeThickness = 1
            });
            AddLabel(FormatAxis(maximum * (1.0 - ratio)), 4, y - 8);
        }

        AddLabel(_unit, 5, height - 22);

        if (_points.Count == 0)
        {
            var emptyText = new TextBlock
            {
                Text = _isChinese ? "等待第一个采样点…" : "Waiting for the first sample…",
                FontSize = 12,
                Opacity = 0.68
            };
            Children.Add(emptyText);
            emptyText.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            SetLeft(emptyText, left + Math.Max(0, (plotWidth - emptyText.DesiredSize.Width) / 2));
            SetTop(emptyText, top + Math.Max(0, (plotHeight - emptyText.DesiredSize.Height) / 2));
            return;
        }

        DrawSeries(true, left, top, plotWidth, plotHeight, maximum, downloadBrush, 2.4);
        DrawSeries(false, left, top, plotWidth, plotHeight, maximum, uploadBrush, 2.0);
    }

    private void DrawSeries(bool download, double left, double top, double width, double height, double maximum, Brush brush, double thickness)
    {
        var polyline = new Polyline
        {
            Stroke = brush,
            StrokeThickness = thickness,
            StrokeLineJoin = PenLineJoin.Round
        };

        for (int index = 0; index < _points.Count; index++)
        {
            double x = _points.Count == 1 ? left + width : left + width * index / (_points.Count - 1.0);
            double value = download ? _points[index].Download : _points[index].Upload;
            double y = top + height - value / maximum * height;
            polyline.Points.Add(new Point(x, y));
        }
        Children.Add(polyline);

        (double Download, double Upload) last = _points[^1];
        double lastValue = download ? last.Download : last.Upload;
        double lastY = top + height - lastValue / maximum * height;
        var marker = new Ellipse { Width = 7, Height = 7, Fill = brush };
        Children.Add(marker);
        SetLeft(marker, left + width - 3.5);
        SetTop(marker, lastY - 3.5);
    }

    private void AddLabel(string text, double x, double y)
    {
        var label = new TextBlock { Text = text, FontSize = 10, Opacity = 0.68 };
        Children.Add(label);
        SetLeft(label, x);
        SetTop(label, y);
    }

    private static Brush ResolveBrush(string key, Windows.UI.Color fallback)
    {
        if (Application.Current.Resources.TryGetValue(key, out object value) && value is Brush brush) return brush;
        return new SolidColorBrush(fallback);
    }

    private static string FormatAxis(double value)
    {
        if (value >= 100) return value.ToString("0");
        if (value >= 10) return value.ToString("0.0");
        if (value >= 1) return value.ToString("0.00");
        return value.ToString("0.000");
    }
}
