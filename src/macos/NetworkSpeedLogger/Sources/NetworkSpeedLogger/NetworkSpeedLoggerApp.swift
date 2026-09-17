import AppKit
import CoreServices
import SwiftUI

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController? {
        didSet { deliverLoginItemLaunchIfReady() }
    }
    private(set) var launchedAsLoginItem = false
    private var deliveredLoginItemLaunch = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        captureLoginItemLaunch()
        deliverLoginItemLaunchIfReady()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        captureLoginItemLaunch()
        deliverLoginItemLaunchIfReady()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard statusBarController?.handleApplicationReopen() == true else {
            return true
        }
        return false
    }

    private func captureLoginItemLaunch() {
        if ProcessInfo.processInfo.environment["NETWORK_SPEED_LOGGER_LOGIN_ITEM_TEST"] == "1" {
            launchedAsLoginItem = true
            return
        }

        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEOpenApplication,
              event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
                == keyAELaunchedAsLogInItem else { return }
        launchedAsLoginItem = true
    }

    private func deliverLoginItemLaunchIfReady() {
        guard launchedAsLoginItem,
              !deliveredLoginItemLaunch,
              let statusBarController else { return }

        deliveredLoginItemLaunch = true
        statusBarController.enterStatusBarModeAfterLoginLaunch()
        if ProcessInfo.processInfo.environment[
            "NETWORK_SPEED_LOGGER_LOGIN_ITEM_RESTORE_TEST"
        ] == "1" {
            statusBarController.restoreMainWindowAfterLoginLaunchForTesting()
        }
    }
}

@main
@MainActor
struct NetworkSpeedLoggerApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var monitor: NetworkMonitor
    @StateObject private var updateChecker: UpdateChecker
    @StateObject private var statusBarController: StatusBarController

    init() {
        let settings = AppSettings()
        let monitor = NetworkMonitor()
        let updateChecker = UpdateChecker()
        let statusBarController = StatusBarController()

        statusBarController.configure(
            settings: settings,
            monitor: monitor,
            updateChecker: updateChecker
        )

        _settings = StateObject(wrappedValue: settings)
        _monitor = StateObject(wrappedValue: monitor)
        _updateChecker = StateObject(wrappedValue: updateChecker)
        _statusBarController = StateObject(wrappedValue: statusBarController)
        applicationDelegate.statusBarController = statusBarController

        if ProcessInfo.processInfo.environment["NETWORK_SPEED_LOGGER_LOGIN_ITEM_TEST"] == "1" {
            if let resultPath = ProcessInfo.processInfo.environment[
                "NETWORK_SPEED_LOGGER_LOGIN_ITEM_TEST_RESULT"
            ] {
                try? "appInitialized=true\n".write(
                    toFile: resultPath,
                    atomically: true,
                    encoding: .utf8
                )
            }
            statusBarController.enterStatusBarModeAfterLoginLaunch()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                settings: settings,
                monitor: monitor,
                updateChecker: updateChecker,
                statusBarController: statusBarController
            )
                .frame(minWidth: 1_040, minHeight: 700)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    monitor.stop(reason: .applicationQuit)
                }
        }
        .defaultSize(width: 1_180, height: 780)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(settings.text("Check for Updates…", "检查更新…")) {
                    Task { await updateChecker.checkForUpdates(manual: true) }
                }
                .disabled(updateChecker.status == .checking)
            }

            CommandMenu(settings.text("Session", "记录")) {
                if monitor.state.isRunning {
                    Button(settings.text("Stop Logging", "结束记录")) {
                        monitor.stop()
                    }
                    .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button(settings.text("Start Logging", "开始记录")) {
                        monitor.start(using: settings)
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(settings.outputFolderURL == nil)
                }

                Divider()

                Button(settings.text("Open Output Folder", "打开输出目录")) {
                    settings.openOutputFolder()
                }
                .disabled(settings.outputFolderURL == nil)
            }
        }

        Settings {
            PreferencesView(settings: settings, monitor: monitor, updateChecker: updateChecker)
        }
        .windowResizability(.contentSize)
    }
}
