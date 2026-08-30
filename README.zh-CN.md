[English](README.md) | 简体中文

# Network Speed Logger

Network Speed Logger 是一款适用于 Windows 与 macOS 的轻量级开源网络流量记录工具，同时为两个平台提供原生桌面客户端和终端脚本。

它记录电脑实际发送和接收的流量，包括互联网和局域网流量，并不是用于测试宽带峰值速度的网络测速工具。

## 下载

对大多数用户来说，桌面客户端是最方便的使用方式。请从 [Releases 页面](https://github.com/hoshinoshion/network-speed-logger/releases)下载：

| 平台 | 文件 | 运行要求 |
| --- | --- | --- |
| macOS | `NetworkSpeedLogger.dmg` | macOS 13 或更高版本；Apple 芯片或 Intel Mac |
| Windows | `NetworkSpeedLogger-Setup.exe` | x64 Windows 10 版本 1809 或更高版本 |

两个客户端都不需要管理员权限。

## 桌面客户端功能

两个桌面客户端均支持：

- 自动识别物理网络接口，并排除回环、VPN、隧道、网桥、虚拟机等虚拟接口。
- 合并多个同时工作的物理接口流量，并在记录期间自动适应有线与 Wi-Fi 的连接变化。
- 手动选择一个或多个物理或虚拟接口。
- 设置记录时长、采样间隔、速度单位，并记住手动选择的输出文件夹。
- 为记录时长、采样间隔和速度单位保存启动默认值；主窗口中的修改只在本次启动期间有效。
- 使用 MB/s 或 Mbps 显示实时速度、累计流量、最近 60 个采样点曲线、最近采样和本次记录统计。
- 每次采样后立即写入 CSV，并在记录结束时生成 Markdown 汇总。
- 简体中文和英语界面；默认跟随系统语言，也可以在应用中手动切换。
- 浅色和深色外观；默认跟随系统，也可以手动切换。

## macOS 客户端

macOS 客户端是遵循系统控件和交互习惯设计的原生 SwiftUI 应用。Release 中提供的是同时包含 `arm64` 与 `x86_64` 的 Universal 通用程序。应用还会在 Mac 睡眠、唤醒、系统时间跳变或接口计数器重置后安全重建基线，避免产生错误的速度峰值。

### 安装方法

1. 打开 `NetworkSpeedLogger.dmg`。
2. 将 **Network Speed Logger** 拖入“应用程序”文件夹。
3. 从“应用程序”或启动台打开。
4. 首次启动时选择输出文件夹。应用会记住该文件夹，之后可以在侧边栏或设置中更改。

### 未签名应用说明

当前 macOS 客户端**没有使用 Apple Developer ID 签名，也没有经过 Apple 公证**。应用包只使用了用于保证内部完整性的临时签名，因此 Gatekeeper 会将开发者识别为未知。

如果 macOS 阻止首次启动，请先尝试打开一次应用，然后前往“**系统设置 → 隐私与安全性**”，在“安全性”中找到 Network Speed Logger 并点击“**仍要打开**”，再确认“打开”。macOS 会记住这次例外，之后可以正常启动。

请仅在 DMG 来自本仓库 Release 页面且你信任该文件时绕过 Gatekeeper。也可以参考 [Apple 关于打开未知开发者应用的说明](https://support.apple.com/zh-cn/guide/mac-help/mh40616/mac)。

macOS 客户端不依赖 Homebrew，也不需要内核扩展或网络扩展；在 macOS 26 上会自动采用系统 Liquid Glass 侧边栏与工具栏外观。

## Windows 客户端

Windows 客户端采用当前用户安装方式，具有标准的安装和卸载流程：

1. 运行 `NetworkSpeedLogger-Setup.exe` 并完成安装，不需要管理员权限。
2. 从开始菜单打开 **Network Speed Logger**。
3. 首次启动时选择输出文件夹，应用会在以后自动恢复该位置。
4. 设置本次记录的时长、采样间隔、速度单位和网卡模式，然后点击“开始”。
5. 随时点击“结束”，或等待设定时长结束。

通过“设置”可以更改界面语言、输出文件夹以及每次启动时载入的默认配置。直接在主窗口修改记录时长、采样间隔和速度单位，只在关闭应用前有效。可以从 Windows“设置”中卸载应用，卸载不会删除 CSV 或 Markdown 记录文件。

客户端使用 WinUI 3，并在安装包中自带所需的 .NET 和 Windows App SDK 组件，无需另外安装运行库。当前 Windows 客户端和安装器没有代码签名，因此 SmartScreen 可能将发布者显示为未知。

旧版单体 EXE 用户可以直接安装新版，然后手动删除原来的 EXE；旧版保存的语言选择会自动迁移。

## macOS Shell 脚本

Shell 版本只使用 macOS 系统自带命令，不需要管理员权限。

```sh
chmod +x macos/NetworkSpeedLogger.sh
./macos/NetworkSpeedLogger.sh
```

不限时运行、列出接口或选择多个接口：

```sh
./macos/NetworkSpeedLogger.sh --duration-hours 0
./macos/NetworkSpeedLogger.sh --list-adapters
./macos/NetworkSpeedLogger.sh --adapter en0 --adapter en5
```

运行 `./macos/NetworkSpeedLogger.sh --help` 可以查看全部选项。

## Windows PowerShell 脚本

运行要求：Windows 10 或 11，以及 Windows PowerShell 5.1 或更高版本。

使用默认设置运行 24 小时，每 15 秒采样一次：

```powershell
.\windows\NetworkSpeedLogger.ps1
```

不限时运行，使用 `Ctrl+C` 或 `Q` 手动结束：

```powershell
.\windows\NetworkSpeedLogger.ps1 -DurationHours 0
```

列出网卡或手动选择网卡：

```powershell
.\windows\NetworkSpeedLogger.ps1 -ListAdapters
.\windows\NetworkSpeedLogger.ps1 -AdapterName "Wi-Fi","Ethernet"
```

如果 Windows 阻止本地脚本执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\NetworkSpeedLogger.ps1
```

## 输出文件

每次记录会生成：

- `NetworkSpeed_YYYYMMDD_HHMMSS.csv`：带时间戳的采样数据、已运行时间、下载与上传速度以及活动接口。
- `NetworkSpeed_YYYYMMDD_HHMMSS_summary.md`：记录时长、累计流量、接口列表、结束原因以及最小、最大和平均速度。

每次采样都会立即刷新到 CSV，因此即使应用、终端或电脑之后意外停止，已经完成的采样数据仍会保留。CSV 中的速度使用十进制 MB/s，即 1 MB 等于 1,000,000 字节；桌面客户端也可以将同一数据换算为 Mbps 显示。

## 从源代码编译

### macOS

安装当前版本的 Xcode 命令行工具，然后在 macOS 上运行：

```sh
bash src/macos/NetworkSpeedLogger/Scripts/build-release.sh 0.5.0
```

脚本会分别编译 `arm64` 和 `x86_64`、合并为 Universal 应用、生成图标、应用临时签名，并创建 `dist/NetworkSpeedLogger.dmg`。也可以通过 `src/macos/NetworkSpeedLogger/Package.swift` 将源代码作为 Swift Package 打开。

### Windows

在安装了“.NET 桌面开发”工作负载的 Visual Studio 中打开 `src/windows/NetworkSpeedLogger.WinUI/NetworkSpeedLogger.WinUI.csproj`，选择 Release 配置并生成。若要创建安装器，请安装 Inno Setup 6，并在 Release 构建完成后编译 `installer/windows/NetworkSpeedLogger.iss`。

## 仓库结构

- `src/macos/NetworkSpeedLogger/`：原生 SwiftUI 客户端和 Universal DMG 构建脚本。
- `macos/NetworkSpeedLogger.sh`：macOS 终端版本。
- `src/windows/NetworkSpeedLogger.WinUI/`：Windows WinUI 3 客户端源代码。
- `src/windows/NetworkSpeedLogger/`：Windows 共用图标资源和归档的早期客户端源代码。
- `installer/windows/`：Windows 安装器和卸载程序的 Inno Setup 配置。
- `windows/NetworkSpeedLogger.ps1`：Windows PowerShell 版本。
- `.github/workflows/release.yml`：当前版本使用的可复现 Release 工作流。

## 开源协议

本项目采用 [MIT License](LICENSE)。
