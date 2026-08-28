Languages: English | [简体中文](README.zh-CN.md)

# Network Speed Logger

Network Speed Logger is a lightweight Windows and macOS utility that records real-time download and upload traffic. In automatic mode, it detects connected physical network adapters, excludes common virtual adapters, combines traffic from multiple active physical adapters, and adapts to Ethernet/Wi-Fi changes while running.

It records the traffic actually sent and received by your computer, including both internet and local-network traffic. It is not an internet speed test.

## Windows GUI application

The standalone GUI is the recommended version for most Windows users.

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

## Windows PowerShell script

The PowerShell version provides the same core adapter-selection, aggregation, logging, and summary behavior in a terminal-friendly form.

Requirements:

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later

Run with the defaults (24 hours, one sample every 15 seconds):

```powershell
.\windows\NetworkSpeedLogger.ps1
```

Run indefinitely and stop manually with `Ctrl+C` or `Q`:

```powershell
.\windows\NetworkSpeedLogger.ps1 -DurationHours 0
```

Use a 5-second interval for 2 hours:

```powershell
.\windows\NetworkSpeedLogger.ps1 -DurationHours 2 -SampleIntervalSeconds 5
```

List adapters, then monitor selected adapters:

```powershell
.\windows\NetworkSpeedLogger.ps1 -ListAdapters
.\windows\NetworkSpeedLogger.ps1 -AdapterName "Wi-Fi","Ethernet"
```

Force a language instead of following the system language:

```powershell
.\windows\NetworkSpeedLogger.ps1 -Language en-US
.\windows\NetworkSpeedLogger.ps1 -Language zh-CN
```

If Windows blocks local script execution, start it for the current run with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\NetworkSpeedLogger.ps1
```

## macOS shell script

The macOS version uses only built-in system commands. It requires no Homebrew packages or administrator privileges and works on both Apple silicon and Intel Macs.

Make the script executable once, then run it with the defaults (24 hours, one sample every 15 seconds):

```sh
chmod +x macos/NetworkSpeedLogger.sh
./macos/NetworkSpeedLogger.sh
```

Run indefinitely and stop manually with `Ctrl+C` or `Q`:

```sh
./macos/NetworkSpeedLogger.sh --duration-hours 0
```

Use a 5-second interval for 2 hours:

```sh
./macos/NetworkSpeedLogger.sh --duration-hours 2 --sample-interval-seconds 5
```

List interfaces, then monitor selected interfaces by their BSD names:

```sh
./macos/NetworkSpeedLogger.sh --list-adapters
./macos/NetworkSpeedLogger.sh --adapter en0 --adapter en5
```

Manual selection also permits virtual interfaces such as a specific `utun` interface. In automatic mode, the script monitors active hardware ports and excludes loopback, VPN/tunnel, bridge, AWDL, virtual-machine, and similar virtual interfaces.

Force a language instead of following the first preferred macOS language:

```sh
./macos/NetworkSpeedLogger.sh --language en-US
./macos/NetworkSpeedLogger.sh --language zh-CN
```

Run `./macos/NetworkSpeedLogger.sh --help` to see all options.

## Output files

Each session creates:

- `NetworkSpeed_YYYYMMDD_HHMMSS.csv` — timestamped samples, elapsed time, download/upload speed, and active adapters.
- `NetworkSpeed_YYYYMMDD_HHMMSS_summary.md` — session duration, traffic totals, adapter list, and minimum/maximum/average speeds.

The PowerShell and macOS scripts save these files beside the script. The GUI saves them in the selected output folder. Each sample is appended to the CSV immediately so completed data remains available if the computer or terminal later stops unexpectedly.

Speeds stored in CSV are decimal MB/s, where 1 MB equals 1,000,000 bytes. The GUI can display the same values as MB/s or Mbps.

## Build from source

Open `src/NetworkSpeedLogger/NetworkSpeedLogger.csproj` in Visual Studio with the **.NET desktop development** workload installed, select the Release configuration, and build. The project targets .NET Framework 4.8 and has no third-party runtime dependencies.

## Repository layout

- `src/NetworkSpeedLogger/` — Windows WPF GUI source code and application icon.
- `windows/NetworkSpeedLogger.ps1` — Windows PowerShell version.
- `macos/NetworkSpeedLogger.sh` — macOS shell version.
- `.github/workflows/release.yml` — reproducible Windows build and release workflow.

## License

This project is licensed under the [MIT License](LICENSE).
