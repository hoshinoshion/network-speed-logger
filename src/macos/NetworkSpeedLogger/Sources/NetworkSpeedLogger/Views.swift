import AppKit
import Charts
import SwiftUI

struct RootView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitor: NetworkMonitor
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        Group {
            if settings.outputFolderURL == nil {
                WelcomeView(settings: settings)
            } else {
                MainView(settings: settings, monitor: monitor)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: settings.outputFolderURL)
        .task(id: settings.language) {
            try? await Task.sleep(nanoseconds: 100_000_000)
            MenuBarLocalizer.apply(usesChinese: settings.usesChinese)
        }
        .task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, settings.automaticallyChecksForUpdates else { return }
            await updateChecker.checkAutomaticallyIfNeeded()
        }
        .alert(
            settings.text("Update Available", "发现新版本"),
            isPresented: Binding(
                get: { updateChecker.presentedRelease != nil },
                set: { isPresented in
                    if !isPresented { updateChecker.deferPresentedRelease() }
                }
            ),
            presenting: updateChecker.presentedRelease
        ) { _ in
            Button(settings.text("View Release", "查看并下载")) {
                updateChecker.openPresentedRelease()
            }
            Button(settings.text("Skip This Version", "跳过此版本")) {
                updateChecker.skipPresentedRelease()
            }
            Button(settings.text("Later", "稍后"), role: .cancel) {
                updateChecker.deferPresentedRelease()
            }
        } message: { release in
            Text(settings.text(
                "Network Speed Logger \(release.version) is available. You are using \(UpdateChecker.displayedCurrentVersion).",
                "Network Speed Logger \(release.version) 已发布，当前版本为 \(UpdateChecker.displayedCurrentVersion)。"
            ))
        }
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
                .navigationSplitViewColumnWidth(min: 270, ideal: 290, max: 340)
        } detail: {
            DashboardView(settings: settings, monitor: monitor)
                .navigationTitle("Network Speed Logger")
                .toolbar {
                    if #available(macOS 14.0, *) {
                        ToolbarItem(placement: .primaryAction) {
                            SettingsLink {
                                Label(settings.text("Settings", "设置"), systemImage: "gearshape")
                            }
                            .help(settings.text("Open Settings", "打开设置"))
                        }
                    } else {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                openLegacySettingsWindow()
                            } label: {
                                Label(settings.text("Settings", "设置"), systemImage: "gearshape")
                            }
                            .help(settings.text("Open Settings", "打开设置"))
                        }
                    }

                    if #available(macOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .primaryAction)
                    }

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
                                Label(settings.text("Stop", "结束"), systemImage: "stop.circle.fill")
                            }
                        } else {
                            Button {
                                monitor.start(using: settings)
                            } label: {
                                Label(settings.text("Start", "开始"), systemImage: "record.circle.fill")
                            }
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

    private func openLegacySettingsWindow() {
        let opened = NSApp.sendAction(
            Selector(("showPreferencesWindow:")),
            to: nil,
            from: nil
        )
        if !opened {
            NSApp.sendAction(
                Selector(("showSettingsWindow:")),
                to: nil,
                from: nil
            )
        }
    }
}

private enum SidebarMetrics {
    static let trailingControlWidth: CGFloat = 120
    static let numericFieldWidth: CGFloat = 74
    static let rowVerticalPadding: CGFloat = 6
}

private struct FixedWidthSegmentedPicker<Value: Hashable>: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding private var selection: Value
    private let options: [(label: String, value: Value)]
    private let totalWidth: CGFloat

    init(
        selection: Binding<Value>,
        options: [(String, Value)],
        totalWidth: CGFloat = SidebarMetrics.trailingControlWidth
    ) {
        _selection = selection
        self.options = options.map { (label: $0.0, value: $0.1) }
        self.totalWidth = totalWidth
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        NSSegmentedControl(
            labels: options.map { $0.label },
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if control.segmentCount != options.count {
            control.segmentCount = options.count
        }
        for (index, option) in options.enumerated() {
            control.setLabel(option.label, forSegment: index)
            control.setWidth(totalWidth / CGFloat(options.count), forSegment: index)
        }
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
        control.isEnabled = isEnabled
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSSegmentedControl,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: totalWidth,
            height: nsView.intrinsicContentSize.height
        )
    }

    final class Coordinator: NSObject {
        var parent: FixedWidthSegmentedPicker

        init(parent: FixedWidthSegmentedPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            guard parent.options.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.options[sender.selectedSegment].value
        }
    }
}

private struct ControlsSidebar: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitor: NetworkMonitor

    var body: some View {
        List {
            Section(settings.text("Session", "记录")) {
                DurationInputRow(
                    title: settings.text("Duration", "记录时长"),
                    value: $settings.durationHours,
                    unlimitedText: settings.text("0 = unlimited", "0 表示不限时")
                )

                IntervalInputRow(
                    title: settings.text("Sample interval", "采样间隔"),
                    value: $settings.sampleIntervalSeconds
                )

                HStack(spacing: 12) {
                    Text(settings.text("Speed unit", "速度单位"))
                    Spacer(minLength: 12)
                    FixedWidthSegmentedPicker(
                        selection: $settings.speedUnit,
                        options: [
                            ("MB/s", SpeedUnit.megabytesPerSecond),
                            ("Mbps", SpeedUnit.megabitsPerSecond)
                        ]
                    )
                    .frame(width: SidebarMetrics.trailingControlWidth)
                }
                .padding(.vertical, SidebarMetrics.rowVerticalPadding)
            }
            .disabled(monitor.state.isRunning)

            Section {
                HStack(spacing: 12) {
                    Text(settings.text("Mode", "模式"))
                    Spacer(minLength: 12)
                    FixedWidthSegmentedPicker(
                        selection: $settings.interfaceMode,
                        options: [
                            (settings.text("Auto", "自动"), InterfaceSelectionMode.automatic),
                            (settings.text("Manual", "手动"), InterfaceSelectionMode.manual)
                        ]
                    )
                    .frame(width: SidebarMetrics.trailingControlWidth)
                }
                .padding(.vertical, SidebarMetrics.rowVerticalPadding)
                .disabled(monitor.state.isRunning)

                if settings.interfaceMode == .automatic {
                    automaticInterfaceSummary

                    ForEach(monitor.availableInterfaces.filter { $0.isPhysical && $0.isActive }) { interface in
                        InterfaceRow(interface: interface, showsKind: false, settings: settings)
                    }
                } else {
                    ForEach(monitor.availableInterfaces) { interface in
                        Toggle(isOn: Binding(
                            get: { settings.selectedInterfaceNames.contains(interface.name) },
                            set: { settings.toggleInterface(interface.name, enabled: $0) }
                        )) {
                            InterfaceRow(interface: interface, showsKind: true, settings: settings)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(monitor.state.isRunning)
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text(settings.text("Interfaces", "网络接口"))
                    Button {
                        monitor.refreshInterfaces()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(settings.text("Refresh Interfaces", "刷新接口"))
                }
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
                    .padding(.vertical, SidebarMetrics.rowVerticalPadding)
                }

                HStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        Button {
                            settings.chooseOutputFolder()
                        } label: {
                            Text(settings.text("Change…", "更改…"))
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .disabled(monitor.state.isRunning)

                        Button {
                            settings.revealOutputFolder()
                        } label: {
                            Text(settings.text("Reveal", "显示"))
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(width: SidebarMetrics.trailingControlWidth)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 34)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Divider()
                if monitor.state.isRunning {
                    Button(role: .destructive) {
                        monitor.stop()
                    } label: {
                        Label(settings.text("Stop Logging", "结束记录"), systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        monitor.start(using: settings)
                    } label: {
                        Label(settings.text("Start Logging", "开始记录"), systemImage: "record.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(startIsDisabled)
                }
            }
            .padding([.horizontal, .bottom])
            .background(.bar)
        }
    }

    private var startIsDisabled: Bool {
        settings.outputFolderURL == nil
            || (settings.interfaceMode == .manual && settings.selectedInterfaceNames.isEmpty)
    }

    private var automaticInterfaceSummary: some View {
        let count = monitor.availableInterfaces.filter { $0.isPhysical && $0.isActive }.count
        return Label {
            Text(count == 0
                ? settings.text("No active physical interface", "没有活动物理接口")
                : settings.text(
                    "\(count) active physical \(count == 1 ? "interface" : "interfaces")",
                    "\(count) 个活动物理接口"
                ))
                .font(.caption)
        } icon: {
            Image(systemName: count == 0 ? "exclamationmark.triangle" : "point.3.connected.trianglepath.dotted")
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, SidebarMetrics.rowVerticalPadding)
    }
}

private struct DurationInputRow: View {
    let title: String
    @Binding var value: Double
    let unlimitedText: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(unlimitedText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 7) {
                TextField("", value: $value, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: SidebarMetrics.numericFieldWidth)
                    .onSubmit { value = min(max(value, 0), 168) }
                Text("h")
                    .foregroundStyle(.secondary)
                    .frame(width: 12, alignment: .leading)
                Stepper("", value: $value, in: 0...168, step: 1)
                    .labelsHidden()
            }
            .frame(width: SidebarMetrics.trailingControlWidth, alignment: .trailing)
        }
        .padding(.vertical, SidebarMetrics.rowVerticalPadding)
        .onChange(of: value) { newValue in
            if newValue < 0 || newValue > 168 {
                value = min(max(newValue, 0), 168)
            }
        }
    }
}

private struct IntervalInputRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
            Spacer(minLength: 12)
            HStack(spacing: 7) {
                TextField("", value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: SidebarMetrics.numericFieldWidth)
                    .onSubmit { value = min(max(value, 1), 3_600) }
                Text("s")
                    .foregroundStyle(.secondary)
                    .frame(width: 12, alignment: .leading)
                Stepper("", value: $value, in: 1...3_600, step: 1)
                    .labelsHidden()
            }
            .frame(width: SidebarMetrics.trailingControlWidth, alignment: .trailing)
        }
        .padding(.vertical, SidebarMetrics.rowVerticalPadding)
        .onChange(of: value) { newValue in
            if newValue < 1 || newValue > 3_600 {
                value = min(max(newValue, 1), 3_600)
            }
        }
    }
}

private struct InterfaceRow: View {
    let interface: NetworkInterfaceInfo
    let showsKind: Bool
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
                if showsKind {
                    Text(interfaceKind)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Circle()
                .fill(interface.isActive ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
                .help(interface.isActive ? settings.text("Active", "活动") : settings.text("Inactive", "未活动"))
        }
        .padding(.vertical, showsKind ? 5 : SidebarMetrics.rowVerticalPadding)
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
                        y: .value("Download", settings.speedUnit.value(fromBytesPerSecond: sample.downloadBytesPerSecond)),
                        series: .value("Series", "Download")
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Upload", settings.speedUnit.value(fromBytesPerSecond: sample.uploadBytesPerSecond)),
                        series: .value("Series", "Upload")
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
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        Form {
            Section(settings.text("General", "通用")) {
                Picker(settings.text("Language", "语言"), selection: $settings.language) {
                    Text(settings.text("Automatic", "自动")).tag(AppLanguage.automatic)
                    Text("English").tag(AppLanguage.english)
                    Text("简体中文").tag(AppLanguage.simplifiedChinese)
                }

                Picker(settings.text("Appearance", "外观"), selection: $settings.appearance) {
                    Text(settings.text("Follow System", "跟随系统")).tag(AppearanceMode.automatic)
                    Text(settings.text("Light", "浅色")).tag(AppearanceMode.light)
                    Text(settings.text("Dark", "深色")).tag(AppearanceMode.dark)
                }
            }

            Section(settings.text("Session Defaults", "记录默认配置")) {
                DurationInputRow(
                    title: settings.text("Duration", "记录时长"),
                    value: $settings.defaultDurationHours,
                    unlimitedText: settings.text("0 = unlimited", "0 表示不限时")
                )

                IntervalInputRow(
                    title: settings.text("Sample interval", "采样间隔"),
                    value: $settings.defaultSampleIntervalSeconds
                )

                Picker(settings.text("Speed unit", "速度单位"), selection: $settings.defaultSpeedUnit) {
                    Text("MB/s").tag(SpeedUnit.megabytesPerSecond)
                    Text("Mbps").tag(SpeedUnit.megabitsPerSecond)
                }
                .pickerStyle(.segmented)

                Text(settings.text(
                    "These values are loaded when the app starts. Changes made in the main window apply only to the current launch.",
                    "应用每次启动时都会载入这些值；主窗口中的临时修改只在本次启动期间有效。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(settings.text("Apply Defaults Now", "立即应用默认配置")) {
                    settings.applyDefaultsToCurrentSession()
                }
                .disabled(monitor.state.isRunning)
            }

            Section(settings.text("Files", "文件")) {
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
            }

            Section(settings.text("Updates", "更新")) {
                Toggle(
                    settings.text("Automatically check for updates", "自动检查更新"),
                    isOn: $settings.automaticallyChecksForUpdates
                )

                LabeledContent(
                    settings.text("Current version", "当前版本"),
                    value: UpdateChecker.displayedCurrentVersion
                )

                HStack(spacing: 10) {
                    Button(settings.text("Check for Updates…", "检查更新…")) {
                        Task {
                            await updateChecker.checkForUpdates(
                                manual: true,
                                presentWhenAvailable: false
                            )
                        }
                    }
                    .disabled(updateChecker.status == .checking)

                    if updateChecker.status == .checking {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if updateChecker.status == .updateAvailable {
                        Button(settings.text("View Release", "查看并下载")) {
                            updateChecker.openAvailableRelease()
                        }
                    }
                }

                if let statusText = updateStatusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(updateChecker.status == .failed ? Color.red : Color.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            settings.normalizeDefaultValues()
        }
    }

    private var updateStatusText: String? {
        switch updateChecker.status {
        case .idle, .checking:
            return nil
        case .upToDate:
            return settings.text("You’re up to date.", "当前已是最新正式版。")
        case .updateAvailable:
            guard let release = updateChecker.availableRelease else { return nil }
            return settings.text(
                "Version \(release.version) is available.",
                "发现新版本 \(release.version)。"
            )
        case .failed:
            return settings.text(
                "Unable to check for updates. Try again later.",
                "无法检查更新，请稍后重试。"
            )
        }
    }
}
