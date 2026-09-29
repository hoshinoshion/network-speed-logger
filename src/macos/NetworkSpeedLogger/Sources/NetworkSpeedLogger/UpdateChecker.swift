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
    private let session: URLSession?
    private let installedVersion: String?
    private var isChecking = false
    private var automaticCheckTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, session: URLSession? = nil, installedVersion: String? = nil) {
        self.defaults = defaults
        self.session = session
        self.installedVersion = installedVersion ?? Self.currentVersion
    }

    // The timer belongs to the application, so checks continue while no window exists.
    func startAutomaticChecks(
        isEnabled: @escaping @MainActor () -> Bool,
        initialDelay: UInt64 = 10_000_000_000,
        repeatInterval: UInt64 = 5 * 60 * 1_000_000_000
    ) {
        automaticCheckTask?.cancel()
        automaticCheckTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: initialDelay)
                while !Task.isCancelled {
                    if isEnabled() { await self?.checkAutomaticallyIfNeeded() }
                    try await Task.sleep(nanoseconds: repeatInterval)
                }
            } catch is CancellationError {
                // Application shutdown or a replacement timer.
            } catch {
                // Task.sleep only throws on cancellation.
            }
        }
    }

    func stopAutomaticChecks() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
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
            guard let currentText = installedVersion,
                  let current = ComparableVersion(currentText),
                  let latest = ComparableVersion(release.version) else {
                status = .failed
                return
            }
            defaults.set(Date(), forKey: Key.lastSuccessfulCheck)

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
        presentedRelease = nil
    }

    private var automaticCheckIsDue: Bool {
        let now = Date()
        if let lastSuccessful = defaults.object(forKey: Key.lastSuccessfulCheck) as? Date,
           now.timeIntervalSince(lastSuccessful) < 24 * 60 * 60 {
            return false
        }
        // A failed check must be retried after connectivity returns, even when
        // the application keeps running in the menu bar for days.
        if let lastAttempt = defaults.object(forKey: Key.lastAttempt) as? Date,
           now.timeIntervalSince(lastAttempt) < 5 * 60 {
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

    private struct ReleaseHTTPError: Error {
        let statusCode: Int
    }

    private func fetchLatestRelease() async throws -> UpdateReleaseInfo {
        // Start each check with a fresh network session. A menu bar application
        // can outlive DNS, VPN and network changes by many hours.
        let activeSession = session ?? Self.makeSession()
        defer {
            if session == nil { activeSession.finishTasksAndInvalidate() }
        }
        let endpoint = URL(string: "https://api.github.com/repos/hoshinoshion/network-speed-logger/releases/latest")!
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NetworkSpeedLogger-macOS", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        for attempt in 0..<3 {
            do {
                let (data, response) = try await activeSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard httpResponse.statusCode == 200 else {
                    throw ReleaseHTTPError(statusCode: httpResponse.statusCode)
                }
                return try parseRelease(data)
            } catch {
                if attempt < 2 && Self.isTransient(error) {
                    try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
                    continue
                }
                // The public API has a separate rate limit from GitHub's
                // release pages. Use GitHub's documented latest-release URL
                // when the API is temporarily unavailable.
                if Self.canUseReleasePageFallback(error) {
                    return try await fetchLatestReleasePage(using: activeSession)
                }
                throw error
            }
        }
        throw URLError(.badServerResponse)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    private static func canUseReleasePageFallback(_ error: Error) -> Bool {
        if let http = error as? ReleaseHTTPError {
            return http.statusCode == 403 || http.statusCode == 429 || (500...599).contains(http.statusCode)
        }
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
            .badServerResponse, .secureConnectionFailed
        ].contains(urlError.code)
    }

    private func fetchLatestReleasePage(using session: URLSession) async throws -> UpdateReleaseInfo {
        let endpoint = URL(string: "https://github.com/hoshinoshion/network-speed-logger/releases/latest")!
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("NetworkSpeedLogger-macOS", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let pageURL = httpResponse.url else {
            throw URLError(.badServerResponse)
        }
        return try Self.releaseFromLatestPageURL(pageURL)
    }

    private static func releaseFromLatestPageURL(_ url: URL) throws -> UpdateReleaseInfo {
        let prefix = "/hoshinoshion/network-speed-logger/releases/tag/"
        guard url.scheme == "https",
              url.host == "github.com",
              url.path.hasPrefix(prefix),
              url.query == nil,
              url.fragment == nil else {
            throw URLError(.cannotParseResponse)
        }
        let tag = String(url.path.dropFirst(prefix.count))
        let version = tag.first == "v" || tag.first == "V"
            ? String(tag.dropFirst())
            : tag
        guard ComparableVersion(version) != nil else {
            throw URLError(.cannotParseResponse)
        }
        return UpdateReleaseInfo(version: version, pageURL: url, publishedAt: nil)
    }

    private static func isTransient(_ error: Error) -> Bool {
        if let http = error as? ReleaseHTTPError {
            return (500...504).contains(http.statusCode)
        }
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet
        ].contains(urlError.code)
    }

    private func parseRelease(_ data: Data) throws -> UpdateReleaseInfo {
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
