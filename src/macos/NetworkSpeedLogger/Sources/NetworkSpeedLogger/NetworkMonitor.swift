import AppKit
import Foundation

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var state: MonitorState = .idle
    @Published private(set) var availableInterfaces: [NetworkInterfaceInfo] = []
    @Published private(set) var activeInterfaceNames: [String] = []
    @Published private(set) var samples: [SpeedSample] = []
    @Published private(set) var statistics = SessionStatistics()
    @Published private(set) var currentDownloadBytesPerSecond: Double = 0
    @Published private(set) var currentUploadBytesPerSecond: Double = 0
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var eventMessage = ""
    @Published private(set) var csvURL: URL?
    @Published private(set) var summaryURL: URL?

    private let provider = InterfaceProvider()
    private var samplingTask: Task<Void, Never>?
    private var writer: SessionWriter?
    private var previousCounters: [String: InterfaceCounter] = [:]
    private var configuration: Configuration?
    private var startDate: Date?
    private var lastSampleDate: Date?
    private var isSystemSleeping = false
    private var workspaceObservers: [NSObjectProtocol] = []

    private struct Configuration {
        let durationHours: Double
        let sampleIntervalSeconds: Int
        let interfaceMode: InterfaceSelectionMode
        let manualInterfaceNames: Set<String>
        let usesChinese: Bool
    }

    init() {
        refreshInterfaces()
        installPowerObservers()
    }

    deinit {
        samplingTask?.cancel()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func refreshInterfaces() {
        availableInterfaces = provider.capture().interfaces
    }

    func start(using settings: AppSettings) {
        guard !state.isRunning, let outputFolder = settings.outputFolderURL else { return }

        let config = Configuration(
            durationHours: max(0, settings.durationHours),
            sampleIntervalSeconds: min(max(settings.sampleIntervalSeconds, 1), 3_600),
            interfaceMode: settings.interfaceMode,
            manualInterfaceNames: settings.selectedInterfaceNames,
            usesChinese: settings.usesChinese
        )
        let initialCapture = provider.capture()
        availableInterfaces = initialCapture.interfaces
        let selectedNames = provider.selectedNames(
            from: initialCapture,
            mode: config.interfaceMode,
            manuallySelected: config.manualInterfaceNames
        )

        guard !selectedNames.isEmpty else {
            state = .failed(settings.text(
                "No monitorable interface is available. Connect a physical interface or select one manually.",
                "没有可监控的网络接口。请连接物理网卡，或手动选择接口。"
            ))
            return
        }

        let now = Date()
        do {
            let newWriter = try SessionWriter(outputFolder: outputFolder, startDate: now, usesChinese: config.usesChinese)
            writer = newWriter
            csvURL = newWriter.csvURL
            summaryURL = newWriter.summaryURL
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        configuration = config
        startDate = now
        lastSampleDate = now
        previousCounters = counters(for: selectedNames, in: initialCapture)
        activeInterfaceNames = selectedNames
        samples = []
        statistics = SessionStatistics()
        currentDownloadBytesPerSecond = 0
        currentUploadBytesPerSecond = 0
        elapsedSeconds = 0
        eventMessage = config.usesChinese ? "正在记录网络流量" : "Logging network traffic"
        isSystemSleeping = false
        state = .running

        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let nanoseconds = UInt64(config.sampleIntervalSeconds) * 1_000_000_000
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                self.captureSample()
            }
        }
    }

    func stop(reason: SessionStopReason = .user) {
        guard state.isRunning else { return }
        samplingTask?.cancel()
        samplingTask = nil

        let endDate = Date()
        do {
            try writer?.finish(endDate: endDate, statistics: statistics, reason: reason)
            switch reason {
            case .error(let message):
                state = .failed(message)
            default:
                state = .finished
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
        writer = nil
        currentDownloadBytesPerSecond = 0
        currentUploadBytesPerSecond = 0
        activeInterfaceNames = []
        previousCounters = [:]
    }

    private func captureSample() {
        guard state.isRunning,
              !isSystemSleeping,
              let config = configuration,
              let startDate,
              let previousDate = lastSampleDate else { return }

        let now = Date()
        let interval = now.timeIntervalSince(previousDate)
        let elapsed = now.timeIntervalSince(startDate)
        elapsedSeconds = elapsed

        if config.durationHours > 0, elapsed >= config.durationHours * 3_600 {
            captureNormalSample(now: now, interval: interval, elapsed: elapsed, configuration: config)
            stop(reason: .durationCompleted)
            return
        }

        let discontinuityThreshold = max(Double(config.sampleIntervalSeconds) * 3, Double(config.sampleIntervalSeconds) + 10)
        guard interval > 0, interval <= discontinuityThreshold else {
            rebaseline(after: now, configuration: config)
            eventMessage = config.usesChinese
                ? "检测到睡眠、唤醒或系统时间变化，已安全恢复采样"
                : "Sampling resumed safely after sleep, wake, or a clock change"
            return
        }

        captureNormalSample(now: now, interval: interval, elapsed: elapsed, configuration: config)
    }

    private func captureNormalSample(
        now: Date,
        interval: TimeInterval,
        elapsed: TimeInterval,
        configuration config: Configuration
    ) {
        let capture = provider.capture()
        availableInterfaces = capture.interfaces
        let selectedNames = provider.selectedNames(
            from: capture,
            mode: config.interfaceMode,
            manuallySelected: config.manualInterfaceNames
        )

        var receivedDelta: UInt64 = 0
        var sentDelta: UInt64 = 0

        for (name, previous) in previousCounters {
            guard let current = capture.counters[name] else { continue }
            if current.receivedBytes >= previous.receivedBytes {
                receivedDelta = receivedDelta.addingWithoutOverflow(current.receivedBytes - previous.receivedBytes)
            }
            if current.sentBytes >= previous.sentBytes {
                sentDelta = sentDelta.addingWithoutOverflow(current.sentBytes - previous.sentBytes)
            }
        }

        let download = Double(receivedDelta) / interval
        let upload = Double(sentDelta) / interval
        let sample = SpeedSample(
            timestamp: now,
            elapsedSeconds: elapsed,
            downloadBytesPerSecond: download,
            uploadBytesPerSecond: upload,
            activeInterfaces: selectedNames
        )

        do {
            try writer?.append(sample)
        } catch {
            stop(reason: .error(error.localizedDescription))
            return
        }

        samples.append(sample)
        if samples.count > 600 {
            samples.removeFirst(samples.count - 600)
        }
        statistics.record(
            receivedBytes: receivedDelta,
            sentBytes: sentDelta,
            interval: interval,
            downloadBytesPerSecond: download,
            uploadBytesPerSecond: upload
        )
        currentDownloadBytesPerSecond = download
        currentUploadBytesPerSecond = upload
        activeInterfaceNames = selectedNames
        previousCounters = counters(for: selectedNames, in: capture)
        lastSampleDate = now
        eventMessage = selectedNames.isEmpty
            ? (config.usesChinese ? "等待网络接口连接" : "Waiting for a network interface")
            : (config.usesChinese ? "正在记录网络流量" : "Logging network traffic")
    }

    private func rebaseline(after date: Date, configuration config: Configuration) {
        let capture = provider.capture()
        availableInterfaces = capture.interfaces
        let selectedNames = provider.selectedNames(
            from: capture,
            mode: config.interfaceMode,
            manuallySelected: config.manualInterfaceNames
        )
        previousCounters = counters(for: selectedNames, in: capture)
        activeInterfaceNames = selectedNames
        lastSampleDate = date
        currentDownloadBytesPerSecond = 0
        currentUploadBytesPerSecond = 0
    }

    private func counters(for names: [String], in capture: InterfaceCapture) -> [String: InterfaceCounter] {
        Dictionary(uniqueKeysWithValues: names.compactMap { name in
            capture.counters[name].map { (name, $0) }
        })
    }

    private func installPowerObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.isRunning else { return }
                self.isSystemSleeping = true
                self.eventMessage = self.configuration?.usesChinese == true
                    ? "Mac 即将进入睡眠，已暂停采样"
                    : "Sampling paused while the Mac sleeps"
            }
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.isRunning, let config = self.configuration else { return }
                self.isSystemSleeping = false
                let now = Date()
                if let startDate = self.startDate,
                   config.durationHours > 0,
                   now.timeIntervalSince(startDate) >= config.durationHours * 3_600 {
                    self.stop(reason: .durationCompleted)
                    return
                }
                self.rebaseline(after: now, configuration: config)
                self.eventMessage = config.usesChinese
                    ? "Mac 已唤醒，已重新建立流量基线"
                    : "The Mac woke and traffic baselines were refreshed"
            }
        })
    }
}
