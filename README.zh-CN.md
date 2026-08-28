[English](README.md) | 简体中文

# Network Speed Logger

Network Speed Logger 是一款轻量级的开源 Windows 与 macOS 实时网速记录工具，同时提供两个平台的桌面客户端和终端脚本。

本工具统计的是电脑网卡实际收发的流量，包括互联网和局域网流量，并不是连接测速服务器测试宽带峰值速度的工具。

## 下载

从[最新 Release](https://github.com/hoshinoshion/network-speed-logger/releases/latest)下载桌面客户端：

| 平台 | 文件 | 运行要求 |
| --- | --- | --- |
| macOS | `NetworkSpeedLogger.dmg` | macOS 13 或更高版本；Apple 芯片或 Intel Mac |
| Windows | `NetworkSpeedLogger.exe` | Windows 10 或 11；.NET Framework 4.8 |

两个客户端都不需要管理员权限。

## macOS 客户端

macOS 客户端是使用 SwiftUI 独立开发的原生应用，界面和交互遵循 macOS 的设计习惯。Release 中提供的是同时包含 `arm64` 与 `x86_64` 的 Universal 通用程序。

### 安装方法

1. 打开 `NetworkSpeedLogger.dmg`。
2. 将 **Network Speed Logger** 拖入“应用程序”文件夹。
3. 从“应用程序”或启动台打开。
4. 首次启动时选择 CSV 采样和 Markdown 汇总的保存文件夹。应用会记住该文件夹，之后也可以在侧边栏或设置中更改。

### 未签名应用说明

当前 macOS 客户端**没有使用 Apple Developer ID 签名，也没有经过 Apple 公证**。应用包只使用了用于保证内部完整性的临时签名，因此 Gatekeeper 会将开发者识别为未知。

如果 macOS 在首次启动时阻止运行：

1. 先尝试打开一次应用，让系统显示安全警告。
2. 打开“**系统设置 → 隐私与安全性**”。
3. 向下滚动到“安全性”，找到 Network Speed Logger 并点击“**仍要打开**”。
4. 在再次出现的窗口中确认“打开”。

完成后，macOS 会记住这次例外，之后可以正常双击运行。请仅在 DMG 来自本仓库 Release 页面且你信任该文件时绕过 Gatekeeper。也可以参考 [Apple 关于打开未知开发者应用的说明](https://support.apple.com/zh-cn/guide/mac-help/mh40616/mac)。

### macOS 客户端功能

- 使用标准 macOS 控件、导航、完整本地化菜单、设置、系统颜色和 SF Symbols 的原生 SwiftUI 界面；在 macOS 26 上自动采用系统 Liquid Glass 侧边栏与工具栏外观。
- 自动识别物理网络接口，并排除回环、VPN/隧道、网桥、AWDL、虚拟机等虚拟接口。
- 合并多个同时工作的物理接口流量，例如同时连接的以太网和 Wi-Fi。
- 记录期间自动适应接口连接、断开、USB 网卡热插拔以及有线/Wi-Fi 切换。
- 在 Mac 睡眠、唤醒、系统时间跳变或接口计数器重置后安全重建基线，避免产生错误的速度峰值。
- 支持手动选择一个或多个物理或虚拟接口。
- 记录时长和采样间隔既可直接填写，也可使用步进按钮；设置中可以配置时长、间隔和速度单位的启动默认值。
- 使用 MB/s 或 Mbps 显示实时速度、累计流量、最近 60 个采样点曲线、最近采样和本次记录统计。
- 每次采样后立即写入 CSV，并在记录结束时生成 Markdown 汇总。
- 支持简体中文和英语；默认根据 macOS 首选语言选择，也可在设置中手动切换。
- 不依赖 Homebrew，不需要管理员权限、内核扩展或网络扩展。

## Windows 客户端

对于大多数 Windows 用户，推荐使用可以直接运行的 WPF 客户端。

1. 运行 `NetworkSpeedLogger.exe`。
2. 设置记录时长、采样间隔、速度单位、网卡模式和结果保存位置。
3. 点击“开始记录”。
4. 随时点击“结束记录”，或等待设定时长结束。

Windows 客户端支持自动识别物理网卡、排除虚拟网卡、合并多个网卡、运行期间适应有线/Wi-Fi 切换、手动选择网卡、MB/s 与 Mbps、实时曲线、记录统计以及中英文界面。

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

## 输出文件

每次记录会生成：

- `NetworkSpeed_YYYYMMDD_HHMMSS.csv`：带时间戳的采样数据、已运行时间、下载和上传速度及活动接口。
- `NetworkSpeed_YYYYMMDD_HHMMSS_summary.md`：记录时长、累计流量、接口列表、结束原因以及最小、最大和平均速度。

每次采样都会立即刷新到 CSV，因此即使应用、终端或电脑之后意外停止，已经完成的采样数据仍会保留。CSV 中的速度使用十进制 MB/s，即 1 MB 等于 1,000,000 字节；客户端可以将同一数据换算为 MB/s 或 Mbps 显示。

## 从源代码编译

### macOS

安装当前版本的 Xcode 命令行工具，然后在 macOS 上运行：

```sh
bash src/macos/NetworkSpeedLogger/Scripts/build-release.sh 0.2.1
```

脚本会分别编译 `arm64` 和 `x86_64`、合并为 Universal 应用、生成应用图标、应用临时签名，并创建 `dist/NetworkSpeedLogger.dmg`。

也可以通过 `src/macos/NetworkSpeedLogger/Package.swift` 将源代码作为 Swift Package 打开。

### Windows

在安装了“.NET 桌面开发”工作负载的 Visual Studio 中打开 `src/windows/NetworkSpeedLogger/NetworkSpeedLogger.csproj`，选择 Release 配置并生成。项目目标为 .NET Framework 4.8，不依赖第三方运行库。

## 仓库结构

- `src/macos/NetworkSpeedLogger/`：原生 SwiftUI 客户端和 Universal DMG 构建脚本。
- `src/windows/NetworkSpeedLogger/`：Windows WPF 客户端源代码和图标。
- `macos/NetworkSpeedLogger.sh`：macOS 终端版本。
- `windows/NetworkSpeedLogger.ps1`：Windows PowerShell 版本。
- `.github/workflows/release.yml`：可复现的 Windows 与 macOS v0.2.1 Release 工作流。

## 开源协议

本项目采用 [MIT License](LICENSE)。
