Languages: English | [简体中文](README.zh-CN.md)

# Network Speed Logger

Network Speed Logger is a lightweight, open-source network traffic logger for Windows and macOS. It provides native desktop applications and terminal scripts for both platforms.

It records the traffic actually sent and received by your computer, including internet and local-network traffic. It is not an internet speed test.

## Download

For most users, the desktop applications are the easiest way to get started. Download them from the [Releases page](https://github.com/hoshinoshion/network-speed-logger/releases):

| Platform | File | Requirements |
| --- | --- | --- |
| macOS | `NetworkSpeedLogger.dmg` | macOS 13 or later; Apple silicon or Intel |
| Windows | `NetworkSpeedLogger-Setup.exe` | x64 Windows 10 version 1809 or later |

Neither application requires administrator privileges.

## Desktop application features

Both desktop applications provide:

- Automatic detection of physical network interfaces and exclusion of loopback, VPN, tunnel, bridge, virtual-machine, and similar virtual interfaces.
- Combined traffic from multiple active physical interfaces, with automatic adaptation to Ethernet/Wi-Fi changes during a session.
- Manual selection of one or more physical or virtual interfaces.
- Configurable duration, sample interval, speed unit, and a remembered output folder.
- Saved launch defaults for duration, sample interval, and speed unit; main-window changes remain temporary for the current launch.
- Real-time MB/s or Mbps display, traffic totals, a 60-sample chart, recent samples, and session statistics.
- Immediate CSV writes after every sample and a Markdown summary when the session ends.
- Simplified Chinese and English, selected from the system language by default and switchable in the application.
- Light and dark appearances that follow the system by default and can be selected manually.

## macOS application

The macOS client is a native SwiftUI application designed around standard macOS controls and behavior. The Release build is a Universal application containing both `arm64` and `x86_64` code. It also safely re-baselines after sleep, wake, system-clock discontinuities, and interface counter resets to prevent false speed spikes.

### Install

1. Open `NetworkSpeedLogger.dmg`.
2. Drag **Network Speed Logger** to the **Applications** folder.
3. Open it from Applications or Launchpad.
4. Choose an output folder on first launch. The app remembers it, and you can change it later from the sidebar or Settings.

### Unsigned application notice

The current macOS application is **not signed with an Apple Developer ID and is not notarized**. It uses an ad-hoc signature for internal integrity, so Gatekeeper identifies the publisher as unknown.

If macOS blocks the first launch, try to open the app once, then go to **System Settings → Privacy & Security**, find Network Speed Logger under **Security**, and select **Open Anyway**. Confirm by selecting **Open**. macOS remembers this exception for later launches.

Only bypass Gatekeeper when the DMG came from this repository's Release page and you trust the downloaded file. See [Apple's instructions for opening an app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac).

The macOS application requires no Homebrew packages, kernel extensions, or network extensions. On macOS 26, it automatically adopts the system Liquid Glass sidebar and toolbar appearance.

## Windows application

The Windows client is installed per user with a standard setup and uninstall process:

1. Run `NetworkSpeedLogger-Setup.exe` and complete Setup. Administrator privileges are not required.
2. Open **Network Speed Logger** from the Start menu.
3. Choose an output folder on first launch. The app remembers it for future sessions.
4. Choose the current duration, sample interval, speed unit, and adapter mode, then select **Start**.
5. Select **Stop** at any time, or let the configured duration finish.

Use the Settings button to change the interface language, output folder, and launch defaults. Changes to duration, sample interval, and speed unit made directly in the main window apply only until the app is closed. Windows Settings can uninstall the application; uninstalling never removes CSV or Markdown files.

It uses WinUI 3 and ships the required .NET and Windows App SDK components in a self-contained installer, so no separate runtime installation is required. The current Windows application and installer are not code-signed, so SmartScreen may identify the publisher as unknown.

Users of an earlier portable version can install the new version normally and then delete the old standalone EXE. The saved language preference is migrated automatically.

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

Run `./macos/NetworkSpeedLogger.sh --help` for all options.

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

## Output files

Each session creates:

- `NetworkSpeed_YYYYMMDD_HHMMSS.csv` — timestamped samples, elapsed time, download/upload speed, and active interfaces.
- `NetworkSpeed_YYYYMMDD_HHMMSS_summary.md` — duration, traffic totals, interface list, stop reason, and minimum, maximum, and average speeds.

Each sample is flushed to the CSV immediately, so completed data remains available if the application, terminal, or computer later stops unexpectedly. CSV speeds use decimal MB/s, where 1 MB equals 1,000,000 bytes; the desktop applications can also display the same data as Mbps.

## Build from source

### macOS

Install the current Xcode command-line tools, then run on macOS:

```sh
bash src/macos/NetworkSpeedLogger/Scripts/build-release.sh 0.4.3
```

The script builds `arm64` and `x86_64`, combines them into a Universal application, generates the icon, applies an ad-hoc signature, and creates `dist/NetworkSpeedLogger.dmg`. You can also open `src/macos/NetworkSpeedLogger/Package.swift` as a Swift package.

### Windows

Open `src/windows/NetworkSpeedLogger.WinUI/NetworkSpeedLogger.WinUI.csproj` in Visual Studio with the **.NET desktop development** workload, select Release, and build. To create the installer, install Inno Setup 6 and compile `installer/windows/NetworkSpeedLogger.iss` after the Release build finishes.

## Repository layout

- `src/macos/NetworkSpeedLogger/` — native SwiftUI application and Universal DMG build scripts.
- `macos/NetworkSpeedLogger.sh` — macOS terminal version.
- `src/windows/NetworkSpeedLogger.WinUI/` — Windows WinUI 3 application source.
- `src/windows/NetworkSpeedLogger/` — shared Windows icon assets and archived earlier client source.
- `installer/windows/` — Inno Setup definition for the Windows installer and uninstaller.
- `windows/NetworkSpeedLogger.ps1` — Windows PowerShell version.
- `.github/workflows/release.yml` — reproducible release workflow for the current release.

## License

This project is licensed under the [MIT License](LICENSE).
