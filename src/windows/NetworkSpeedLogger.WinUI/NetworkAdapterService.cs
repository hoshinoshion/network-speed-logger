using System.Management;
using System.Net.NetworkInformation;

namespace NetworkSpeedLogger;

public sealed class NetworkAdapterService
{
    private HashSet<string> _physicalAdapterIds = new(StringComparer.OrdinalIgnoreCase);

    public bool PhysicalDetectionFallback { get; private set; }

    public IReadOnlySet<string> PhysicalAdapterIds => _physicalAdapterIds;

    public IReadOnlyList<AdapterChoice> GetChoices(IReadOnlySet<string>? previouslySelected = null)
    {
        RefreshPhysicalAdapterIds();
        NetworkInterface[] adapters = NetworkInterface.GetAllNetworkInterfaces()
            .Where(item => item.NetworkInterfaceType is not NetworkInterfaceType.Loopback and not NetworkInterfaceType.Tunnel)
            .OrderByDescending(item => item.OperationalStatus == OperationalStatus.Up)
            .ThenBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();

        bool hasPreviousSelection = previouslySelected is not null;
        return adapters.Select(adapter =>
        {
            string id = NormalizeId(adapter.Id);
            bool physical = _physicalAdapterIds.Contains(id);
            bool connected = adapter.OperationalStatus == OperationalStatus.Up;
            bool selected = hasPreviousSelection
                ? previouslySelected!.Contains(id)
                : physical && connected;
            string state = connected ? Localization.T("已连接", "Connected") : Localization.T("未连接", "Disconnected");
            string kind = physical ? Localization.T("物理网卡", "Physical") : Localization.T("虚拟/其他", "Virtual/other");
            string description = string.IsNullOrWhiteSpace(adapter.Description)
                ? adapter.NetworkInterfaceType.ToString()
                : adapter.Description;
            return new AdapterChoice(id, adapter.Name, state + " · " + kind + " · " + description, physical, connected, selected);
        }).ToArray();
    }

    public void RefreshPhysicalAdapterIds()
    {
        _physicalAdapterIds = DetectPhysicalAdapters(out bool fallback);
        PhysicalDetectionFallback = fallback;
    }

    public List<NetworkInterface> ResolveActiveAdapters(bool manualMode, IReadOnlyCollection<string> selectedAdapterIds)
    {
        HashSet<string> allowedIds = manualMode
            ? new HashSet<string>(selectedAdapterIds, StringComparer.OrdinalIgnoreCase)
            : _physicalAdapterIds;

        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(item => item.OperationalStatus == OperationalStatus.Up &&
                           item.NetworkInterfaceType is not NetworkInterfaceType.Loopback and not NetworkInterfaceType.Tunnel &&
                           allowedIds.Contains(NormalizeId(item.Id)))
            .OrderBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    public static Dictionary<string, CounterSnapshot> SnapshotAdapters(IEnumerable<NetworkInterface> adapters)
    {
        var result = new Dictionary<string, CounterSnapshot>(StringComparer.OrdinalIgnoreCase);
        foreach (NetworkInterface adapter in adapters)
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

    public static string NormalizeId(string? id) =>
        (id ?? string.Empty).Trim().Trim('{', '}').ToUpperInvariant();

    private static HashSet<string> DetectPhysicalAdapters(out bool fallback)
    {
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        fallback = false;
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT GUID, PhysicalAdapter FROM Win32_NetworkAdapter WHERE PhysicalAdapter = TRUE");
            using ManagementObjectCollection objects = searcher.Get();
            foreach (ManagementObject item in objects)
            {
                string? guid = item["GUID"] as string;
                if (!string.IsNullOrWhiteSpace(guid)) result.Add(NormalizeId(guid));
            }
        }
        catch
        {
            fallback = true;
        }

        if (result.Count > 0) return result;

        fallback = true;
        foreach (NetworkInterface adapter in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (IsLikelyPhysical(adapter)) result.Add(NormalizeId(adapter.Id));
        }
        return result;
    }

    private static bool IsLikelyPhysical(NetworkInterface adapter)
    {
        string text = (adapter.Name + " " + adapter.Description).ToLowerInvariant();
        string[] virtualWords = ["virtual", "vmware", "hyper-v", "vethernet", "vpn", " tap", "tun", "wsl", "docker", "loopback"];
        if (virtualWords.Any(text.Contains)) return false;

        return adapter.NetworkInterfaceType is
            NetworkInterfaceType.Ethernet or
            NetworkInterfaceType.Ethernet3Megabit or
            NetworkInterfaceType.FastEthernetFx or
            NetworkInterfaceType.FastEthernetT or
            NetworkInterfaceType.GigabitEthernet or
            NetworkInterfaceType.Wireless80211 or
            NetworkInterfaceType.Wman or
            NetworkInterfaceType.Wwanpp or
            NetworkInterfaceType.Wwanpp2;
    }
}

public sealed class CounterSnapshot
{
    public CounterSnapshot(NetworkInterface adapter, long received, long sent)
    {
        Adapter = adapter;
        Received = received;
        Sent = sent;
    }

    public NetworkInterface Adapter { get; }
    public long Received { get; }
    public long Sent { get; }
}
