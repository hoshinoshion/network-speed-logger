import AppKit
import SwiftUI

@main
struct NetworkSpeedLoggerApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var monitor = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            RootView(settings: settings, monitor: monitor)
                .frame(minWidth: 1_040, minHeight: 700)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    monitor.stop(reason: .applicationQuit)
                }
        }
        .defaultSize(width: 1_180, height: 780)
        .windowStyle(.titleBar)
        .commands {
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

                Button(settings.text("Reveal Output Folder", "在访达中显示保存目录")) {
                    settings.revealOutputFolder()
                }
                .disabled(settings.outputFolderURL == nil)
            }
        }

        Settings {
            PreferencesView(settings: settings, monitor: monitor)
                .frame(width: 520)
                .padding(24)
        }
    }
}
