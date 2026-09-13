import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private weak var settings: AppSettings?
    private weak var monitor: NetworkMonitor?
    private weak var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var isInStatusBarMode = false

    override init() {
        super.init()
    }

    func configure(settings: AppSettings, monitor: NetworkMonitor) {
        self.settings = settings
        self.monitor = monitor
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
        guard isInStatusBarMode else { return }
        mainWindow = window
        leaveStatusBarMode()
    }

    private func enterStatusBarMode() {
        if !isInStatusBarMode {
            isInStatusBarMode = true
            installStatusItem()
        }

        for window in NSApp.windows where window.isVisible {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.makeStatusBarImage()
            button.imagePosition = .imageOnly
            button.toolTip = settings?.text("Network Speed Logger", "Network Speed Logger")
            button.target = self
            button.action = #selector(statusItemSelected(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Network Speed Logger")
        }
        statusItem = item
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

    private func leaveStatusBarMode() {
        guard isInStatusBarMode else { return }
        isInStatusBarMode = false

        NSApp.setActivationPolicy(.regular)
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func restoreMainWindow() {
        guard isInStatusBarMode else { return }
        leaveStatusBarMode()

        NSApp.unhide(nil)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func makeStatusBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            drawArrow(
                center: NSPoint(x: 6, y: 11.5),
                width: 5.4,
                height: 7,
                pointsUp: true
            )
            drawArrow(
                center: NSPoint(x: 12, y: 6.5),
                width: 5.4,
                height: 7,
                pointsUp: false
            )
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawArrow(
        center: NSPoint,
        width: CGFloat,
        height: CGFloat,
        pointsUp: Bool
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
