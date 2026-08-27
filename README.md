Languages: English | [简体中文](README.zh-CN.md)

# Network Speed Logger

Network Speed Logger is a lightweight Windows utility that records real-time download and upload traffic. It automatically detects connected physical network adapters, excludes common virtual adapters in automatic mode, combines traffic from multiple active physical adapters, and adapts to Ethernet/Wi-Fi changes while running.

It records the traffic actually sent and received by your computer, including both internet and local-network traffic. It is not an internet speed test.

## GUI application

The standalone GUI is the recommended version for most users.

### Download

Download `NetworkSpeedLogger.exe` from the [latest release](https://github.com/hoshinoshion/network-speed-logger/releases/latest). No installation or administrator privileges are required.

Requirements:

- Windows 10 or Windows 11
- .NET Framework 4.8

### Usage

1. Run `NetworkSpeedLogger.exe`.
2. Choose the duration, sample interval, speed unit, adapter mode, and output folder.
3. Select **Start logging**.
4. Select **Stop logging** at any time, or let the configured duration finish.

The GUI provides:

- Simplified Chinese and English, with automatic selection based on the Windows display language and a manual language selector.
- Automatic physical-adapter detection and exclusion of VPN, Hyper-V, VMware, VirtualBox, and other virtual adapters.
- Aggregation of multiple simultaneously active physical adapters.
- Automatic adaptation to Ethernet/Wi-Fi switching and newly connected physical adapters while logging.
- Manual selection of one or more physical or virtual adapters.
- Real-time download/upload speed in MB/s or Mbps.
- Elapsed and remaining time, sample count, accumulated traffic, a 60-sample chart, and the latest five samples.
- Minimum, maximum, and average download/upload speeds for the current session.
- Immediate CSV writes after every sample and a Markdown summary when the session ends.

## PowerShell script

The PowerShell version provides the same core adapter-selection, aggregation, logging, and summary behavior in a terminal-friendly form.

Requirements:

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later

Run with the defaults (24 hours, one sample every 15 seconds):

```powershell
.\powershell\NetworkSpeedLogger.ps1
```

Run indefinitely and stop manually with `Ctrl+C` or `Q`:

```powershell
.\powershell\NetworkSpeedLogger.ps1 -DurationHours 0
```

Use a 5-second interval for 2 hours:

```powershell
.\powershell\NetworkSpeedLogger.ps1 -DurationHours 2 -SampleIntervalSeconds 5
```

List adapters, then monitor selected adapters:

```powershell
.\powershell\NetworkSpeedLogger.ps1 -ListAdapters
.\powershell\NetworkSpeedLogger.ps1 -AdapterName "Wi-Fi","Ethernet"
```

Force a language instead of following the system language:

```powershell
.\powershell\NetworkSpeedLogger.ps1 -Language en-US
.\powershell\NetworkSpeedLogger.ps1 -Language zh-CN
```

If Windows blocks local script execution, start it for the current run with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\powershell\NetworkSpeedLogger.ps1
```

## Output files

Each session creates:

- `NetworkSpeed_YYYYMMDD_HHMMSS.csv` — timestamped samples, elapsed time, download/upload speed, and active adapters.
- `NetworkSpeed_YYYYMMDD_HHMMSS_summary.md` — session duration, traffic totals, adapter list, and minimum/maximum/average speeds.

Speeds stored in CSV are decimal MB/s, where 1 MB equals 1,000,000 bytes. The GUI can display the same values as MB/s or Mbps.

## Build from source

Open `src/NetworkSpeedLogger/NetworkSpeedLogger.csproj` in Visual Studio with the **.NET desktop development** workload installed, select the Release configuration, and build. The project targets .NET Framework 4.8 and has no third-party runtime dependencies.

## Repository layout

- `src/NetworkSpeedLogger/` — WPF GUI source code and application icon.
- `powershell/NetworkSpeedLogger.ps1` — PowerShell version.
- `.github/workflows/release.yml` — reproducible Windows build and release workflow.

## License

This project is licensed under the [MIT License](LICENSE).
