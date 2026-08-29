using System;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;

namespace NetworkSpeedLogger
{
    [DataContract]
    internal sealed class SessionDefaults
    {
        [DataMember(Name = "durationHours", Order = 0)]
        public double DurationHours { get; set; }

        [DataMember(Name = "sampleIntervalSeconds", Order = 1)]
        public int SampleIntervalSeconds { get; set; }

        [DataMember(Name = "speedUnit", Order = 2)]
        public string SpeedUnit { get; set; }

        internal SessionDefaults Clone()
        {
            return new SessionDefaults
            {
                DurationHours = DurationHours,
                SampleIntervalSeconds = SampleIntervalSeconds,
                SpeedUnit = SpeedUnit
            };
        }
    }

    [DataContract]
    internal sealed class AppSettingsData
    {
        [DataMember(Name = "schemaVersion", Order = 0)]
        public int SchemaVersion { get; set; }

        [DataMember(Name = "language", Order = 1)]
        public string Language { get; set; }

        [DataMember(Name = "outputFolder", Order = 2)]
        public string OutputFolder { get; set; }

        [DataMember(Name = "defaults", Order = 3)]
        public SessionDefaults Defaults { get; set; }

        internal AppSettingsData Clone()
        {
            return new AppSettingsData
            {
                SchemaVersion = SchemaVersion,
                Language = Language,
                OutputFolder = OutputFolder,
                Defaults = Defaults == null ? null : Defaults.Clone()
            };
        }
    }

    internal static class AppSettingsStore
    {
        internal const double MinimumDurationHours = 0;
        internal const double MaximumDurationHours = 8760;
        internal const int MinimumSampleIntervalSeconds = 1;
        internal const int MaximumSampleIntervalSeconds = 3600;

        private static string SettingsFolder
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "NetworkSpeedLogger");
            }
        }

        internal static string SettingsPath
        {
            get { return Path.Combine(SettingsFolder, "settings.json"); }
        }

        private static string LegacyLanguagePath
        {
            get { return Path.Combine(SettingsFolder, "language.txt"); }
        }

        internal static AppSettingsData Load()
        {
            AppSettingsData settings = null;
            try
            {
                if (File.Exists(SettingsPath))
                {
                    var serializer = new DataContractJsonSerializer(typeof(AppSettingsData));
                    using (var stream = File.OpenRead(SettingsPath))
                    {
                        settings = serializer.ReadObject(stream) as AppSettingsData;
                    }
                }
            }
            catch
            {
                settings = null;
            }

            if (settings == null)
            {
                settings = CreateDefaults();
                settings.Language = LoadLegacyLanguage();
            }

            Normalize(settings);
            return settings;
        }

        internal static bool TrySave(AppSettingsData settings, out string error)
        {
            error = null;
            if (settings == null)
            {
                error = "Settings are unavailable.";
                return false;
            }

            Normalize(settings);
            string temporaryPath = null;
            try
            {
                Directory.CreateDirectory(SettingsFolder);
                temporaryPath = SettingsPath + ".tmp";

                var serializer = new DataContractJsonSerializer(typeof(AppSettingsData));
                using (var stream = new FileStream(temporaryPath, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    serializer.WriteObject(stream, settings);
                    stream.Flush(true);
                }

                if (File.Exists(SettingsPath))
                {
                    string backupPath = SettingsPath + ".bak";
                    bool replaced = false;
                    try
                    {
                        File.Replace(temporaryPath, SettingsPath, backupPath, true);
                        replaced = true;
                    }
                    catch
                    {
                        File.Copy(temporaryPath, SettingsPath, true);
                        File.Delete(temporaryPath);
                    }
                    if (replaced)
                    {
                        try
                        {
                            if (File.Exists(backupPath)) File.Delete(backupPath);
                        }
                        catch
                        {
                        }
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

        internal static AppSettingsData CreateDefaults()
        {
            return new AppSettingsData
            {
                SchemaVersion = 1,
                Language = "Auto",
                OutputFolder = string.Empty,
                Defaults = new SessionDefaults
                {
                    DurationHours = 24,
                    SampleIntervalSeconds = 15,
                    SpeedUnit = "MB/s"
                }
            };
        }

        internal static bool IsValidLanguage(string value)
        {
            return value == "Auto" || value == "zh-CN" || value == "en-US";
        }

        internal static bool IsValidSpeedUnit(string value)
        {
            return value == "MB/s" || value == "Mbps";
        }

        internal static bool IsValidDuration(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value) &&
                   value >= MinimumDurationHours && value <= MaximumDurationHours;
        }

        internal static bool IsValidSampleInterval(int value)
        {
            return value >= MinimumSampleIntervalSeconds && value <= MaximumSampleIntervalSeconds;
        }

        private static void Normalize(AppSettingsData settings)
        {
            AppSettingsData builtIn = CreateDefaults();
            settings.SchemaVersion = 1;
            if (!IsValidLanguage(settings.Language)) settings.Language = builtIn.Language;
            settings.OutputFolder = (settings.OutputFolder ?? string.Empty).Trim();
            if (settings.Defaults == null) settings.Defaults = builtIn.Defaults;
            if (!IsValidDuration(settings.Defaults.DurationHours)) settings.Defaults.DurationHours = builtIn.Defaults.DurationHours;
            if (!IsValidSampleInterval(settings.Defaults.SampleIntervalSeconds)) settings.Defaults.SampleIntervalSeconds = builtIn.Defaults.SampleIntervalSeconds;
            if (!IsValidSpeedUnit(settings.Defaults.SpeedUnit)) settings.Defaults.SpeedUnit = builtIn.Defaults.SpeedUnit;
        }

        private static string LoadLegacyLanguage()
        {
            try
            {
                string value = File.ReadAllText(LegacyLanguagePath, Encoding.UTF8).Trim();
                if (IsValidLanguage(value)) return value;
            }
            catch
            {
            }
            return "Auto";
        }
    }
}
