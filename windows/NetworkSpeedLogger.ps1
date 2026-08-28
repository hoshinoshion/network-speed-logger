<#
.SYNOPSIS
    轻量级 Windows 实时网络速度记录工具。

.DESCRIPTION
    自动监控所有处于连接状态的物理网卡，排除 Hyper-V、VPN、虚拟机等虚拟网卡，
    并将多个物理网卡的流量合并计算。每次采样立即写入 CSV，结束时生成 Markdown 汇总。

    速度单位为十进制 MB/s（1 MB = 1,000,000 字节）。
    统计的是电脑网卡实际收发流量，包含互联网和局域网流量。

.EXAMPLE
    .\NetworkSpeedLogger.ps1
    使用默认设置：运行 24 小时，每 15 秒采样一次。

.EXAMPLE
    .\NetworkSpeedLogger.ps1 -DurationHours 2 -SampleIntervalSeconds 5
    运行 2 小时，每 5 秒采样一次。

.EXAMPLE
    .\NetworkSpeedLogger.ps1 -DurationHours 0
    不设自动结束时间，一直运行到按 Ctrl+C。

.EXAMPLE
    .\NetworkSpeedLogger.ps1 -AdapterName "Wi-Fi","Ethernet"
    只监控指定网卡。手动指定时也允许选择虚拟网卡。

.EXAMPLE
    .\NetworkSpeedLogger.ps1 -ListAdapters
    列出可用网卡名称后退出。

.EXAMPLE
    .\NetworkSpeedLogger.ps1 -Language en-US
    Force English terminal output and Markdown summary.
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "运行时长（小时）；设为 0 表示仅手动停止。")]
    [ValidateRange(0.0, 8760.0)]
    [double]$DurationHours = 24,

    [Parameter(HelpMessage = "采样间隔（秒）。")]
    [ValidateRange(1, 3600)]
    [int]$SampleIntervalSeconds = 15,

    [Parameter(HelpMessage = "要监控的网卡名称；留空时自动选择所有已连接的物理网卡。")]
    [string[]]$AdapterName,

    [Parameter(HelpMessage = "界面与汇总语言：Auto、zh-CN 或 en-US。")]
    [ValidateSet("Auto", "zh-CN", "en-US")]
    [string]$Language = "Auto",

    [Parameter(HelpMessage = "列出系统中的网卡后退出。")]
    [switch]$ListAdapters
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$BytesPerMB = 1000000.0

if ($Language -eq "zh-CN") {
    $script:IsChinese = $true
}
elseif ($Language -eq "en-US") {
    $script:IsChinese = $false
}
else {
    $script:IsChinese = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq "zh"
}

function Get-Text {
    param(
        [Parameter(Mandatory = $true)][string]$Chinese,
        [Parameter(Mandatory = $true)][string]$English
    )

    if ($script:IsChinese) {
        return $Chinese
    }
    return $English
}

function Get-AdapterKey {
    param([Parameter(Mandatory = $true)]$Adapter)

    if ($null -ne $Adapter.InterfaceGuid -and $Adapter.InterfaceGuid.ToString().Length -gt 0) {
        return $Adapter.InterfaceGuid.ToString()
    }

    return $Adapter.Name.ToString()
}

function Get-SelectedAdapters {
    if ($AdapterName -and $AdapterName.Count -gt 0) {
        $selected = foreach ($name in $AdapterName) {
            Get-NetAdapter -Name $name -ErrorAction Stop
        }
    }
    else {
        # -Physical 是 Windows 自带的可靠筛选，可避免 VPN、Hyper-V、VMware、
        # VirtualBox 等虚拟网卡造成重复计数。
        $selected = Get-NetAdapter -Physical -ErrorAction Stop |
            Where-Object { $_.Status -eq "Up" }
    }

    $unique = @{}
    foreach ($adapter in @($selected)) {
        $unique[(Get-AdapterKey -Adapter $adapter)] = $adapter
    }

    return @($unique.Values)
}

function Get-StatisticsSnapshot {
    param([Parameter(Mandatory = $true)][object[]]$Adapters)

    $snapshot = @{}
    foreach ($adapter in $Adapters) {
        try {
            $statistics = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction Stop
            $key = Get-AdapterKey -Adapter $adapter
            $snapshot[$key] = [PSCustomObject]@{
                Adapter      = $adapter
                ReceivedBytes = [uint64]$statistics.ReceivedBytes
                SentBytes     = [uint64]$statistics.SentBytes
            }
        }
        catch {
            # 网卡可能在两次采样之间被拔出或禁用。跳过本次数据，下一次再自动检测。
        }
    }

    return $snapshot
}

function Format-Duration {
    param([Parameter(Mandatory = $true)][double]$Seconds)

    $timeSpan = [TimeSpan]::FromSeconds([Math]::Max(0, $Seconds))
    if ($timeSpan.TotalDays -ge 1) {
        $daySeparator = Get-Text -Chinese " 天 " -English " d "
        return ([Math]::Floor($timeSpan.TotalDays).ToString([Globalization.CultureInfo]::InvariantCulture) +
            $daySeparator +
            ("{0:00}:{1:00}:{2:00}" -f $timeSpan.Hours, $timeSpan.Minutes, $timeSpan.Seconds))
    }

    return ("{0:00}:{1:00}:{2:00}" -f $timeSpan.Hours, $timeSpan.Minutes, $timeSpan.Seconds)
}

function Format-NumberInvariant {
    param(
        [Parameter(Mandatory = $true)][double]$Value,
        [Parameter(Mandatory = $true)][string]$Format
    )

    return $Value.ToString($Format, [Globalization.CultureInfo]::InvariantCulture)
}

function Test-ManualStopRequested {
    if (-not $script:consoleKeyCaptureEnabled) {
        return $false
    }

    try {
        while ([Console]::KeyAvailable) {
            $keyInfo = [Console]::ReadKey($true)
            $isControlC = ($keyInfo.Key -eq [ConsoleKey]::C) -and
                (($keyInfo.Modifiers -band [ConsoleModifiers]::Control) -ne 0)
            $isQ = $keyInfo.Key -eq [ConsoleKey]::Q

            if ($isControlC -or $isQ) {
                return $true
            }
        }
    }
    catch {
        # 某些非标准 PowerShell 宿主不提供控制台键盘接口，退回系统默认的 Ctrl+C。
        $script:consoleKeyCaptureEnabled = $false
    }

    return $false
}

function Wait-MonitorDelay {
    param(
        [Parameter(Mandatory = $true)][double]$Seconds,
        [Parameter(Mandatory = $true)][Diagnostics.Stopwatch]$Stopwatch
    )

    $waitUntil = $Stopwatch.Elapsed.TotalSeconds + $Seconds
    while ($Stopwatch.Elapsed.TotalSeconds -lt $waitUntil) {
        if (Test-ManualStopRequested) {
            return $false
        }

        $remainingMilliseconds = [int][Math]::Ceiling(
            ($waitUntil - $Stopwatch.Elapsed.TotalSeconds) * 1000.0
        )
        $sleepMilliseconds = [Math]::Min(200, [Math]::Max(1, $remainingMilliseconds))
        Start-Sleep -Milliseconds $sleepMilliseconds
    }

    return (-not (Test-ManualStopRequested))
}

if ($ListAdapters) {
    $physicalColumn = Get-Text -Chinese "是否物理网卡" -English "Physical"
    Get-NetAdapter -ErrorAction Stop |
        Sort-Object -Property Name |
        Select-Object Name, Status,
            @{ Name = $physicalColumn; Expression = { $_.HardwareInterface } },
            LinkSpeed, InterfaceDescription |
        Format-Table -AutoSize
    return
}

$initialAdapters = @(Get-SelectedAdapters)
if ($initialAdapters.Count -eq 0) {
        throw (Get-Text -Chinese "没有找到可监控的已连接物理网卡。请先连接网络，或运行 .\NetworkSpeedLogger.ps1 -ListAdapters 查看网卡名称并用 -AdapterName 手动指定。" -English "No connected physical adapter was found. Connect to a network, or run .\NetworkSpeedLogger.ps1 -ListAdapters and use -AdapterName to select one manually.")
}

$previousSnapshot = Get-StatisticsSnapshot -Adapters $initialAdapters
if ($previousSnapshot.Count -eq 0) {
    throw (Get-Text -Chinese "无法读取所选网卡的流量计数器。请确认网卡处于启用状态。" -English "Unable to read traffic counters for the selected adapters. Make sure they are enabled.")
}

$outputDirectory = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
    $outputDirectory = (Get-Location).Path
}

$startTime = Get-Date
$fileStamp = $startTime.ToString("yyyyMMdd_HHmmss")
$fileBase = "NetworkSpeed_$fileStamp"
$csvPath = Join-Path $outputDirectory ($fileBase + ".csv")
$summaryPath = Join-Path $outputDirectory ($fileBase + "_summary.md")

# 极少数情况下可能在同一秒启动两次，避免覆盖已有记录。
$suffix = 1
while ((Test-Path -LiteralPath $csvPath) -or (Test-Path -LiteralPath $summaryPath)) {
    $csvPath = Join-Path $outputDirectory ("{0}_{1}.csv" -f $fileBase, $suffix)
    $summaryPath = Join-Path $outputDirectory ("{0}_{1}_summary.md" -f $fileBase, $suffix)
    $suffix++
}

$utf8WithBom = New-Object System.Text.UTF8Encoding($true)
$csvWriter = New-Object System.IO.StreamWriter($csvPath, $false, $utf8WithBom)
$csvWriter.WriteLine("Timestamp,ElapsedSeconds,Download_MBps,Upload_MBps,ActiveAdapters")
$csvWriter.Flush()

$observedAdapters = New-Object "System.Collections.Generic.HashSet[string]"
foreach ($adapter in $initialAdapters) {
    [void]$observedAdapters.Add($adapter.Name)
}

$sampleCount = 0L
$totalReceivedBytes = 0.0
$totalSentBytes = 0.0
$totalMeasuredSeconds = 0.0
$minDownload = [double]::PositiveInfinity
$maxDownload = 0.0
$minUpload = [double]::PositiveInfinity
$maxUpload = 0.0
$durationStopReason = Get-Text -Chinese "达到设定时长" -English "Duration reached"
$manualStopReason = Get-Text -Chinese "用户手动停止" -English "Stopped by user"
$stopReason = $durationStopReason
$fatalError = $null
$statusLineWritten = $false
$consoleKeyCaptureEnabled = $false
$originalTreatControlCAsInput = $false

# 将 Ctrl+C 当作普通按键读取，避免它直接终止 PowerShell 管道。
# 这样脚本能可靠地写完 CSV、MD 和终端总结。退出时会恢复原设置。
try {
    if (-not [Console]::IsInputRedirected) {
        $originalTreatControlCAsInput = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true
        $consoleKeyCaptureEnabled = $true
    }
}
catch {
    $consoleKeyCaptureEnabled = $false
}

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$lastSampleElapsed = 0.0
$targetSeconds = $DurationHours * 3600.0

$nameSeparator = if ($script:IsChinese) { "、" } else { ", " }
$initialNames = ($initialAdapters | Sort-Object -Property Name | ForEach-Object { $_.Name }) -join $nameSeparator
Write-Host (Get-Text -Chinese "网络速度监控已启动" -English "Network speed monitoring started") -ForegroundColor Green
Write-Host ((Get-Text -Chinese "监控网卡：" -English "Adapters: ") + $initialNames)
if ($DurationHours -gt 0) {
    Write-Host ((Get-Text -Chinese "计划时长：" -English "Planned duration: ") + $DurationHours.ToString([Globalization.CultureInfo]::InvariantCulture) +
        (Get-Text -Chinese " 小时；采样间隔：" -English " hours; sample interval: ") + $SampleIntervalSeconds.ToString() +
        (Get-Text -Chinese " 秒" -English " seconds"))
}
else {
    Write-Host ((Get-Text -Chinese "计划时长：不限；采样间隔：" -English "Planned duration: unlimited; sample interval: ") +
        $SampleIntervalSeconds.ToString() + (Get-Text -Chinese " 秒" -English " seconds"))
}
Write-Host ((Get-Text -Chinese "CSV：" -English "CSV: ") + $csvPath)
if ($consoleKeyCaptureEnabled) {
    Write-Host (Get-Text -Chinese "按 Ctrl+C 或 Q 可提前停止并生成汇总。" -English "Press Ctrl+C or Q to stop early and generate the summary.")
}
else {
    Write-Host (Get-Text -Chinese "按 Ctrl+C 可提前停止并生成汇总。" -English "Press Ctrl+C to stop early and generate the summary.")
}

try {
    while ($true) {
        $elapsedBeforeSleep = $stopwatch.Elapsed.TotalSeconds
        if ($DurationHours -gt 0 -and $elapsedBeforeSleep -ge $targetSeconds) {
            break
        }

        $sleepSeconds = [double]$SampleIntervalSeconds
        if ($DurationHours -gt 0) {
            $sleepSeconds = [Math]::Min($sleepSeconds, $targetSeconds - $elapsedBeforeSleep)
        }

        $manualStopRequested = $false
        if ($sleepSeconds -gt 0) {
            $waitCompleted = Wait-MonitorDelay -Seconds $sleepSeconds -Stopwatch $stopwatch
            if (-not $waitCompleted) {
                $manualStopRequested = $true
            }
        }

        $sampleTime = Get-Date
        $currentElapsed = $stopwatch.Elapsed.TotalSeconds
        $actualInterval = $currentElapsed - $lastSampleElapsed
        $lastSampleElapsed = $currentElapsed

        if ($actualInterval -le 0) {
            continue
        }

        # 自动模式会重新检查已连接的物理网卡，因此有线/Wi-Fi 切换后无需重启脚本。
        $currentAdapters = @(Get-SelectedAdapters)
        foreach ($adapter in $currentAdapters) {
            [void]$observedAdapters.Add($adapter.Name)
        }

        # 也查询上一轮中刚刚断开的网卡，以尽可能记录它断开前的最后一段流量。
        $adaptersToQuery = @{}
        foreach ($entry in $previousSnapshot.GetEnumerator()) {
            $adaptersToQuery[$entry.Key] = $entry.Value.Adapter
        }
        foreach ($adapter in $currentAdapters) {
            $adaptersToQuery[(Get-AdapterKey -Adapter $adapter)] = $adapter
        }

        $currentSnapshot = Get-StatisticsSnapshot -Adapters @($adaptersToQuery.Values)
        $receivedDelta = 0.0
        $sentDelta = 0.0

        foreach ($key in $currentSnapshot.Keys) {
            if ($previousSnapshot.ContainsKey($key)) {
                $old = $previousSnapshot[$key]
                $new = $currentSnapshot[$key]

                # 驱动重置、休眠或网卡重连可能使累计计数器归零；负差值不计入流量。
                if ($new.ReceivedBytes -ge $old.ReceivedBytes) {
                    $receivedDelta += [double]($new.ReceivedBytes - $old.ReceivedBytes)
                }
                if ($new.SentBytes -ge $old.SentBytes) {
                    $sentDelta += [double]($new.SentBytes - $old.SentBytes)
                }
            }
        }

        # 下一轮仅保留当前仍应监控的网卡；新出现的网卡从本轮建立基线。
        $nextSnapshot = @{}
        foreach ($adapter in $currentAdapters) {
            $key = Get-AdapterKey -Adapter $adapter
            if ($currentSnapshot.ContainsKey($key)) {
                $nextSnapshot[$key] = $currentSnapshot[$key]
            }
        }
        $previousSnapshot = $nextSnapshot

        $downloadMBps = ($receivedDelta / $BytesPerMB) / $actualInterval
        $uploadMBps = ($sentDelta / $BytesPerMB) / $actualInterval

        $sampleCount++
        $totalReceivedBytes += $receivedDelta
        $totalSentBytes += $sentDelta
        $totalMeasuredSeconds += $actualInterval
        $minDownload = [Math]::Min($minDownload, $downloadMBps)
        $maxDownload = [Math]::Max($maxDownload, $downloadMBps)
        $minUpload = [Math]::Min($minUpload, $uploadMBps)
        $maxUpload = [Math]::Max($maxUpload, $uploadMBps)

        $activeNames = ($currentAdapters | Sort-Object -Property Name | ForEach-Object { $_.Name }) -join "; "
        if ([string]::IsNullOrWhiteSpace($activeNames)) {
            $activeNames = "(none)"
        }
        $csvSafeNames = $activeNames.Replace('"', '""')
        $csvLine = [string]::Format(
            [Globalization.CultureInfo]::InvariantCulture,
            '{0},{1:F3},{2:F6},{3:F6},"{4}"',
            $sampleTime.ToString("yyyy-MM-ddTHH:mm:ss.fffK"),
            $currentElapsed,
            $downloadMBps,
            $uploadMBps,
            $csvSafeNames
        )
        $csvWriter.WriteLine($csvLine)
        $csvWriter.Flush()

        if ($script:IsChinese) {
            $status = "{0:yyyy-MM-dd HH:mm:ss} | 下载 {1,10:F3} MB/s | 上传 {2,10:F3} MB/s | 样本 {3}" -f $sampleTime, $downloadMBps, $uploadMBps, $sampleCount
        }
        else {
            $status = "{0:yyyy-MM-dd HH:mm:ss} | Down {1,10:F3} MB/s | Up {2,10:F3} MB/s | Samples {3}" -f $sampleTime, $downloadMBps, $uploadMBps, $sampleCount
        }
        Write-Host ("`r" + $status.PadRight(100)) -NoNewline
        $statusLineWritten = $true

        if ($manualStopRequested) {
            $stopReason = $manualStopReason
            break
        }
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    $stopReason = $manualStopReason
}
catch {
    $fatalError = $_
    $stopReason = (Get-Text -Chinese "发生错误：" -English "Error: ") + $_.Exception.Message
}
finally {
    $stopwatch.Stop()
    $endTime = Get-Date
    $runSeconds = $stopwatch.Elapsed.TotalSeconds

    if ($consoleKeyCaptureEnabled) {
        try {
            [Console]::TreatControlCAsInput = $originalTreatControlCAsInput
        }
        catch {
        }
        $consoleKeyCaptureEnabled = $false
    }

    # 非标准终端可能绕过 catch，但提前退出本身仍可据运行时长识别为手动停止。
    if ($stopReason -eq $durationStopReason -and
        ($DurationHours -eq 0 -or $runSeconds -lt ($targetSeconds - 1.0))) {
        $stopReason = $manualStopReason
    }

    if ($null -ne $csvWriter) {
        $csvWriter.Flush()
        $csvWriter.Dispose()
    }

    if ($statusLineWritten) {
        Write-Host ""
    }

    if ($sampleCount -gt 0 -and $totalMeasuredSeconds -gt 0) {
        $averageDownload = ($totalReceivedBytes / $BytesPerMB) / $totalMeasuredSeconds
        $averageUpload = ($totalSentBytes / $BytesPerMB) / $totalMeasuredSeconds
    }
    else {
        $averageDownload = 0.0
        $averageUpload = 0.0
        $minDownload = 0.0
        $minUpload = 0.0
    }

    $adapterSummary = [string]::Join($nameSeparator, $observedAdapters)
    $durationText = Format-Duration -Seconds $runSeconds
    $downloadTotalMB = $totalReceivedBytes / $BytesPerMB
    $uploadTotalMB = $totalSentBytes / $BytesPerMB

    # 先用纯 .NET 方法准备好文本。即使宿主仍将 Ctrl+C 视作管道中止，汇总也不会写到一半。
    $invariantCulture = [Globalization.CultureInfo]::InvariantCulture
    $minDownloadText = $minDownload.ToString("F3", $invariantCulture)
    $maxDownloadText = $maxDownload.ToString("F3", $invariantCulture)
    $averageDownloadText = $averageDownload.ToString("F3", $invariantCulture)
    $minUploadText = $minUpload.ToString("F3", $invariantCulture)
    $maxUploadText = $maxUpload.ToString("F3", $invariantCulture)
    $averageUploadText = $averageUpload.ToString("F3", $invariantCulture)
    $downloadTotalText = $downloadTotalMB.ToString("F3", $invariantCulture)
    $uploadTotalText = $uploadTotalMB.ToString("F3", $invariantCulture)

    $summaryWriter = [System.IO.StreamWriter]::new($summaryPath, $false, $utf8WithBom)
    try {
        if ($script:IsChinese) {
            $summaryWriter.WriteLine("# 网络速度监控汇总")
            $summaryWriter.WriteLine("")
            $summaryWriter.WriteLine("- 开始时间：" + $startTime.ToString("yyyy-MM-dd HH:mm:ss zzz"))
            $summaryWriter.WriteLine("- 结束时间：" + $endTime.ToString("yyyy-MM-dd HH:mm:ss zzz"))
            $summaryWriter.WriteLine("- 实际运行时间：" + $durationText)
            $summaryWriter.WriteLine("- 结束原因：" + $stopReason)
            $summaryWriter.WriteLine("- 采样间隔：" + $SampleIntervalSeconds.ToString() + " 秒")
            $summaryWriter.WriteLine("- 有效样本数：" + $sampleCount.ToString())
            $summaryWriter.WriteLine("- 监控过的网卡：" + $adapterSummary.Replace("|", "\|"))
            $summaryWriter.WriteLine("- 详细记录：" + [IO.Path]::GetFileName($csvPath))
            $summaryWriter.WriteLine("")
            $summaryWriter.WriteLine("| 指标 | 下载 | 上传 |")
            $summaryWriter.WriteLine("|---|---:|---:|")
            $summaryWriter.WriteLine("| 最小速度 | " + $minDownloadText + " MB/s | " + $minUploadText + " MB/s |")
            $summaryWriter.WriteLine("| 最大速度 | " + $maxDownloadText + " MB/s | " + $maxUploadText + " MB/s |")
            $summaryWriter.WriteLine("| 平均速度 | " + $averageDownloadText + " MB/s | " + $averageUploadText + " MB/s |")
            $summaryWriter.WriteLine("| 总数据量 | " + $downloadTotalText + " MB | " + $uploadTotalText + " MB |")
            $summaryWriter.WriteLine("")
            $summaryWriter.WriteLine("> 速度使用十进制 MB/s（1 MB = 1,000,000 字节）。数据为物理网卡实际收发流量，包含互联网和局域网流量。")
        }
        else {
            $summaryWriter.WriteLine("# Network Speed Monitoring Summary")
            $summaryWriter.WriteLine("")
            $summaryWriter.WriteLine("- Start time: " + $startTime.ToString("yyyy-MM-dd HH:mm:ss zzz"))
            $summaryWriter.WriteLine("- End time: " + $endTime.ToString("yyyy-MM-dd HH:mm:ss zzz"))
            $summaryWriter.WriteLine("- Actual duration: " + $durationText)
            $summaryWriter.WriteLine("- Stop reason: " + $stopReason)
            $summaryWriter.WriteLine("- Sample interval: " + $SampleIntervalSeconds.ToString() + " seconds")
            $summaryWriter.WriteLine("- Valid samples: " + $sampleCount.ToString())
            $summaryWriter.WriteLine("- Monitored adapters: " + $adapterSummary.Replace("|", "\|"))
            $summaryWriter.WriteLine("- Detailed log: " + [IO.Path]::GetFileName($csvPath))
            $summaryWriter.WriteLine("")
            $summaryWriter.WriteLine("| Metric | Download | Upload |")
            $summaryWriter.WriteLine("|---|---:|---:|")
            $summaryWriter.WriteLine("| Minimum speed | " + $minDownloadText + " MB/s | " + $minUploadText + " MB/s |")
            $summaryWriter.WriteLine("| Maximum speed | " + $maxDownloadText + " MB/s | " + $maxUploadText + " MB/s |")
            $summaryWriter.WriteLine("| Average speed | " + $averageDownloadText + " MB/s | " + $averageUploadText + " MB/s |")
            $summaryWriter.WriteLine("| Total data | " + $downloadTotalText + " MB | " + $uploadTotalText + " MB |")
            $summaryWriter.WriteLine("")
            $summaryWriter.WriteLine("> Speeds use decimal MB/s (1 MB = 1,000,000 bytes). Values are actual physical-adapter traffic and include both internet and local-network traffic.")
        }
    }
    finally {
        $summaryWriter.Flush()
        $summaryWriter.Dispose()
    }

    # 使用 Console.WriteLine 绕过已停止的 PowerShell 输出管道。
    try {
        if ($script:IsChinese) {
            [Console]::WriteLine("网络速度监控已结束")
            [Console]::WriteLine("结束原因：" + $stopReason)
            [Console]::WriteLine("实际运行时间：" + $durationText + "；样本数：" + $sampleCount.ToString())
            [Console]::WriteLine("下载：最小 " + $minDownloadText + "，最大 " + $maxDownloadText + "，平均 " + $averageDownloadText + " MB/s")
            [Console]::WriteLine("上传：最小 " + $minUploadText + "，最大 " + $maxUploadText + "，平均 " + $averageUploadText + " MB/s")
            [Console]::WriteLine("CSV：" + $csvPath)
            [Console]::WriteLine("汇总：" + $summaryPath)
        }
        else {
            [Console]::WriteLine("Network speed monitoring finished")
            [Console]::WriteLine("Stop reason: " + $stopReason)
            [Console]::WriteLine("Actual duration: " + $durationText + "; samples: " + $sampleCount.ToString())
            [Console]::WriteLine("Download: min " + $minDownloadText + ", max " + $maxDownloadText + ", average " + $averageDownloadText + " MB/s")
            [Console]::WriteLine("Upload: min " + $minUploadText + ", max " + $maxUploadText + ", average " + $averageUploadText + " MB/s")
            [Console]::WriteLine("CSV: " + $csvPath)
            [Console]::WriteLine("Summary: " + $summaryPath)
        }
    }
    catch {
        Write-Host (Get-Text -Chinese "网络速度监控已结束" -English "Network speed monitoring finished")
        Write-Host ((Get-Text -Chinese "结束原因：" -English "Stop reason: ") + $stopReason)
        Write-Host ((Get-Text -Chinese "实际运行时间：" -English "Actual duration: ") + $durationText +
            (Get-Text -Chinese "；样本数：" -English "; samples: ") + $sampleCount.ToString())
        Write-Host ((Get-Text -Chinese "CSV：" -English "CSV: ") + $csvPath)
        Write-Host ((Get-Text -Chinese "汇总：" -English "Summary: ") + $summaryPath)
    }
}

if ($null -ne $fatalError) {
    throw $fatalError
}
