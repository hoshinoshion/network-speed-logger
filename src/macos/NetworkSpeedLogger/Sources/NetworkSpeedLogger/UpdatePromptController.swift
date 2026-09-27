import AppKit
import Combine
import SwiftUI

@MainActor
final class UpdatePromptController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("NetworkSpeedLogger.UpdatePrompt")

    private let settings: AppSettings
    private let updateChecker: UpdateChecker
    private var subscription: AnyCancellable?
    private var panel: NSPanel?
    private var shownVersion: String?

    init(settings: AppSettings, updateChecker: UpdateChecker) {
        self.settings = settings
        self.updateChecker = updateChecker
        super.init()

        subscription = updateChecker.$presentedRelease.sink { [weak self] release in
            self?.present(release)
        }
    }

    private func present(_ release: UpdateReleaseInfo?) {
        guard let release else {
            closePanelForModelChange()
            return
        }

        if let panel, shownVersion == release.version {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        closePanelForModelChange()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.identifier = Self.windowIdentifier
        panel.title = settings.text("Update Available", "发现新版本")
        panel.contentViewController = NSHostingController(rootView: UpdatePromptView(
            settings: settings,
            updateChecker: updateChecker,
            release: release
        ))
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.delegate = self
        panel.center()

        shownVersion = release.version
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.writePresentationVerificationIfRequested()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        panel = nil
        shownVersion = nil
        if updateChecker.presentedRelease != nil {
            updateChecker.deferPresentedRelease()
        }
    }

    private func closePanelForModelChange() {
        let previous = panel
        panel = nil
        shownVersion = nil
        previous?.delegate = nil
        previous?.close()
    }

    private func writePresentationVerificationIfRequested() {
        guard let path = ProcessInfo.processInfo.environment[
            "NETWORK_SPEED_LOGGER_UPDATE_PROMPT_TEST_RESULT"
        ], let panel else { return }

        let mainWindowVisible = NSApp.windows.contains {
            $0.identifier?.rawValue == "NetworkSpeedLogger.MainWindow" && $0.isVisible
        }
        let result = [
            "promptVisible=\(panel.isVisible)",
            "promptCanBecomeKey=\(panel.canBecomeKey)",
            "promptIsKey=\(panel.isKeyWindow)",
            "promptWidth=\(Int(panel.frame.width))",
            "visibleWindowCount=\(NSApp.windows.filter(\.isVisible).count)",
            "mainWindowVisible=\(mainWindowVisible)",
            "activationPolicyAccessory=\(NSApp.activationPolicy() == .accessory)"
        ].joined(separator: "\n") + "\n"
        try? result.write(toFile: path, atomically: true, encoding: .utf8)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.panel?.performClose(nil)
            let dismissal = [
                "dismissalClearedRelease=\(self?.updateChecker.presentedRelease == nil)",
                "promptClosed=\(self?.panel == nil)",
                "stillInMenuBarMode=\(NSApp.activationPolicy() == .accessory)"
            ].joined(separator: "\n") + "\n"
            try? (result + dismissal).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

private struct UpdatePromptView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateChecker: UpdateChecker
    let release: UpdateReleaseInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(settings.text("Update Available", "发现新版本"))
                .font(.headline)
            Text(settings.text(
                "Network Speed Logger \(release.version) is available. You are using \(UpdateChecker.displayedCurrentVersion).",
                "Network Speed Logger \(release.version) 已发布，当前版本为 \(UpdateChecker.displayedCurrentVersion)。"
            ))
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(settings.text("Skip This Version", "跳过此版本")) {
                    updateChecker.skipPresentedRelease()
                }
                Spacer()
                Button(settings.text("Later", "稍后")) {
                    updateChecker.deferPresentedRelease()
                }
                Button(settings.text("View Release", "查看并下载")) {
                    updateChecker.openPresentedRelease()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440, height: 190)
    }
}
