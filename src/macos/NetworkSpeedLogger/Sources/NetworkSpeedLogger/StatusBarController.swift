import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private weak var settings: AppSettings?
    private weak var monitor: NetworkMonitor?
    private weak var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var isInStatusBarMode = false
    private var shouldEnterStatusBarModeAfterLoginLaunch = false

    private let interfaceProvider = InterfaceProvider()
    private var speedSamplingTimer: DispatchSourceTimer?
    private var speedConfiguration: SpeedConfiguration?
    private var speedRateTracker = NetworkRateTracker()
    private var currentDownloadBytesPerSecond: Double = 0
    private var currentUploadBytesPerSecond: Double = 0

    // Keep the arrow pair centered while giving the two glyphs slightly more vertical separation.
    static let upperArrowCenterY: CGFloat = 12
    static let lowerArrowCenterY: CGFloat = 6

    private struct SpeedConfiguration: Equatable {
        let sampleIntervalSeconds: Int
        let interfaceMode: InterfaceSelectionMode
        let manualInterfaceNames: Set<String>
    }

    override init() {
        super.init()
    }

    deinit {
        speedSamplingTimer?.cancel()
    }

    func configure(settings: AppSettings, monitor: NetworkMonitor) {
        self.settings = settings
        self.monitor = monitor
        reconcileSpeedSampling()
        reconcileStatusItem()
        scheduleLoginLaunchPresentationIfReady()
    }

    func enterStatusBarModeAfterLoginLaunch() {
        shouldEnterStatusBarModeAfterLoginLaunch = true
        scheduleLoginLaunchPresentationIfReady()
    }

    func handleMainWindowClose(_ window: NSWindow) -> Bool {
        guard settings?.keepsRunningInMenuBar == true else { return false }
        mainWindow = window

        DispatchQueue.main.async { [weak self] in
            self?.enterStatusBarMode()
        }
        return true
    }

    func handleMainWindowBecameActive(_ window: NSWindow) {
        mainWindow = window
        if isInStatusBarMode {
            leaveStatusBarMode()
        } else {
            reconcileStatusItem()
        }
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        if isInStatusBarMode, window.isVisible {
            leaveStatusBarMode()
        } else {
            reconcileStatusItem()
        }
        scheduleLoginLaunchPresentationIfReady()
    }

    private func scheduleLoginLaunchPresentationIfReady() {
        guard shouldEnterStatusBarModeAfterLoginLaunch,
              settings != nil,
              mainWindow != nil else { return }

        shouldEnterStatusBarModeAfterLoginLaunch = false
        DispatchQueue.main.async { [weak self] in
            self?.enterStatusBarMode()
        }
    }

    func handleApplicationReopen() -> Bool {
        guard isInStatusBarMode || mainWindow?.isVisible != true else { return false }
        restoreMainWindow()
        return true
    }

    private func enterStatusBarMode() {
        isInStatusBarMode = true
        reconcileStatusItem()

        for window in NSApp.windows where window.isVisible {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    private func leaveStatusBarMode() {
        guard isInStatusBarMode else {
            reconcileStatusItem()
            return
        }

        isInStatusBarMode = false
        NSApp.setActivationPolicy(.regular)
        reconcileStatusItem()
    }

    private func reconcileStatusItem() {
        guard let settings else { return }
        let shouldShow = isInStatusBarMode || settings.showsNetworkSpeedInMenuBar

        if shouldShow {
            installStatusItemIfNeeded()
            refreshStatusItemAppearance()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.toolTip = settings?.text("Network Speed Logger", "Network Speed Logger")
            button.target = self
            button.action = #selector(statusItemSelected(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Network Speed Logger")
        }
        statusItem = item
    }

    private func refreshStatusItemAppearance() {
        guard let statusItem, let button = statusItem.button, let settings else { return }

        if settings.showsNetworkSpeedInMenuBar {
            let image = Self.makeSpeedStatusBarImage(
                uploadBytesPerSecond: currentUploadBytesPerSecond,
                downloadBytesPerSecond: currentDownloadBytesPerSecond,
                unit: settings.menuBarSpeedUnit,
                activityThresholdBytesPerSecond:
                    Double(settings.menuBarSpeedActivityThresholdKilobytesPerSecond) * 1_000
            )
            button.image = image
            statusItem.length = image.size.width + 4
            button.toolTip = settings.text(
                "Upload: \(Self.formatSpeed(currentUploadBytesPerSecond, unit: settings.menuBarSpeedUnit))\nDownload: \(Self.formatSpeed(currentDownloadBytesPerSecond, unit: settings.menuBarSpeedUnit))",
                "上传：\(Self.formatSpeed(currentUploadBytesPerSecond, unit: settings.menuBarSpeedUnit))\n下载：\(Self.formatSpeed(currentDownloadBytesPerSecond, unit: settings.menuBarSpeedUnit))"
            )
        } else {
            button.image = Self.makeStatusBarImage()
            statusItem.length = NSStatusItem.squareLength
            button.toolTip = settings.text("Network Speed Logger", "Network Speed Logger")
        }
    }

    @objc private func statusItemSelected(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            presentMenu()
        } else {
            restoreMainWindow()
        }
    }

    private func presentMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let startItem = NSMenuItem(
            title: settings?.text("Start", "开始") ?? "Start",
            action: #selector(startLogging),
            keyEquivalent: ""
        )
        startItem.target = self
        startItem.isEnabled = canStartLogging
        menu.addItem(startItem)

        let stopItem = NSMenuItem(
            title: settings?.text("Stop", "停止") ?? "Stop",
            action: #selector(stopLogging),
            keyEquivalent: ""
        )
        stopItem.target = self
        stopItem.isEnabled = monitor?.state.isRunning == true
        menu.addItem(stopItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: settings?.text("Quit", "退出") ?? "Quit",
            action: #selector(quitApplication),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private var canStartLogging: Bool {
        guard let settings, monitor?.state.isRunning != true else { return false }
        return settings.outputFolderURL != nil
            && (settings.interfaceMode != .manual || !settings.selectedInterfaceNames.isEmpty)
    }

    @objc private func startLogging() {
        guard canStartLogging, let settings else { return }
        monitor?.start(using: settings)
    }

    @objc private func stopLogging() {
        monitor?.stop()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func restoreMainWindow() {
        if isInStatusBarMode {
            leaveStatusBarMode()
        }

        NSApp.unhide(nil)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reconcileStatusItem()
    }

    private func reconcileSpeedSampling() {
        guard let settings, settings.showsNetworkSpeedInMenuBar else {
            stopSpeedSampling()
            return
        }

        let configuration = SpeedConfiguration(
            sampleIntervalSeconds: min(max(settings.menuBarSpeedSampleIntervalSeconds, 1), 3_600),
            interfaceMode: settings.menuBarSpeedInterfaceMode,
            manualInterfaceNames: settings.menuBarSpeedSelectedInterfaceNames
        )

        guard configuration != speedConfiguration || speedSamplingTimer == nil else {
            refreshStatusItemAppearance()
            return
        }

        startSpeedSampling(configuration: configuration)
    }

    private func startSpeedSampling(configuration: SpeedConfiguration) {
        speedSamplingTimer?.cancel()
        speedConfiguration = configuration

        let capture = interfaceProvider.capture()
        let selectedNames = interfaceProvider.selectedNames(
            from: capture,
            mode: configuration.interfaceMode,
            manuallySelected: configuration.manualInterfaceNames
        )
        speedRateTracker.reset(
            counters: capture.counters,
            selectedNames: selectedNames,
            at: Date()
        )
        currentDownloadBytesPerSecond = 0
        currentUploadBytesPerSecond = 0
        refreshStatusItemAppearance()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval = DispatchTimeInterval.seconds(configuration.sampleIntervalSeconds)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(min(configuration.sampleIntervalSeconds * 50, 250))
        )
        timer.setEventHandler { [weak self] in
            self?.captureSpeedSample(configuration: configuration)
        }
        speedSamplingTimer = timer
        timer.resume()
    }

    private func stopSpeedSampling() {
        speedSamplingTimer?.cancel()
        speedSamplingTimer = nil
        speedConfiguration = nil
        speedRateTracker = NetworkRateTracker()
        currentDownloadBytesPerSecond = 0
        currentUploadBytesPerSecond = 0
    }

    private func captureSpeedSample(configuration: SpeedConfiguration) {
        let now = Date()
        let capture = interfaceProvider.capture()
        let selectedNames = interfaceProvider.selectedNames(
            from: capture,
            mode: configuration.interfaceMode,
            manuallySelected: configuration.manualInterfaceNames
        )
        let discontinuityThreshold = max(
            Double(configuration.sampleIntervalSeconds) * 3,
            Double(configuration.sampleIntervalSeconds) + 10
        )

        let rate = speedRateTracker.sample(
            counters: capture.counters,
            selectedNames: selectedNames,
            at: now,
            maximumInterval: discontinuityThreshold
        )
        currentDownloadBytesPerSecond = rate.downloadBytesPerSecond
        currentUploadBytesPerSecond = rate.uploadBytesPerSecond
        refreshStatusItemAppearance()
    }

    private static func makeStatusBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            drawArrow(
                center: NSPoint(x: 6, y: upperArrowCenterY),
                width: 5.4,
                height: 7,
                pointsUp: true,
                alpha: 1
            )
            drawArrow(
                center: NSPoint(x: 12, y: lowerArrowCenterY),
                width: 5.4,
                height: 7,
                pointsUp: false,
                alpha: 1
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    static func makeSpeedStatusBarImage(
        uploadBytesPerSecond: Double,
        downloadBytesPerSecond: Double,
        unit: MenuBarSpeedUnit,
        activityThresholdBytesPerSecond: Double
    ) -> NSImage {
        let uploadText = formatSpeed(uploadBytesPerSecond, unit: unit)
        let downloadText = formatSpeed(downloadBytesPerSecond, unit: unit)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        // Reserve the widest possible three-digit presentation so the status
        // item and every neighboring menu-bar click target stay stationary as
        // the value and SI prefix change.
        let fixedWidthSamples = [
            "0.00 B/s", "0.00 KB/s", "0.00 MB/s", "0.00 GB/s", "0.00 TB/s",
            "0.00 b/s", "0.00 Kb/s", "0.00 Mb/s", "0.00 Gb/s", "0.00 Tb/s"
        ]
        let textWidth = ceil(fixedWidthSamples.reduce(CGFloat.zero) { width, sample in
            max(width, (sample as NSString).size(withAttributes: attributes).width)
        })
        let textToIconSpacing: CGFloat = 3
        let iconWidth: CGFloat = 18
        let imageSize = NSSize(
            width: max(34, textWidth + textToIconSpacing + iconWidth),
            height: 18
        )

        let image = NSImage(size: imageSize, flipped: false) { _ in
            (uploadText as NSString).draw(
                in: NSRect(x: 0, y: 9, width: textWidth, height: 9),
                withAttributes: attributes
            )
            (downloadText as NSString).draw(
                in: NSRect(x: 0, y: 0, width: textWidth, height: 9),
                withAttributes: attributes
            )

            let iconOriginX = textWidth + textToIconSpacing
            drawArrow(
                center: NSPoint(x: iconOriginX + 6, y: upperArrowCenterY),
                width: 5.4,
                height: 7,
                pointsUp: true,
                alpha: uploadBytesPerSecond >= activityThresholdBytesPerSecond ? 1 : 0.32
            )
            drawArrow(
                center: NSPoint(x: iconOriginX + 12, y: lowerArrowCenterY),
                width: 5.4,
                height: 7,
                pointsUp: false,
                alpha: downloadBytesPerSecond >= activityThresholdBytesPerSecond ? 1 : 0.32
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    static func formatSpeed(
        _ bytesPerSecond: Double,
        unit: MenuBarSpeedUnit
    ) -> String {
        var value = max(0, bytesPerSecond)
        let suffixes: [String]

        switch unit {
        case .byte:
            suffixes = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        case .bit:
            value *= 8
            suffixes = ["b/s", "Kb/s", "Mb/s", "Gb/s", "Tb/s"]
        }

        var suffixIndex = 0
        // Promote just before rounding would produce a four-digit value such
        // as 1000 KB/s, keeping the numeric field at three digits.
        while value >= 999.5, suffixIndex < suffixes.count - 1 {
            value /= 1_000
            suffixIndex += 1
        }

        let number: String
        if value >= 99.95 {
            number = String(format: "%.0f", value)
        } else if value >= 9.995 {
            number = String(format: "%.1f", value)
        } else {
            number = String(format: "%.2f", value)
        }
        return "\(number) \(suffixes[suffixIndex])"
    }

    private static func drawArrow(
        center: NSPoint,
        width: CGFloat,
        height: CGFloat,
        pointsUp: Bool,
        alpha: CGFloat
    ) {
        let halfWidth = width / 2
        let halfHeight = height / 2
        let shaftHalfWidth = width * 0.17
        let top = center.y + halfHeight
        let bottom = center.y - halfHeight
        let headBase = pointsUp ? top - height * 0.47 : bottom + height * 0.47

        let points: [NSPoint]
        if pointsUp {
            points = [
                NSPoint(x: center.x - shaftHalfWidth, y: bottom),
                NSPoint(x: center.x + shaftHalfWidth, y: bottom),
                NSPoint(x: center.x + shaftHalfWidth, y: headBase),
                NSPoint(x: center.x + halfWidth, y: headBase),
                NSPoint(x: center.x, y: top),
                NSPoint(x: center.x - halfWidth, y: headBase),
                NSPoint(x: center.x - shaftHalfWidth, y: headBase)
            ]
        } else {
            points = [
                NSPoint(x: center.x - shaftHalfWidth, y: top),
                NSPoint(x: center.x + shaftHalfWidth, y: top),
                NSPoint(x: center.x + shaftHalfWidth, y: headBase),
                NSPoint(x: center.x + halfWidth, y: headBase),
                NSPoint(x: center.x, y: bottom),
                NSPoint(x: center.x - halfWidth, y: headBase),
                NSPoint(x: center.x - shaftHalfWidth, y: headBase)
            ]
        }

        let color = NSColor.black.withAlphaComponent(alpha)
        color.setFill()
        color.setStroke()

        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.close()
        path.lineJoinStyle = .round
        path.lineWidth = 0.8
        path.fill()
        path.stroke()
    }
}

private final class MainWindowDelegateProxy: NSObject, NSWindowDelegate {
    let forwardingDelegate: NSWindowDelegate?
    weak var controller: StatusBarController?

    init(forwardingDelegate: NSWindowDelegate?, controller: StatusBarController) {
        self.forwardingDelegate = forwardingDelegate
        self.controller = controller
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if controller?.handleMainWindowClose(sender) == true {
            return false
        }
        return forwardingDelegate?.windowShouldClose?(sender) ?? true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            controller?.handleMainWindowBecameActive(window)
        }
        forwardingDelegate?.windowDidBecomeKey?(notification)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            controller?.handleMainWindowBecameActive(window)
        }
        forwardingDelegate?.windowDidBecomeMain?(notification)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || forwardingDelegate?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if forwardingDelegate?.responds(to: selector) == true {
            return forwardingDelegate
        }
        return super.forwardingTarget(for: selector)
    }
}

struct MainWindowBridge: NSViewRepresentable {
    let controller: StatusBarController
    let settings: AppSettings
    let monitor: NetworkMonitor

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSView {
        controller.configure(settings: settings, monitor: monitor)
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        controller.configure(settings: settings, monitor: monitor)
        context.coordinator.attach(to: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private let controller: StatusBarController
        private weak var window: NSWindow?
        private var delegateProxy: MainWindowDelegateProxy?

        init(controller: StatusBarController) {
            self.controller = controller
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                self.controller.registerMainWindow(window)
                guard self.window !== window || window.delegate !== self.delegateProxy else { return }

                self.detach()
                let proxy = MainWindowDelegateProxy(
                    forwardingDelegate: window.delegate,
                    controller: self.controller
                )
                self.window = window
                self.delegateProxy = proxy
                window.identifier = NSUserInterfaceItemIdentifier("NetworkSpeedLogger.MainWindow")
                window.delegate = proxy
            }
        }

        func detach() {
            if let window, window.delegate === delegateProxy {
                window.delegate = delegateProxy?.forwardingDelegate
            }
            window = nil
            delegateProxy = nil
        }
    }
}
