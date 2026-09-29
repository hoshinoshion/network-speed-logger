import Foundation
import XCTest
@testable import NetworkSpeedLogger

private final class ReleaseResponseProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var statuses: [Int] = []
    private static var requestCount = 0
    private static var body = Data()
    private static var finalPageURL: URL?
    private static var requestedURLs: [URL] = []

    static func configure(statuses: [Int], body: Data, finalPageURL: URL? = nil) {
        lock.lock()
        defer { lock.unlock() }
        self.statuses = statuses
        self.body = body
        self.finalPageURL = finalPageURL
        requestCount = 0
        requestedURLs = []
    }

    static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    static var URLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requestedURLs
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let index = Self.requestCount
        Self.requestCount += 1
        let status = Self.statuses[min(index, Self.statuses.count - 1)]
        let body = Self.body
        let pageURL = Self.finalPageURL
        Self.requestedURLs.append(request.url!)
        Self.lock.unlock()

        let responseURL = request.url!.host == "github.com" ? (pageURL ?? request.url!) : request.url!
        let response = HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class UpdateCheckerTests: XCTestCase {
    private func makeChecker() async -> (UpdateChecker, UserDefaults, URLSession) {
        let defaults = UserDefaults(suiteName: "UpdateCheckerTests.\(UUID().uuidString)")!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseResponseProtocol.self]
        let session = URLSession(configuration: config)
        let checker = await MainActor.run {
            UpdateChecker(defaults: defaults, session: session, installedVersion: "1.0.0")
        }
        return (checker, defaults, session)
    }

    private var validRelease: Data {
        Data(#"{"tag_name":"v1.0.1","html_url":"https://github.com/hoshinoshion/network-speed-logger/releases/tag/v1.0.1","published_at":"2026-09-26T00:00:00Z","assets":[{"name":"NetworkSpeedLogger.dmg"}]}"#.utf8)
    }

    func testAutomaticCheckRunsWithoutAnyWindow() async throws {
        ReleaseResponseProtocol.configure(statuses: [200], body: validRelease)
        let (checker, _, session) = await makeChecker()
        defer { session.invalidateAndCancel() }

        await MainActor.run {
            checker.startAutomaticChecks(isEnabled: { true }, initialDelay: 1_000_000)
        }

        for _ in 0..<40 {
            if await MainActor.run(body: { checker.status == .updateAvailable }) { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let release = await MainActor.run { checker.presentedRelease }
        XCTAssertEqual(release?.version, "1.0.1")
        XCTAssertEqual(ReleaseResponseProtocol.count, 1)
        await MainActor.run { checker.stopAutomaticChecks() }
    }

    func testManualCheckRetriesTemporaryServerFailure() async {
        ReleaseResponseProtocol.configure(statuses: [503, 200], body: validRelease)
        let (checker, _, session) = await makeChecker()
        defer { session.invalidateAndCancel() }

        await checker.checkForUpdates(manual: true, presentWhenAvailable: false)
        let status = await MainActor.run { checker.status }
        XCTAssertEqual(status, .updateAvailable)
        XCTAssertEqual(ReleaseResponseProtocol.count, 2)
    }

    func testInvalidReleaseDoesNotSuppressFutureAutomaticChecks() async {
        ReleaseResponseProtocol.configure(statuses: [200], body: Data("{}".utf8))
        let (checker, defaults, session) = await makeChecker()
        defer { session.invalidateAndCancel() }

        await checker.checkForUpdates(manual: false)
        let status = await MainActor.run { checker.status }
        XCTAssertEqual(status, .failed)
        XCTAssertNil(defaults.object(forKey: "updates.lastSuccessfulCheck"))
    }

    func testRateLimitedAPIUsesLatestStableReleasePage() async {
        let pageURL = URL(string: "https://github.com/hoshinoshion/network-speed-logger/releases/tag/v1.0.4")!
        ReleaseResponseProtocol.configure(statuses: [403, 200], body: validRelease, finalPageURL: pageURL)
        let (checker, _, session) = await makeChecker()
        defer { session.invalidateAndCancel() }

        await checker.checkForUpdates(manual: true, presentWhenAvailable: false)
        let result = await MainActor.run { (checker.status, checker.availableRelease) }
        XCTAssertEqual(result.0, .updateAvailable)
        XCTAssertEqual(result.1?.version, "1.0.4")
        XCTAssertEqual(result.1?.pageURL, pageURL)
        XCTAssertEqual(ReleaseResponseProtocol.URLs.map(\.host), ["api.github.com", "github.com"])
    }

    func testFallbackRejectsAnUnresolvedOrUnexpectedPage() async {
        ReleaseResponseProtocol.configure(statuses: [429, 200], body: validRelease)
        let (checker, _, session) = await makeChecker()
        defer { session.invalidateAndCancel() }

        await checker.checkForUpdates(manual: true)
        let status = await MainActor.run { checker.status }
        XCTAssertEqual(status, .failed)
        XCTAssertEqual(ReleaseResponseProtocol.count, 2)
    }

    func testAutomaticCheckRetriesAfterPreviousFailureWithoutRestart() async {
        ReleaseResponseProtocol.configure(statuses: [200], body: validRelease)
        let (checker, defaults, session) = await makeChecker()
        defer { session.invalidateAndCancel() }
        defaults.set(Date().addingTimeInterval(-6 * 60), forKey: "updates.lastAttempt")

        await checker.checkAutomaticallyIfNeeded()
        let status = await MainActor.run { checker.status }
        XCTAssertEqual(status, .updateAvailable)
        XCTAssertEqual(ReleaseResponseProtocol.count, 1)
    }

    func testRunningAutomaticTimerRecoversAfterTemporaryFailure() async throws {
        ReleaseResponseProtocol.configure(statuses: [403, 503, 200], body: validRelease)
        let (checker, defaults, session) = await makeChecker()
        defer { session.invalidateAndCancel() }
        await MainActor.run {
            checker.startAutomaticChecks(
                isEnabled: { true },
                initialDelay: 1_000_000,
                repeatInterval: 25_000_000
            )
        }
        defer { Task { @MainActor in checker.stopAutomaticChecks() } }

        for _ in 0..<40 {
            if await MainActor.run(body: { checker.status == .failed }) { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let failedStatus = await MainActor.run { checker.status }
        XCTAssertEqual(failedStatus, .failed)
        defaults.set(Date().addingTimeInterval(-6 * 60), forKey: "updates.lastAttempt")

        for _ in 0..<40 {
            if await MainActor.run(body: { checker.status == .updateAvailable }) { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        let recoveredStatus = await MainActor.run { checker.status }
        XCTAssertEqual(recoveredStatus, .updateAvailable)
        XCTAssertEqual(ReleaseResponseProtocol.count, 3)
        await MainActor.run { checker.stopAutomaticChecks() }
    }
}
