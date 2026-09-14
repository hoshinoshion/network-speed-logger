import Darwin
import XCTest
@testable import NetworkSpeedLogger

final class NetworkRateTrackerTests: XCTestCase {
    func testCalculatesCombinedRateAcrossSelectedInterfaces() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var tracker = NetworkRateTracker()
        tracker.reset(
            counters: [
                "en0": InterfaceCounter(receivedBytes: 1_000, sentBytes: 2_000),
                "en5": InterfaceCounter(receivedBytes: 3_000, sentBytes: 4_000)
            ],
            selectedNames: ["en0", "en5"],
            at: start
        )

        let rate = tracker.sample(
            counters: [
                "en0": InterfaceCounter(receivedBytes: 2_000, sentBytes: 2_500),
                "en5": InterfaceCounter(receivedBytes: 4_500, sentBytes: 5_500)
            ],
            selectedNames: ["en0", "en5"],
            at: start.addingTimeInterval(2),
            maximumInterval: 12
        )

        XCTAssertEqual(rate.downloadBytesPerSecond, 1_250)
        XCTAssertEqual(rate.uploadBytesPerSecond, 1_000)
    }

    func testNewInterfaceIsBaselinedBeforeItsTrafficIsCounted() {
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        var tracker = NetworkRateTracker()
        tracker.reset(
            counters: ["en0": InterfaceCounter(receivedBytes: 1_000, sentBytes: 1_000)],
            selectedNames: ["en0"],
            at: start
        )

        let first = tracker.sample(
            counters: [
                "en0": InterfaceCounter(receivedBytes: 2_000, sentBytes: 2_000),
                "en5": InterfaceCounter(receivedBytes: 50_000, sentBytes: 50_000)
            ],
            selectedNames: ["en0", "en5"],
            at: start.addingTimeInterval(1),
            maximumInterval: 11
        )
        XCTAssertEqual(first.downloadBytesPerSecond, 1_000)
        XCTAssertEqual(first.uploadBytesPerSecond, 1_000)

        let second = tracker.sample(
            counters: [
                "en0": InterfaceCounter(receivedBytes: 3_000, sentBytes: 3_000),
                "en5": InterfaceCounter(receivedBytes: 52_000, sentBytes: 53_000)
            ],
            selectedNames: ["en0", "en5"],
            at: start.addingTimeInterval(2),
            maximumInterval: 11
        )
        XCTAssertEqual(second.downloadBytesPerSecond, 3_000)
        XCTAssertEqual(second.uploadBytesPerSecond, 4_000)
    }

    func testDiscontinuityAndCounterResetDoNotCreateFalseSpikes() {
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        var tracker = NetworkRateTracker()
        tracker.reset(
            counters: ["en0": InterfaceCounter(receivedBytes: 10_000, sentBytes: 10_000)],
            selectedNames: ["en0"],
            at: start
        )

        let afterSleep = tracker.sample(
            counters: ["en0": InterfaceCounter(receivedBytes: 50_000, sentBytes: 50_000)],
            selectedNames: ["en0"],
            at: start.addingTimeInterval(60),
            maximumInterval: 11
        )
        XCTAssertEqual(afterSleep, .zero)

        let afterReset = tracker.sample(
            counters: ["en0": InterfaceCounter(receivedBytes: 100, sentBytes: 200)],
            selectedNames: ["en0"],
            at: start.addingTimeInterval(61),
            maximumInterval: 11
        )
        XCTAssertEqual(afterReset, .zero)
    }

    func testAutomaticProviderCountersIncreaseWithOutgoingTraffic() throws {
        let provider = InterfaceProvider()
        let initialCapture = provider.capture()
        let selectedNames = provider.selectedNames(
            from: initialCapture,
            mode: .automatic,
            manuallySelected: []
        )
        XCTAssertFalse(selectedNames.isEmpty, "No automatic physical interface was selected")

        let start = Date()
        var tracker = NetworkRateTracker()
        tracker.reset(
            counters: initialCapture.counters,
            selectedNames: selectedNames,
            at: start
        )

        try sendTestDatagrams()
        usleep(250_000)

        let finalCapture = provider.capture()
        let finalSelectedNames = provider.selectedNames(
            from: finalCapture,
            mode: .automatic,
            manuallySelected: []
        )
        let rate = tracker.sample(
            counters: finalCapture.counters,
            selectedNames: finalSelectedNames,
            at: start.addingTimeInterval(1),
            maximumInterval: 11
        )
        XCTAssertGreaterThan(
            rate.uploadBytesPerSecond,
            0,
            "Outgoing traffic did not change counters for the automatically selected interface"
        )
    }

    private func sendTestDatagrams() throws {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(9).bigEndian
        XCTAssertEqual(inet_pton(AF_INET, "192.0.2.1", &destination.sin_addr), 1)

        let payload = [UInt8](repeating: 0x4e, count: 1_024)
        var successfulSends = 0
        withUnsafePointer(to: &destination) { destinationPointer in
            destinationPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addressPointer in
                for _ in 0..<128 {
                    let sent = payload.withUnsafeBytes { bytes in
                        sendto(
                            descriptor,
                            bytes.baseAddress,
                            bytes.count,
                            0,
                            addressPointer,
                            socklen_t(MemoryLayout<sockaddr_in>.size)
                        )
                    }
                    if sent > 0 { successfulSends += 1 }
                }
            }
        }
        XCTAssertGreaterThan(successfulSends, 0)
    }
}
