import XCTest
@testable import NetworkSpeedLogger

final class MenuBarSpeedPresentationTests: XCTestCase {
    func testFormatterKeepsThreeNumericDigits() async {
        await MainActor.run {
            XCTAssertEqual(StatusBarController.formatSpeed(0, unit: .byte), "0.00 B/s")
            XCTAssertEqual(StatusBarController.formatSpeed(9, unit: .byte), "9.00 B/s")
            XCTAssertEqual(StatusBarController.formatSpeed(12, unit: .byte), "12.0 B/s")
            XCTAssertEqual(StatusBarController.formatSpeed(123, unit: .byte), "123 B/s")
            XCTAssertEqual(StatusBarController.formatSpeed(99.96, unit: .byte), "100 B/s")
            XCTAssertEqual(StatusBarController.formatSpeed(999.6, unit: .byte), "1.00 KB/s")
            XCTAssertEqual(StatusBarController.formatSpeed(1_000, unit: .byte), "1.00 KB/s")
            XCTAssertEqual(StatusBarController.formatSpeed(12_000, unit: .byte), "12.0 KB/s")
            XCTAssertEqual(StatusBarController.formatSpeed(123_000, unit: .byte), "123 KB/s")
            XCTAssertEqual(StatusBarController.formatSpeed(125, unit: .bit), "1.00 Kb/s")
        }
    }

    func testArrowPairKeepsItsCenterWhileIncreasingVerticalSeparation() async {
        await MainActor.run {
            XCTAssertEqual(StatusBarController.upperArrowCenterY, 12)
            XCTAssertEqual(StatusBarController.lowerArrowCenterY, 6)
            XCTAssertEqual(StatusBarController.upperArrowCenterY - StatusBarController.lowerArrowCenterY, 6)
            XCTAssertEqual((StatusBarController.upperArrowCenterY + StatusBarController.lowerArrowCenterY) / 2, 9)
        }
    }

    func testStatusItemImageWidthDoesNotChangeWithSpeedOrUnit() async {
        await MainActor.run {
            let byteSpeeds: [Double] = [0, 9, 12, 123, 1_000, 12_000, 123_000, 1_000_000]
            let bitSpeeds: [Double] = [0, 1, 125, 1_250, 12_500, 125_000]
            let images = byteSpeeds.map {
                StatusBarController.makeSpeedStatusBarImage(
                    uploadBytesPerSecond: $0,
                    downloadBytesPerSecond: $0 * 2,
                    unit: .byte,
                    activityThresholdBytesPerSecond: 50_000
                )
            } + bitSpeeds.map {
                StatusBarController.makeSpeedStatusBarImage(
                    uploadBytesPerSecond: $0,
                    downloadBytesPerSecond: $0 * 2,
                    unit: .bit,
                    activityThresholdBytesPerSecond: 50_000
                )
            }

            let widths = Set(images.map(\.size.width))
            XCTAssertEqual(widths.count, 1)
        }
    }
}
