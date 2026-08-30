import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let language = "language"
        static let appearance = "appearance"
        static let defaultSpeedUnit = "defaultSpeedUnit.v2"
        static let interfaceMode = "interfaceMode"
        static let selectedInterfaces = "selectedInterfaces"
        static let defaultDurationHours = "defaultDurationHours.v2"
        static let defaultSampleInterval = "defaultSampleInterval.v2"
        static let outputFolderBookmark = "outputFolderBookmark"
        static let automaticallyChecksForUpdates = "automaticallyChecksForUpdates"
    }

    private let defaults: UserDefaults
    private var isAccessingOutputFolder = false

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    @Published var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    @Published var speedUnit: SpeedUnit

    @Published var interfaceMode: InterfaceSelectionMode {
        didSet { defaults.set(interfaceMode.rawValue, forKey: Key.interfaceMode) }
    }

    @Published var selectedInterfaceNames: Set<String> {
        didSet { defaults.set(Array(selectedInterfaceNames).sorted(), forKey: Key.selectedInterfaces) }
    }

    @Published var durationHours: Double

    @Published var sampleIntervalSeconds: Int

    @Published var defaultSpeedUnit: SpeedUnit {
        didSet { defaults.set(defaultSpeedUnit.rawValue, forKey: Key.defaultSpeedUnit) }
    }

    @Published var defaultDurationHours: Double {
        didSet { defaults.set(defaultDurationHours, forKey: Key.defaultDurationHours) }
    }

    @Published var defaultSampleIntervalSeconds: Int {
        didSet { defaults.set(defaultSampleIntervalSeconds, forKey: Key.defaultSampleInterval) }
    }

    @Published var automaticallyChecksForUpdates: Bool {
        didSet { defaults.set(automaticallyChecksForUpdates, forKey: Key.automaticallyChecksForUpdates) }
    }

    @Published private(set) var outputFolderURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedDefaultDuration = (defaults.object(forKey: Key.defaultDurationHours) as? Double)
            .map { min(max($0, 0), 168) } ?? 24
        let storedDefaultInterval = (defaults.object(forKey: Key.defaultSampleInterval) as? Int)
            .map { min(max($0, 1), 3_600) } ?? 15
        let storedDefaultSpeedUnit = SpeedUnit(
            rawValue: defaults.string(forKey: Key.defaultSpeedUnit) ?? ""
        ) ?? .megabytesPerSecond

        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .automatic
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .automatic
        interfaceMode = InterfaceSelectionMode(rawValue: defaults.string(forKey: Key.interfaceMode) ?? "") ?? .automatic
        selectedInterfaceNames = Set(defaults.stringArray(forKey: Key.selectedInterfaces) ?? [])
        defaultDurationHours = storedDefaultDuration
        defaultSampleIntervalSeconds = storedDefaultInterval
        defaultSpeedUnit = storedDefaultSpeedUnit
        durationHours = storedDefaultDuration
        sampleIntervalSeconds = storedDefaultInterval
        speedUnit = storedDefaultSpeedUnit
        automaticallyChecksForUpdates = (defaults.object(forKey: Key.automaticallyChecksForUpdates) as? Bool) ?? true

        restoreOutputFolder()
        applyAppearance()
    }

    var usesChinese: Bool {
        switch language {
        case .english:
            return false
        case .simplifiedChinese:
            return true
        case .automatic:
            guard let preferred = Locale.preferredLanguages.first?.lowercased() else { return false }
            return preferred.hasPrefix("zh-hans") || preferred.hasPrefix("zh-cn") || preferred.hasPrefix("zh-sg")
        }
    }

    func text(_ english: String, _ chinese: String) -> String {
        usesChinese ? chinese : english
    }

    private func applyAppearance() {
        let appKitAppearance: NSAppearance?
        switch appearance {
        case .automatic:
            appKitAppearance = nil
        case .light:
            appKitAppearance = NSAppearance(named: .aqua)
        case .dark:
            appKitAppearance = NSAppearance(named: .darkAqua)
        }

        NSApp.appearance = appKitAppearance
        for window in NSApp.windows {
            window.appearance = appKitAppearance
            window.toolbar?.validateVisibleItems()
            window.contentView?.needsDisplay = true
        }
    }

    @discardableResult
    func chooseOutputFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.title = text("Choose where session files are saved", "选择记录文件的保存位置")
        panel.message = text(
            "CSV samples and Markdown summaries will be saved in this folder.",
            "CSV 采样和 Markdown 汇总将保存在此文件夹中。"
        )
        panel.prompt = text("Choose Folder", "选择文件夹")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputFolderURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return storeOutputFolder(url)
    }

    func revealOutputFolder() {
        guard let outputFolderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputFolderURL])
    }

    func toggleInterface(_ name: String, enabled: Bool) {
        if enabled {
            selectedInterfaceNames.insert(name)
        } else {
            selectedInterfaceNames.remove(name)
        }
    }

    func applyDefaultsToCurrentSession() {
        durationHours = defaultDurationHours
        sampleIntervalSeconds = defaultSampleIntervalSeconds
        speedUnit = defaultSpeedUnit
    }

    func normalizeCurrentSessionValues() {
        durationHours = min(max(durationHours, 0), 168)
        sampleIntervalSeconds = min(max(sampleIntervalSeconds, 1), 3_600)
    }

    func normalizeDefaultValues() {
        defaultDurationHours = min(max(defaultDurationHours, 0), 168)
        defaultSampleIntervalSeconds = min(max(defaultSampleIntervalSeconds, 1), 3_600)
    }

    private func restoreOutputFolder() {
        guard let data = defaults.data(forKey: Key.outputFolderBookmark) else { return }
        var isStale = false

        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard FileManager.default.fileExists(atPath: url.path) else {
                defaults.removeObject(forKey: Key.outputFolderBookmark)
                return
            }

            outputFolderURL = url
            isAccessingOutputFolder = url.startAccessingSecurityScopedResource()
            if isStale {
                _ = storeOutputFolder(url)
            }
        } catch {
            defaults.removeObject(forKey: Key.outputFolderBookmark)
        }
    }

    private func storeOutputFolder(_ url: URL) -> Bool {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            if isAccessingOutputFolder {
                outputFolderURL?.stopAccessingSecurityScopedResource()
            }
            outputFolderURL = url
            isAccessingOutputFolder = url.startAccessingSecurityScopedResource()
            defaults.set(bookmark, forKey: Key.outputFolderBookmark)
            return true
        } catch {
            return false
        }
    }
}
