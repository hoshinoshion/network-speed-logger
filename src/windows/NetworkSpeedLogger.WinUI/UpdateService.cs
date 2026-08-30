using System.Net.Http.Headers;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NetworkSpeedLogger;

public enum UpdateCheckStatus
{
    UpToDate,
    UpdateAvailable,
    Failed
}

public sealed record UpdateReleaseInfo(string Version, Uri ReleasePage, DateTimeOffset? PublishedAt);

public sealed record UpdateCheckResult(
    UpdateCheckStatus Status,
    UpdateReleaseInfo? Release = null);

public sealed class UpdateService
{
    private const string LatestReleaseUrl =
        "https://api.github.com/repos/hoshinoshion/network-speed-logger/releases/latest";
    private const string InstallerAssetName = "NetworkSpeedLogger-Setup.exe";
    private static readonly TimeSpan SuccessfulCheckInterval = TimeSpan.FromHours(24);
    private static readonly TimeSpan FailedCheckRetryInterval = TimeSpan.FromHours(1);
    private static readonly TimeSpan ReminderInterval = TimeSpan.FromDays(7);
    private static readonly HttpClient Client = CreateHttpClient();

    private static readonly SemaphoreSlim CheckGate = new(1, 1);

    public static Version CurrentVersion =>
        Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0, 0);

    public static string CurrentVersionText
    {
        get
        {
            Version version = CurrentVersion;
            return $"{version.Major}.{version.Minor}.{Math.Max(version.Build, 0)}";
        }
    }

    public async Task<UpdateCheckResult?> CheckAsync(bool manual, CancellationToken cancellationToken)
    {
        if (!manual && !AutomaticCheckIsDue()) return null;

        await CheckGate.WaitAsync(cancellationToken);
        try
        {
            if (!manual && !AutomaticCheckIsDue()) return null;

            UpdateState state = UpdateStateStore.Load();
            state.LastAttemptUtc = DateTimeOffset.UtcNow;
            UpdateStateStore.Save(state);

            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, LatestReleaseUrl);
                request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
                request.Headers.Add("X-GitHub-Api-Version", "2022-11-28");

                using HttpResponseMessage response = await Client.SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    cancellationToken);
                response.EnsureSuccessStatusCode();

                await using Stream stream = await response.Content.ReadAsStreamAsync(cancellationToken);
                ReleaseResponse? payload = await JsonSerializer.DeserializeAsync<ReleaseResponse>(
                    stream,
                    cancellationToken: cancellationToken);

                if (payload is null ||
                    payload.Assets.All(asset => asset.Name != InstallerAssetName) ||
                    !TryParseVersion(payload.TagName, out Version latestVersion) ||
                    !IsTrustedReleasePage(payload.PageUrl, out Uri releasePage))
                {
                    return new UpdateCheckResult(UpdateCheckStatus.Failed);
                }

                state.LastSuccessfulCheckUtc = DateTimeOffset.UtcNow;
                UpdateStateStore.Save(state);

                if (latestVersion <= CurrentVersion)
                    return new UpdateCheckResult(UpdateCheckStatus.UpToDate);

                string displayVersion =
                    $"{latestVersion.Major}.{latestVersion.Minor}.{Math.Max(latestVersion.Build, 0)}";
                return new UpdateCheckResult(
                    UpdateCheckStatus.UpdateAvailable,
                    new UpdateReleaseInfo(displayVersion, releasePage, payload.PublishedAt));
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                return new UpdateCheckResult(UpdateCheckStatus.Failed);
            }
        }
        finally
        {
            CheckGate.Release();
        }
    }

    public bool ShouldPresentAutomatically(UpdateReleaseInfo release)
    {
        UpdateState state = UpdateStateStore.Load();
        if (!string.Equals(state.LastRemindedVersion, release.Version, StringComparison.OrdinalIgnoreCase) ||
            state.LastReminderUtc is null)
            return true;
        return DateTimeOffset.UtcNow - state.LastReminderUtc.Value >= ReminderInterval;
    }

    public void MarkReminded(UpdateReleaseInfo release)
    {
        UpdateState state = UpdateStateStore.Load();
        state.LastRemindedVersion = release.Version;
        state.LastReminderUtc = DateTimeOffset.UtcNow;
        UpdateStateStore.Save(state);
    }

    private static bool AutomaticCheckIsDue()
    {
        UpdateState state = UpdateStateStore.Load();
        DateTimeOffset now = DateTimeOffset.UtcNow;
        if (state.LastSuccessfulCheckUtc is not null &&
            now - state.LastSuccessfulCheckUtc.Value < SuccessfulCheckInterval)
            return false;
        if (state.LastAttemptUtc is not null &&
            now - state.LastAttemptUtc.Value < FailedCheckRetryInterval)
            return false;
        return true;
    }

    private static bool TryParseVersion(string tagName, out Version version)
    {
        string normalized = tagName.Trim();
        if (normalized.StartsWith('v') || normalized.StartsWith('V'))
            normalized = normalized[1..];
        if (Version.TryParse(normalized, out Version? parsed) && parsed is not null)
        {
            version = parsed;
            return true;
        }
        version = null!;
        return false;
    }

    private static bool IsTrustedReleasePage(string value, out Uri uri)
    {
        uri = null!;
        if (!Uri.TryCreate(value, UriKind.Absolute, out Uri? candidate)) return false;
        if (candidate.Scheme != Uri.UriSchemeHttps ||
            !string.Equals(candidate.Host, "github.com", StringComparison.OrdinalIgnoreCase) ||
            !candidate.AbsolutePath.StartsWith(
                "/hoshinoshion/network-speed-logger/releases/",
                StringComparison.OrdinalIgnoreCase))
            return false;
        uri = candidate;
        return true;
    }

    private static HttpClient CreateHttpClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("NetworkSpeedLogger-Windows");
        return client;
    }

    private sealed class ReleaseResponse
    {
        [JsonPropertyName("tag_name")]
        public string TagName { get; set; } = string.Empty;

        [JsonPropertyName("html_url")]
        public string PageUrl { get; set; } = string.Empty;

        [JsonPropertyName("published_at")]
        public DateTimeOffset? PublishedAt { get; set; }

        [JsonPropertyName("assets")]
        public List<ReleaseAsset> Assets { get; set; } = [];
    }

    private sealed class ReleaseAsset
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;
    }
}

internal sealed class UpdateState
{
    public DateTimeOffset? LastSuccessfulCheckUtc { get; set; }
    public DateTimeOffset? LastAttemptUtc { get; set; }
    public string LastRemindedVersion { get; set; } = string.Empty;
    public DateTimeOffset? LastReminderUtc { get; set; }
}

internal static class UpdateStateStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private static string StatePath => Path.Combine(AppSettingsStore.SettingsFolder, "update-state.json");

    public static UpdateState Load()
    {
        try
        {
            if (File.Exists(StatePath))
                return JsonSerializer.Deserialize<UpdateState>(File.ReadAllText(StatePath)) ?? new UpdateState();
        }
        catch
        {
        }
        return new UpdateState();
    }

    public static void Save(UpdateState state)
    {
        try
        {
            Directory.CreateDirectory(AppSettingsStore.SettingsFolder);
            string temporaryPath = StatePath + ".tmp";
            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(state, JsonOptions));
            File.Move(temporaryPath, StatePath, true);
        }
        catch
        {
        }
    }
}
