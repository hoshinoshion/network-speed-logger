Languages: English | [简体中文](README.zh-CN.md)

# Network Speed Logger

Network Speed Logger is a lightweight, open-source Windows and macOS utility that records the traffic actually sent and received by your computer. It includes native desktop applications and terminal scripts for both platforms.

This is a traffic logger, not an internet speed test. Internet and local-network traffic are both included.

## Download

Download the current desktop applications from the [latest release](https://github.com/hoshinoshion/network-speed-logger/releases/latest):

| Platform | File | Requirements |
| --- | --- | --- |
| macOS | `NetworkSpeedLogger.dmg` | macOS 13 or later; Apple silicon or Intel |
| Windows | `NetworkSpeedLogger.exe` | Windows 10 or 11; .NET Framework 4.8 |

No administrator privileges are required.

## macOS application

The macOS client is a native SwiftUI application designed independently for macOS. The Release build is a Universal application containing both `arm64` and `x86_64` code.

### Install

1. Open `NetworkSpeedLogger.dmg`.
2. Drag **Network Speed Logger** to the **Applications** folder.
3. Open it from Applications or Launchpad.
4. On the first launch, choose the folder where CSV samples and Markdown summaries should be saved. The app remembers this folder; it can be changed later in the sidebar or Settings.

### Unsigned application notice

The current macOS application is **not signed with an Apple Developer ID and is not notarized**. The bundle has only an ad-hoc signature for internal integrity, so Gatekeeper identifies the publisher as unknown.

If macOS blocks the first launch:

1. Try to open the application once so the warning appears.
2. Open **System Settings → Privacy & Security**.
3. Scroll to **Security** and select **Open Anyway** for Network Speed Logger.
4. Confirm by selecting **Open**.

The exception is remembered for later launches. Only bypass Gatekeeper when the DMG came from this repository's Release page and you trust the downloaded file. See [Apple's instructions for opening an app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac).

### macOS features

- Native SwiftUI interface using standard macOS controls, navigation, menus, Settings, colors, and SF Symbols.
- Automatic physical-interface detection and exclusion of loopback, VPN/tunnel, bridge, AWDL, virtual-machine, and similar virtual interfaces.
- Aggregation of multiple active physical interfaces, such as Ethernet and Wi-Fi.
- Automatic adaptation to interface connection, disconnection, USB adapter hot-plugging, and Ethernet/Wi-Fi switching while logging.
- Safe re-baselining after sleep, wake, system-clock discontinuities, and interface counter resets to prevent false speed spikes.
- Manual selection of one or more physical or virtual interfaces.
- Real-time MB/s or Mbps display, traffic totals, a 60-sample chart, recent samples, and session statistics.
- Immediate CSV writes after every sample and a Markdown summary when the session ends.
- Simplified Chinese and English, selected from the preferred macOS language by default and switchable in Settings.
- No Homebrew packages, administrator privileges, kernel extensions, or network extensions.

## Windows application

The standalone WPF application is the recommended version for most Windows users.

1. Run `NetworkSpeedLogger.exe`.
2. Choose the duration, sample interval, speed unit, adapter mode, and output folder.
3. Select **Start logging**.
4. Select **Stop logging** at any time, or let the configured duration finish.

The Windows client supports automatic physical-adapter detection, virtual-adapter exclusion, multiple-adapter aggregation, live Ethernet/Wi-Fi switching, manual adapter selection, MB/s and Mbps, live charts, session statistics, and Chinese/English UI.

## Windows PowerShell script

Requirements: Windows 10 or 11 and Windows PowerShell 5.1 or later.

Run with the defaults (24 hours, one sample every 15 seconds):

```powershell
.\windows\NetworkSpeedLogger.ps1
```

Run indefinitely and stop with `Ctrl+C` or `Q`:

```powershell
.\windows\NetworkSpeedLogger.ps1 -DurationHours 0
```

List adapters or select specific adapters:

```powershell
.\windows\NetworkSpeedLogger.ps1 -ListAdapters
.\windows\NetworkSpeedLogger.ps1 -AdapterName "Wi-Fi","Ethernet"
```

If Windows blocks local script execution:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\NetworkSpeedLogger.ps1
```

## macOS shell script

The shell version uses only built-in macOS commands and requires no administrator privileges.

```sh
chmod +x macos/NetworkSpeedLogger.sh
./macos/NetworkSpeedLogger.sh
```

Run indefinitely, list interfaces, or select multiple interfaces:

```sh
./macos/NetworkSpeedLogger.sh --duration-hours 0
./macos/NetworkSpeedLogger.sh --list-adapters
./macos/NetworkSpeedLogger.sh --adapter en0 --adapter en5
```

Run `./macos/NetworkSpeedLogger.sh --help` for every option.

## Output files

Each session creates:

- `NetworkSpeed_YYYYMMDD_HHMMSS.csv` — timestamped samples, elapsed time, download/upload speed, and active interfaces.
- `NetworkSpeed_YYYYMMDD_HHMMSS_summary.md` — duration, traffic totals, interface list, stop reason, and minimum/maximum/average speeds.

Each sample is flushed to the CSV immediately so completed data remains available if the application, terminal, or computer later stops unexpectedly. CSV speeds use decimal MB/s, where 1 MB equals 1,000,000 bytes; the applications can display the same data as MB/s or Mbps.

## Build from source

### macOS

Install the current Xcode command-line tools, then run on macOS:

```sh
bash src/macos/NetworkSpeedLogger/Scripts/build-release.sh 0.2.0
```

The script compiles `arm64` and `x86_64`, combines them into a Universal application, generates the application icon, applies an ad-hoc signature, and creates `dist/NetworkSpeedLogger.dmg`.

The source can also be opened as a Swift package using `src/macos/NetworkSpeedLogger/Package.swift`.

### Windows

Open `src/windows/NetworkSpeedLogger/NetworkSpeedLogger.csproj` in Visual Studio with the **.NET desktop development** workload, select Release, and build. The project targets .NET Framework 4.8 and has no third-party runtime dependencies.

## Repository layout

- `src/macos/NetworkSpeedLogger/` — native SwiftUI application and Universal DMG build scripts.
- `src/windows/NetworkSpeedLogger/` — Windows WPF application source and icon.
- `macos/NetworkSpeedLogger.sh` — macOS terminal version.
- `windows/NetworkSpeedLogger.ps1` — Windows PowerShell version.
- `.github/workflows/release.yml` — reproducible Windows and macOS v0.2.0 Release workflow.

## License

This project is licensed under the [MIT License](LICENSE).
