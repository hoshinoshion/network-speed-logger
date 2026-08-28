import AppKit
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let language = "language"
        static let speedUnit = "speedUnit"
        static let interfaceMode = "interfaceMode"
        static let selectedInterfaces = "selectedInterfaces"
        static let durationHours = "durationHours"
        static let sampleInterval = "sampleInterval"
        static let outputFolderBookmark = "outputFolderBookmark"
    }

    private let defaults: UserDefaults
    private var isAccessingOutputFolder = false

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    @Published var speedUnit: SpeedUnit {
        didSet { defaults.set(speedUnit.rawValue, forKey: Key.speedUnit) }
    }

    @Published var interfaceMode: InterfaceSelectionMode {
        didSet { defaults.set(interfaceMode.rawValue, forKey: Key.interfaceMode) }
    }

    @Published var selectedInterfaceNames: Set<String> {
        didSet { defaults.set(Array(selectedInterfaceNames).sorted(), forKey: Key.selectedInterfaces) }
    }

    @Published var durationHours: Double {
        didSet { defaults.set(durationHours, forKey: Key.durationHours) }
    }

    @Published var sampleIntervalSeconds: Int {
        didSet { defaults.set(sampleIntervalSeconds, forKey: Key.sampleInterval) }
    }

    @Published private(set) var outputFolderURL: URL?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .automatic
        speedUnit = SpeedUnit(rawValue: defaults.string(forKey: Key.speedUnit) ?? "") ?? .megabytesPerSecond
        interfaceMode = InterfaceSelectionMode(rawValue: defaults.string(forKey: Key.interfaceMode) ?? "") ?? .automatic
        selectedInterfaceNames = Set(defaults.stringArray(forKey: Key.selectedInterfaces) ?? [])

        let storedDuration = defaults.object(forKey: Key.durationHours) as? Double
        durationHours = storedDuration.map { min(max($0, 0), 168) } ?? 24

        let storedInterval = defaults.object(forKey: Key.sampleInterval) as? Int
        sampleIntervalSeconds = storedInterval.map { min(max($0, 1), 3_600) } ?? 15

        restoreOutputFolder()
    }

    deinit {
        if isAccessingOutputFolder {
            outputFolderURL?.stopAccessingSecurityScopedResource()
        }
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
