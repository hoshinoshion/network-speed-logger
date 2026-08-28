import Charts
import SwiftUI

struct RootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitor: NetworkMonitor

    var body: some View {
        Group {
            if settings.outputFolderURL == nil {
                WelcomeView(settings: settings)
            } else {
                MainView(settings: settings, monitor: monitor)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: settings.outputFolderURL)
    }
}

private struct WelcomeView: View {
    @ObservedObject var settings: AppSettings
    @State private var promptedForFolder = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.blue.gradient)
                    .frame(width: 104, height: 104)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .blue.opacity(0.25), radius: 20, y: 8)

            VStack(spacing: 8) {
                Text("Network Speed Logger")
                    .font(.largeTitle.weight(.semibold))
                Text(settings.text(
                    "Choose a folder before your first session",
                    "首次记录前请选择保存文件夹"
                ))
                .font(.title3)
                .foregroundStyle(.secondary)
            }

            Text(settings.text(
                "Every sample is written immediately to CSV. A Markdown summary is created when logging ends. The app remembers this folder for future sessions.",
                "每个采样都会立即写入 CSV，记录结束时会生成 Markdown 汇总。应用会记住该文件夹，之后无需重复选择。"
            ))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 520)

            Button {
                settings.chooseOutputFolder()
            } label: {
                Label(settings.text("Choose Output Folder", "选择保存文件夹"), systemImage: "folder.badge.plus")
                    .frame(minWidth: 170)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(60)
        .task {
            guard !promptedForFolder else { return }
            promptedForFolder = true
            try? await Task.sleep(nanoseconds: 350_000_000)
            if settings.outputFolderURL == nil {
                settings.chooseOutputFolder()
            }
        }
    }
}

private struct MainView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitor: NetworkMonitor

    var body: some View {
        NavigationSplitView {
            ControlsSidebar(settings: settings, monitor: monitor)
                .navigationSplitViewColumnWidth(min: 270, ideal: 300, max: 340)
        } detail: {
            DashboardView(settings: settings, monitor: monitor)
                .navigationTitle("Network Speed Logger")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            settings.revealOutputFolder()
                        } label: {
                            Label(settings.text("Show Files", "显示文件"), systemImage: "folder")
                        }

                        if monitor.state.isRunning {
                            Button(role: .destructive) {
                                monitor.stop()
                            } label: {
                                Label(settings.text("Stop", "结束"), systemImage: "stop.fill")
                            }
                        } else {
                            Button {
                                monitor.start(using: settings)
                            } label: {
                                Label(settings.text("Start", "开始"), systemImage: "record.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(startIsDisabled)
                        }
                    }
                }
        }
    }

    private var startIsDisabled: Bool {
        settings.outputFolderURL == nil
            || (settings.interfaceMode == .manual && settings.selectedInterfaceNames.isEmpty)
    }
}

private struct ControlsSidebar: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitor: NetworkMonitor

    var body: some View {
        Form {
            Section(settings.text("Session", "记录")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(settings.text("Duration", "记录时长"))
                        Spacer()
                        Text(durationText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Stepper("", value: $settings.durationHours, in: 0...168, step: 1)
                        .labelsHidden()
                        .accessibilityLabel(settings.text("Duration in hours", "记录时长（小时）"))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(settings.text("Sample interval", "采样间隔"))
                        Spacer()
                        Text("\(settings.sampleIntervalSeconds) s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Stepper("", value: $settings.sampleIntervalSeconds, in: 1...3_600, step: 1)
                        .labelsHidden()
                        .accessibilityLabel(settings.text("Sample interval in seconds", "采样间隔（秒）"))
                }

                Picker(settings.text("Speed unit", "速度单位"), selection: $settings.speedUnit) {
                    Text("MB/s").tag(SpeedUnit.megabytesPerSecond)
                    Text("Mbps").tag(SpeedUnit.megabitsPerSecond)
                }
                .pickerStyle(.segmented)
            }
            .disabled(monitor.state.isRunning)

            Section(settings.text("Interfaces", "网络接口")) {
                Picker(settings.text("Mode", "模式"), selection: $settings.interfaceMode) {
                    Text(settings.text("Automatic", "自动")).tag(InterfaceSelectionMode.automatic)
                    Text(settings.text("Manual", "手动")).tag(InterfaceSelectionMode.manual)
                }
                .pickerStyle(.segmented)
                .disabled(monitor.state.isRunning)

                if settings.interfaceMode == .automatic {
                    Label {
                        Text(settings.text(
                            "Active physical interfaces are combined automatically.",
                            "自动合并所有活动物理接口。"
                        ))
                        .font(.caption)
                    } icon: {
                        Image(systemName: "wand.and.stars")
                    }
                    .foregroundStyle(.secondary)

                    ForEach(monitor.availableInterfaces.filter { $0.isPhysical && $0.isActive }) { interface in
                        InterfaceRow(interface: interface, checked: true, settings: settings)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(monitor.availableInterfaces) { interface in
                                Toggle(isOn: Binding(
                                    get: { settings.selectedInterfaceNames.contains(interface.name) },
                                    set: { settings.toggleInterface(interface.name, enabled: $0) }
                                )) {
                                    InterfaceRow(interface: interface, checked: nil, settings: settings)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 190)
                    .disabled(monitor.state.isRunning)
                }

                Button {
                    monitor.refreshInterfaces()
                } label: {
                    Label(settings.text("Refresh Interfaces", "刷新接口"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            Section(settings.text("Output", "输出")) {
                if let folder = settings.outputFolderURL {
                    Label {
                        Text(folder.path)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .font(.caption)
                    } icon: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                    }
                }

                HStack {
                    Button(settings.text("Change…", "更改…")) {
                        settings.chooseOutputFolder()
                    }
                    .disabled(monitor.state.isRunning)

                    Button(settings.text("Reveal", "显示")) {
                        settings.revealOutputFolder()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Divider()
                if monitor.state.isRunning {
                    Button(role: .destructive) {
                        monitor.stop()
                    } label: {
                        Label(settings.text("Stop Logging", "结束记录"), systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        monitor.start(using: settings)
                    } label: {
                        Label(settings.text("Start Logging", "开始记录"), systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(settings.interfaceMode == .manual && settings.selectedInterfaceNames.isEmpty)
                }
            }
            .padding([.horizontal, .bottom])
            .background(.bar)
        }
    }

    private var durationText: String {
        settings.durationHours == 0
            ? settings.text("Unlimited", "不限时")
            : String(format: settings.text("%.0f h", "%.0f 小时"), settings.durationHours)
    }
}

private struct InterfaceRow: View {
    let interface: NetworkInterfaceInfo
    let checked: Bool?
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(interface.displayName)
                        .lineLimit(1)
                    Text(interface.name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(interfaceKind)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Circle()
                .fill(interface.isActive ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
                .help(interface.isActive ? settings.text("Active", "活动") : settings.text("Inactive", "未活动"))
        }
    }

    private var interfaceKind: String {
        if interface.isPhysical { return settings.text("Physical", "物理接口") }
        if interface.isVirtual { return settings.text("Virtual", "虚拟接口") }
        return settings.text("System interface", "系统接口")
    }
}

private struct DashboardView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitor: NetworkMonitor

    private let metricColumns = [GridItem(.adaptive(minimum: 165), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusHeader

                LazyVGrid(columns: metricColumns, spacing: 12) {
                    MetricCard(
                        title: settings.text("Download", "下载"),
                        value: formatSpeed(monitor.currentDownloadBytesPerSecond),
                        icon: "arrow.down",
                        color: .blue
                    )
                    MetricCard(
                        title: settings.text("Upload", "上传"),
                        value: formatSpeed(monitor.currentUploadBytesPerSecond),
                        icon: "arrow.up",
                        color: .purple
                    )
                    MetricCard(
                        title: settings.text("Received", "已接收"),
                        value: formatBytes(monitor.statistics.totalReceivedBytes),
                        icon: "tray.and.arrow.down",
                        color: .teal
                    )
                    MetricCard(
                        title: settings.text("Sent", "已发送"),
                        value: formatBytes(monitor.statistics.totalSentBytes),
                        icon: "tray.and.arrow.up",
                        color: .orange
                    )
                }

                speedChart
                statisticsPanel
                recentSamplesPanel
            }
            .padding(22)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: statusIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.title2.weight(.semibold))
                Text(statusSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(monitor.elapsedSeconds.clockText)
                    .font(.title3.monospacedDigit().weight(.medium))
                Text(remainingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var speedChart: some View {
        GroupBox {
            if monitor.samples.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(settings.text(
                        "The live chart appears after the first sample.",
                        "完成第一个采样后将显示实时曲线。"
                    ))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 230)
            } else {
                Chart(chartSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Download", settings.speedUnit.value(fromBytesPerSecond: sample.downloadBytesPerSecond))
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Upload", settings.speedUnit.value(fromBytesPerSecond: sample.uploadBytesPerSecond))
                    )
                    .foregroundStyle(.purple)
                    .interpolationMethod(.catmullRom)
                }
                .chartYAxisLabel(settings.speedUnit.suffix)
                .frame(minHeight: 260)
            }
        } label: {
            HStack {
                Label(settings.text("Live Speed", "实时速度"), systemImage: "waveform.path.ecg")
                Spacer()
                HStack(spacing: 12) {
                    chartLegend(color: .blue, text: settings.text("Download", "下载"))
                    chartLegend(color: .purple, text: settings.text("Upload", "上传"))
                }
                .font(.caption)
            }
        }
    }

    private var statisticsPanel: some View {
        GroupBox(settings.text("Session Statistics", "本次记录统计")) {
            Grid(alignment: .trailing, horizontalSpacing: 22, verticalSpacing: 9) {
                GridRow {
                    Text("")
                    Text(settings.text("Minimum", "最小")).foregroundStyle(.secondary)
                    Text(settings.text("Maximum", "最大")).foregroundStyle(.secondary)
                    Text(settings.text("Average", "平均")).foregroundStyle(.secondary)
                }
                Divider()
                GridRow {
                    Label(settings.text("Download", "下载"), systemImage: "arrow.down")
                        .foregroundStyle(.blue)
                        .gridColumnAlignment(.leading)
                    Text(formatSpeed(monitor.statistics.minimumDownloadBytesPerSecond ?? 0))
                    Text(formatSpeed(monitor.statistics.maximumDownloadBytesPerSecond))
                    Text(formatSpeed(monitor.statistics.averageDownloadBytesPerSecond))
                }
                GridRow {
                    Label(settings.text("Upload", "上传"), systemImage: "arrow.up")
                        .foregroundStyle(.purple)
                        .gridColumnAlignment(.leading)
                    Text(formatSpeed(monitor.statistics.minimumUploadBytesPerSecond ?? 0))
                    Text(formatSpeed(monitor.statistics.maximumUploadBytesPerSecond))
                    Text(formatSpeed(monitor.statistics.averageUploadBytesPerSecond))
                }
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private var recentSamplesPanel: some View {
        GroupBox(settings.text("Recent Samples", "最近采样")) {
            VStack(spacing: 0) {
                sampleRow(
                    time: settings.text("Time", "时间"),
                    download: settings.text("Download", "下载"),
                    upload: settings.text("Upload", "上传"),
                    interfaces: settings.text("Interfaces", "接口"),
                    isHeader: true
                )
                Divider()
                if recentSamples.isEmpty {
                    Text(settings.text("No samples yet", "暂无采样"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                } else {
                    ForEach(recentSamples) { sample in
                        sampleRow(
                            time: Self.sampleTimeFormatter.string(from: sample.timestamp),
                            download: formatSpeed(sample.downloadBytesPerSecond),
                            upload: formatSpeed(sample.uploadBytesPerSecond),
                            interfaces: sample.activeInterfaces.joined(separator: ", "),
                            isHeader: false
                        )
                        if sample.id != recentSamples.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func sampleRow(time: String, download: String, upload: String, interfaces: String, isHeader: Bool) -> some View {
        HStack(spacing: 14) {
            Text(time).frame(width: 74, alignment: .leading)
            Text(download).frame(width: 110, alignment: .trailing)
            Text(upload).frame(width: 110, alignment: .trailing)
            Text(interfaces.isEmpty ? "—" : interfaces)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(isHeader ? .caption.weight(.semibold) : .body.monospacedDigit())
        .foregroundStyle(isHeader ? .secondary : .primary)
        .padding(.vertical, 8)
    }

    private func chartLegend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }

    private var chartSamples: [SpeedSample] { Array(monitor.samples.suffix(60)) }
    private var recentSamples: [SpeedSample] { Array(monitor.samples.suffix(5).reversed()) }

    private var statusTitle: String {
        switch monitor.state {
        case .idle: return settings.text("Ready", "准备就绪")
        case .running: return settings.text("Logging", "正在记录")
        case .finished: return settings.text("Session Complete", "记录已完成")
        case .failed: return settings.text("Attention Required", "需要处理")
        }
    }

    private var statusSubtitle: String {
        switch monitor.state {
        case .failed(let message): return message
        case .running: return monitor.eventMessage
        case .finished:
            return settings.text("CSV and Markdown files were saved.", "CSV 和 Markdown 文件已经保存。")
        case .idle:
            return settings.text("Configure a session, then select Start.", "设置记录参数，然后点击“开始”。")
        }
    }

    private var statusColor: Color {
        switch monitor.state {
        case .running: return .green
        case .failed: return .red
        case .finished: return .blue
        case .idle: return .secondary
        }
    }

    private var statusIcon: String {
        switch monitor.state {
        case .running: return "record.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .finished: return "checkmark.circle.fill"
        case .idle: return "speedometer"
        }
    }

    private var remainingText: String {
        guard settings.durationHours > 0 else { return settings.text("No time limit", "不限时") }
        let total = settings.durationHours * 3_600
        let remaining = max(0, total - monitor.elapsedSeconds)
        return settings.text("\(remaining.clockText) remaining", "剩余 \(remaining.clockText)")
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let value = settings.speedUnit.value(fromBytesPerSecond: bytesPerSecond)
        return String(format: "%.3f %@", value, settings.speedUnit.suffix)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1_000, index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        return String(format: "%.2f %@", value, units[index])
    }

    private static let sampleTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitor: NetworkMonitor

    var body: some View {
        Form {
            Picker(settings.text("Language", "语言"), selection: $settings.language) {
                Text(settings.text("Automatic", "自动")).tag(AppLanguage.automatic)
                Text("English").tag(AppLanguage.english)
                Text("简体中文").tag(AppLanguage.simplifiedChinese)
            }

            LabeledContent(settings.text("Output folder", "保存文件夹")) {
                HStack {
                    Text(settings.outputFolderURL?.path ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button(settings.text("Change…", "更改…")) {
                        settings.chooseOutputFolder()
                    }
                    .disabled(monitor.state.isRunning)
                }
            }

            LabeledContent(settings.text("Version", "版本"), value: "0.2.0")
        }
        .formStyle(.grouped)
    }
}
