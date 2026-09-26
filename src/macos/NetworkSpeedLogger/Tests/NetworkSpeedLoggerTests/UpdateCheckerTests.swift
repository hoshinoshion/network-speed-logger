import Foundation
import XCTest
@testable import NetworkSpeedLogger

private final class ReleaseResponseProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var statuses: [Int] = []
    private static var requestCount = 0
    private static var body = Data()

    static func configure(statuses: [Int], body: Data) {
        lock.lock()
        defer { lock.unlock() }
        self.statuses = statuses
        self.body = body
        requestCount = 0
    }

    static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let index = Self.requestCount
        Self.requestCount += 1
        let status = Self.statuses[min(index, Self.statuses.count - 1)]
        let body = Self.body
        Self.lock.unlock()

        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
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
}
