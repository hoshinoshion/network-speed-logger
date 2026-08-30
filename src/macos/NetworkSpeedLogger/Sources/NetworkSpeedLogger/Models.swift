import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case automatic
    case english
    case simplifiedChinese

    var id: String { rawValue }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }
}

enum SpeedUnit: String, CaseIterable, Identifiable {
    case megabytesPerSecond
    case megabitsPerSecond

    var id: String { rawValue }

    var suffix: String {
        switch self {
        case .megabytesPerSecond: return "MB/s"
        case .megabitsPerSecond: return "Mbps"
        }
    }

    func value(fromBytesPerSecond bytesPerSecond: Double) -> Double {
        switch self {
        case .megabytesPerSecond:
            return bytesPerSecond / 1_000_000
        case .megabitsPerSecond:
            return bytesPerSecond * 8 / 1_000_000
        }
    }
}

enum InterfaceSelectionMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: String { rawValue }
}

struct NetworkInterfaceInfo: Identifiable, Hashable {
    let name: String
    let displayName: String
    let isActive: Bool
    let isPhysical: Bool
    let isVirtual: Bool

    var id: String { name }
}

struct InterfaceCounter {
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

struct InterfaceCapture {
    let interfaces: [NetworkInterfaceInfo]
    let counters: [String: InterfaceCounter]
}

struct SpeedSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let elapsedSeconds: TimeInterval
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let activeInterfaces: [String]
}

struct SessionStatistics {
    private(set) var totalReceivedBytes: UInt64 = 0
    private(set) var totalSentBytes: UInt64 = 0
    private(set) var measuredSeconds: TimeInterval = 0
    private(set) var minimumDownloadBytesPerSecond: Double?
    private(set) var maximumDownloadBytesPerSecond: Double = 0
    private(set) var minimumUploadBytesPerSecond: Double?
    private(set) var maximumUploadBytesPerSecond: Double = 0
    private(set) var sampleCount = 0

    var averageDownloadBytesPerSecond: Double {
        measuredSeconds > 0 ? Double(totalReceivedBytes) / measuredSeconds : 0
    }

    var averageUploadBytesPerSecond: Double {
        measuredSeconds > 0 ? Double(totalSentBytes) / measuredSeconds : 0
    }

    mutating func record(
        receivedBytes: UInt64,
        sentBytes: UInt64,
        interval: TimeInterval,
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double
    ) {
        totalReceivedBytes = totalReceivedBytes.addingWithoutOverflow(receivedBytes)
        totalSentBytes = totalSentBytes.addingWithoutOverflow(sentBytes)
        measuredSeconds += interval
        sampleCount += 1

        minimumDownloadBytesPerSecond = min(
            minimumDownloadBytesPerSecond ?? downloadBytesPerSecond,
            downloadBytesPerSecond
        )
        maximumDownloadBytesPerSecond = max(maximumDownloadBytesPerSecond, downloadBytesPerSecond)
        minimumUploadBytesPerSecond = min(
            minimumUploadBytesPerSecond ?? uploadBytesPerSecond,
            uploadBytesPerSecond
        )
        maximumUploadBytesPerSecond = max(maximumUploadBytesPerSecond, uploadBytesPerSecond)
    }
}

enum MonitorState: Equatable {
    case idle
    case running
    case finished
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

enum SessionStopReason {
    case user
    case durationCompleted
    case applicationQuit
    case error(String)
}

extension UInt64 {
    func addingWithoutOverflow(_ value: UInt64) -> UInt64 {
        let (result, overflow) = addingReportingOverflow(value)
        return overflow ? UInt64.max : result
    }
}

extension TimeInterval {
    var clockText: String {
        let total = max(0, Int(self.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
