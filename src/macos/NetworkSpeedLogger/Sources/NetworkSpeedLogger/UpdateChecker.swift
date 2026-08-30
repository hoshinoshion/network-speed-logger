import AppKit
import Combine
import Foundation

struct UpdateReleaseInfo: Equatable {
    let version: String
    let pageURL: URL
    let publishedAt: Date?
}

enum UpdateCheckStatus: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable
    case failed
}

private struct ComparableVersion: Comparable {
    private let components: [Int]

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }

        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.count <= 4,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        components = parts.compactMap { Int($0) }
        guard components.count == parts.count else { return nil }
    }

    static func < (lhs: ComparableVersion, rhs: ComparableVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    private enum Key {
        static let lastSuccessfulCheck = "updates.lastSuccessfulCheck"
        static let lastAttempt = "updates.lastAttempt"
        static let lastRemindedVersion = "updates.lastRemindedVersion"
        static let lastReminderDate = "updates.lastReminderDate"
        static let skippedVersion = "updates.skippedVersion"
    }

    private struct ReleaseResponse: Decodable {
        struct Asset: Decodable {
            let name: String
        }

        let tagName: String
        let pageURL: URL
        let publishedAt: Date?
        let assets: [Asset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case pageURL = "html_url"
            case publishedAt = "published_at"
            case assets
        }
    }

    static var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static var displayedCurrentVersion: String {
        currentVersion ?? "—"
    }

    @Published private(set) var status: UpdateCheckStatus = .idle
    @Published private(set) var availableRelease: UpdateReleaseInfo?
    @Published var presentedRelease: UpdateReleaseInfo?

    private let defaults: UserDefaults
    private let session: URLSession
    private var isChecking = false

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    func checkAutomaticallyIfNeeded() async {
        guard automaticCheckIsDue else { return }
        await checkForUpdates(manual: false)
    }

    func checkForUpdates(manual: Bool, presentWhenAvailable: Bool = true) async {
        guard !isChecking else { return }
        if !manual && !automaticCheckIsDue { return }

        isChecking = true
        status = .checking
        defaults.set(Date(), forKey: Key.lastAttempt)
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            defaults.set(Date(), forKey: Key.lastSuccessfulCheck)

            guard let currentText = Self.currentVersion,
                  let current = ComparableVersion(currentText),
                  let latest = ComparableVersion(release.version) else {
                status = .failed
                return
            }

            guard latest > current else {
                availableRelease = nil
                status = .upToDate
                return
            }

            availableRelease = release
            status = .updateAvailable
            if presentWhenAvailable && (manual || shouldPresentAutomatically(release)) {
                presentedRelease = release
            }
        } catch is CancellationError {
            status = .idle
        } catch {
            status = .failed
        }
    }

    func openPresentedRelease() {
        guard let release = presentedRelease else { return }
        markReminded(release)
        NSWorkspace.shared.open(release.pageURL)
        presentedRelease = nil
    }

    func deferPresentedRelease() {
        guard let release = presentedRelease else { return }
        markReminded(release)
        presentedRelease = nil
    }

    func skipPresentedRelease() {
        guard let release = presentedRelease else { return }
        defaults.set(release.version, forKey: Key.skippedVersion)
        presentedRelease = nil
    }

    func openAvailableRelease() {
        guard let release = availableRelease else { return }
        markReminded(release)
        NSWorkspace.shared.open(release.pageURL)
    }

    private var automaticCheckIsDue: Bool {
        let now = Date()
        if let lastSuccessful = defaults.object(forKey: Key.lastSuccessfulCheck) as? Date,
           now.timeIntervalSince(lastSuccessful) < 24 * 60 * 60 {
            return false
        }
        if let lastAttempt = defaults.object(forKey: Key.lastAttempt) as? Date,
           now.timeIntervalSince(lastAttempt) < 60 * 60 {
            return false
        }
        return true
    }

    private func shouldPresentAutomatically(_ release: UpdateReleaseInfo) -> Bool {
        if defaults.string(forKey: Key.skippedVersion) == release.version {
            return false
        }
        guard defaults.string(forKey: Key.lastRemindedVersion) == release.version,
              let lastReminder = defaults.object(forKey: Key.lastReminderDate) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastReminder) >= 7 * 24 * 60 * 60
    }

    private func markReminded(_ release: UpdateReleaseInfo) {
        defaults.set(release.version, forKey: Key.lastRemindedVersion)
        defaults.set(Date(), forKey: Key.lastReminderDate)
    }

    private func fetchLatestRelease() async throws -> UpdateReleaseInfo {
        let endpoint = URL(string: "https://api.github.com/repos/hoshinoshion/network-speed-logger/releases/latest")!
        var request = URLRequest(url: endpoint, timeoutInterval: 8)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NetworkSpeedLogger-macOS", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ReleaseResponse.self, from: data)
        guard payload.assets.contains(where: { $0.name == "NetworkSpeedLogger.dmg" }),
              payload.pageURL.scheme == "https",
              payload.pageURL.host == "github.com",
              payload.pageURL.path.hasPrefix("/hoshinoshion/network-speed-logger/releases/") else {
            throw URLError(.cannotParseResponse)
        }

        let version = payload.tagName.first == "v" || payload.tagName.first == "V"
            ? String(payload.tagName.dropFirst())
            : payload.tagName
        return UpdateReleaseInfo(
            version: version,
            pageURL: payload.pageURL,
            publishedAt: payload.publishedAt
        )
    }
}
