[English](README.md) | 简体中文

# Network Speed Logger

Network Speed Logger 是一款轻量级的 Windows 与 macOS 实时网速记录工具。自动模式会检测已连接的物理网卡、排除常见虚拟网卡、合并多个同时工作的物理网卡流量，并在记录过程中自动适应有线与 Wi-Fi 切换。

本工具统计的是电脑网卡实际收发的流量，包含互联网和局域网流量，并不是连接测速服务器测试宽带峰值速度的工具。

## Windows GUI 程序

对于大多数 Windows 用户，推荐使用可以直接运行的 GUI 版本。

### 下载

从 [最新 Release](https://github.com/hoshinoshion/network-speed-logger/releases/latest) 下载 `NetworkSpeedLogger.exe`。程序无需安装，也不需要管理员权限。

运行要求：

- Windows 10 或 Windows 11
- .NET Framework 4.8

### 使用方法

1. 运行 `NetworkSpeedLogger.exe`。
2. 设置记录时长、采样间隔、速度单位、网卡模式和结果保存位置。
3. 点击“开始记录”。
4. 随时点击“结束记录”，或等待设定时长结束。

GUI 版本支持：

- 简体中文和英语；首次启动根据 Windows 显示语言自动选择，也可手动切换语言。
- 自动识别物理网卡，并排除 VPN、Hyper-V、VMware、VirtualBox 等虚拟网卡。
- 合并多个同时工作的物理网卡流量。
- 记录期间自动适应有线与 Wi-Fi 切换，并发现新连接的物理网卡。
- 手动选择一个或多个物理或虚拟网卡。
- 使用 MB/s 或 Mbps 显示实时下载和上传速度。
- 显示已运行时间、剩余时间、样本数、累计流量、最近 60 个采样点曲线和最近 5 条采样。
- 实时计算本次记录的最小、最大和平均下载、上传速度。
- 每次采样后立即写入 CSV，并在记录结束时生成 Markdown 汇总。

## Windows PowerShell 脚本

PowerShell 版本提供与 GUI 版本相同的核心网卡识别、流量合并、记录和汇总能力，适合终端与自动化场景。

运行要求：

- Windows 10 或 Windows 11
- Windows PowerShell 5.1 或更高版本

使用默认设置运行 24 小时，每 15 秒采样一次：

```powershell
.\powershell\NetworkSpeedLogger.ps1
```

不限时运行，使用 `Ctrl+C` 或 `Q` 手动结束：

```powershell
.\powershell\NetworkSpeedLogger.ps1 -DurationHours 0
```

运行 2 小时，每 5 秒采样一次：

```powershell
.\powershell\NetworkSpeedLogger.ps1 -DurationHours 2 -SampleIntervalSeconds 5
```

列出网卡，然后只监控指定网卡：

```powershell
.\powershell\NetworkSpeedLogger.ps1 -ListAdapters
.\powershell\NetworkSpeedLogger.ps1 -AdapterName "Wi-Fi","Ethernet"
```

手动指定语言：

```powershell
.\powershell\NetworkSpeedLogger.ps1 -Language en-US
.\powershell\NetworkSpeedLogger.ps1 -Language zh-CN
```

如果 Windows 阻止本地脚本执行，可以仅为本次运行绕过执行策略：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\powershell\NetworkSpeedLogger.ps1
```

## macOS Shell 脚本

macOS 版本只使用系统自带命令，不需要安装 Homebrew 软件包，也不需要管理员权限，同时支持 Apple 芯片与 Intel Mac。

首次使用时赋予脚本执行权限，然后以默认设置运行 24 小时，每 15 秒采样一次：

```sh
chmod +x macos/NetworkSpeedLogger.sh
./macos/NetworkSpeedLogger.sh
```

不限时运行，使用 `Ctrl+C` 或 `Q` 手动结束：

```sh
./macos/NetworkSpeedLogger.sh --duration-hours 0
```

运行 2 小时，每 5 秒采样一次：

```sh
./macos/NetworkSpeedLogger.sh --duration-hours 2 --sample-interval-seconds 5
```

列出网络接口，然后使用 BSD 接口名手动监控指定接口：

```sh
./macos/NetworkSpeedLogger.sh --list-adapters
./macos/NetworkSpeedLogger.sh --adapter en0 --adapter en5
```

手动模式也允许选择虚拟接口，例如指定某个 `utun` 接口。自动模式只监控处于连接状态的硬件端口，并排除回环、VPN/隧道、网桥、AWDL、虚拟机等虚拟接口。

手动指定语言，不跟随 macOS 的首选语言：

```sh
./macos/NetworkSpeedLogger.sh --language en-US
./macos/NetworkSpeedLogger.sh --language zh-CN
```

运行 `./macos/NetworkSpeedLogger.sh --help` 可以查看全部选项。

## 输出文件

每次记录会生成：

- `NetworkSpeed_YYYYMMDD_HHMMSS.csv`：带时间戳的采样数据、已运行时间、下载和上传速度及活动网卡。
- `NetworkSpeed_YYYYMMDD_HHMMSS_summary.md`：记录时长、累计流量、网卡列表以及最小、最大和平均速度。

PowerShell 与 macOS 脚本会将结果保存在脚本所在目录，GUI 程序则保存在所选输出目录。每次采样都会立即追加到 CSV，因此即使电脑或终端之后意外停止，已经完成的采样数据仍会保留。

CSV 中的速度使用十进制 MB/s，即 1 MB 等于 1,000,000 字节。GUI 可以将同一数据换算为 MB/s 或 Mbps 显示。

## 从源代码编译

在安装了“.NET 桌面开发”工作负载的 Visual Studio 中打开 `src/NetworkSpeedLogger/NetworkSpeedLogger.csproj`，选择 Release 配置并生成。项目目标为 .NET Framework 4.8，不依赖第三方运行库。

## 仓库结构

- `src/NetworkSpeedLogger/`：Windows WPF GUI 源代码和程序图标。
- `powershell/NetworkSpeedLogger.ps1`：Windows PowerShell 版本。
- `macos/NetworkSpeedLogger.sh`：macOS Shell 版本。
- `.github/workflows/release.yml`：可复现的 Windows 编译和发布流程。

## 开源协议

本项目采用 [MIT License](LICENSE)。
