using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NetworkSpeedLogger;

public sealed class SessionDefaults
{
    [JsonPropertyName("durationHours")]
    public double DurationHours { get; set; } = 24;

    [JsonPropertyName("sampleIntervalSeconds")]
    public int SampleIntervalSeconds { get; set; } = 15;

    [JsonPropertyName("speedUnit")]
    public string SpeedUnit { get; set; } = "MB/s";

    public SessionDefaults Clone() => new()
    {
        DurationHours = DurationHours,
        SampleIntervalSeconds = SampleIntervalSeconds,
        SpeedUnit = SpeedUnit
    };
}

public sealed class AppSettingsData
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; } = 1;

    [JsonPropertyName("language")]
    public string Language { get; set; } = "Auto";

    [JsonPropertyName("outputFolder")]
    public string OutputFolder { get; set; } = string.Empty;

    [JsonPropertyName("defaults")]
    public SessionDefaults Defaults { get; set; } = new();

    public AppSettingsData Clone() => new()
    {
        SchemaVersion = SchemaVersion,
        Language = Language,
        OutputFolder = OutputFolder,
        Defaults = Defaults.Clone()
    };
}

public static class AppSettingsStore
{
    public const double MinimumDurationHours = 0;
    public const double MaximumDurationHours = 8760;
    public const int MinimumSampleIntervalSeconds = 1;
    public const int MaximumSampleIntervalSeconds = 3600;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    public static string SettingsFolder => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "NetworkSpeedLogger");

    public static string SettingsPath => Path.Combine(SettingsFolder, "settings.json");

    private static string LegacyLanguagePath => Path.Combine(SettingsFolder, "language.txt");

    public static AppSettingsData Load()
    {
        AppSettingsData? settings = null;
        try
        {
            if (File.Exists(SettingsPath))
                settings = JsonSerializer.Deserialize<AppSettingsData>(File.ReadAllText(SettingsPath), JsonOptions);
        }
        catch
        {
            settings = null;
        }

        if (settings is null)
        {
            settings = CreateDefaults();
            settings.Language = LoadLegacyLanguage();
        }

        Normalize(settings);
        return settings;
    }

    public static bool TrySave(AppSettingsData settings, out string? error)
    {
        error = null;
        Normalize(settings);
        string? temporaryPath = null;
        try
        {
            Directory.CreateDirectory(SettingsFolder);
            temporaryPath = SettingsPath + ".tmp";
            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(settings, JsonOptions));

            if (File.Exists(SettingsPath))
            {
                string backupPath = SettingsPath + ".bak";
                try
                {
                    File.Replace(temporaryPath, SettingsPath, backupPath, true);
                    if (File.Exists(backupPath)) File.Delete(backupPath);
                }
                catch
                {
                    File.Copy(temporaryPath, SettingsPath, true);
                    File.Delete(temporaryPath);
                }
            }
            else
            {
                File.Move(temporaryPath, SettingsPath);
            }

            try
            {
                if (File.Exists(LegacyLanguagePath)) File.Delete(LegacyLanguagePath);
            }
            catch
            {
            }

            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            try
            {
                if (!string.IsNullOrWhiteSpace(temporaryPath) && File.Exists(temporaryPath)) File.Delete(temporaryPath);
            }
            catch
            {
            }
            return false;
        }
    }

    public static AppSettingsData CreateDefaults() => new();

    public static bool IsValidLanguage(string? value) => value is "Auto" or "zh-CN" or "en-US";

    public static bool IsValidSpeedUnit(string? value) => value is "MB/s" or "Mbps";

    public static bool IsValidDuration(double value) =>
        !double.IsNaN(value) && !double.IsInfinity(value) &&
        value >= MinimumDurationHours && value <= MaximumDurationHours;

    public static bool IsValidSampleInterval(int value) =>
        value >= MinimumSampleIntervalSeconds && value <= MaximumSampleIntervalSeconds;

    private static void Normalize(AppSettingsData settings)
    {
        AppSettingsData builtIn = CreateDefaults();
        settings.SchemaVersion = 1;
        if (!IsValidLanguage(settings.Language)) settings.Language = builtIn.Language;
        settings.OutputFolder = (settings.OutputFolder ?? string.Empty).Trim();
        settings.Defaults ??= builtIn.Defaults;
        if (!IsValidDuration(settings.Defaults.DurationHours)) settings.Defaults.DurationHours = builtIn.Defaults.DurationHours;
        if (!IsValidSampleInterval(settings.Defaults.SampleIntervalSeconds)) settings.Defaults.SampleIntervalSeconds = builtIn.Defaults.SampleIntervalSeconds;
        if (!IsValidSpeedUnit(settings.Defaults.SpeedUnit)) settings.Defaults.SpeedUnit = builtIn.Defaults.SpeedUnit;
    }

    private static string LoadLegacyLanguage()
    {
        try
        {
            string value = File.ReadAllText(LegacyLanguagePath).Trim();
            if (IsValidLanguage(value)) return value;
        }
        catch
        {
        }
        return "Auto";
    }
}

public static class Localization
{
    public static bool IsChinese { get; private set; } =
        string.Equals(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName, "zh", StringComparison.OrdinalIgnoreCase);

    public static void ApplyPreference(string preference)
    {
        IsChinese = preference switch
        {
            "zh-CN" => true,
            "en-US" => false,
            _ => string.Equals(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName, "zh", StringComparison.OrdinalIgnoreCase)
        };
    }

    public static string T(string chinese, string english) => IsChinese ? chinese : english;
}

public static class FolderService
{
    public static string NormalizePath(string folder)
    {
        string fullPath = Path.GetFullPath(folder);
        string trimmed = fullPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string? root = Path.GetPathRoot(fullPath);
        return !string.IsNullOrEmpty(root) &&
               string.Equals(trimmed, root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)
            ? root
            : trimmed;
    }

    public static bool TryValidate(string? folder, out string? error)
    {
        error = null;
        if (string.IsNullOrWhiteSpace(folder) || !Directory.Exists(folder))
        {
            error = Localization.T("文件夹不存在，请重新选择。", "The folder does not exist. Choose another folder.");
            return false;
        }

        try
        {
            string selected = NormalizePath(folder);
            string applicationFolder = NormalizePath(AppContext.BaseDirectory);
            if (string.Equals(selected, applicationFolder, StringComparison.OrdinalIgnoreCase) ||
                selected.StartsWith(applicationFolder + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            {
                error = Localization.T("不能将程序安装目录用作记录保存位置。", "The application folder cannot be used for session files.");
                return false;
            }

            string testPath = Path.Combine(selected, ".network-speed-logger-" + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                using var stream = new FileStream(testPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                stream.WriteByte(0);
                stream.Flush(true);
            }
            finally
            {
                try
                {
                    if (File.Exists(testPath)) File.Delete(testPath);
                }
                catch
                {
                }
            }

            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            return false;
        }
    }
}
