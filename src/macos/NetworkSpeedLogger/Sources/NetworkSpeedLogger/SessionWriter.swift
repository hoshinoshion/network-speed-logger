import Foundation

enum SessionWriterError: LocalizedError {
    case cannotCreateFile(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateFile(let path):
            return "Unable to create the output file at \(path)."
        }
    }
}

final class SessionWriter {
    let csvURL: URL
    let summaryURL: URL

    private let startDate: Date
    private let usesChinese: Bool
    private let handle: FileHandle
    private var observedInterfaces = Set<String>()
    private var isClosed = false

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private static let displayTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(outputFolder: URL, startDate: Date, usesChinese: Bool) throws {
        self.startDate = startDate
        self.usesChinese = usesChinese

        let timestamp = Self.fileTimestampFormatter.string(from: startDate)
        var suffix = 0
        var csvCandidate: URL
        var summaryCandidate: URL

        repeat {
            let nameSuffix = suffix == 0 ? "" : "_\(suffix)"
            csvCandidate = outputFolder.appendingPathComponent("NetworkSpeed_\(timestamp)\(nameSuffix).csv")
            summaryCandidate = outputFolder.appendingPathComponent("NetworkSpeed_\(timestamp)\(nameSuffix)_summary.md")
            suffix += 1
        } while FileManager.default.fileExists(atPath: csvCandidate.path)
            || FileManager.default.fileExists(atPath: summaryCandidate.path)

        csvURL = csvCandidate
        summaryURL = summaryCandidate

        let header = usesChinese
            ? "时间,已运行秒数,下载速度(MB/s),上传速度(MB/s),活动接口\n"
            : "Timestamp,Elapsed seconds,Download (MB/s),Upload (MB/s),Active interfaces\n"

        guard FileManager.default.createFile(atPath: csvURL.path, contents: Data(header.utf8)),
              let fileHandle = try? FileHandle(forWritingTo: csvURL) else {
            throw SessionWriterError.cannotCreateFile(csvURL.path)
        }
        handle = fileHandle
        try handle.seekToEnd()
        try handle.synchronize()
    }

    deinit {
        if !isClosed {
            try? handle.close()
        }
    }

    func append(_ sample: SpeedSample) throws {
        observedInterfaces.formUnion(sample.activeInterfaces)
        let interfaceText = csvEscape(sample.activeInterfaces.joined(separator: ", "))
        let line = String(
            format: "%@,%.3f,%.6f,%.6f,%@\n",
            locale: Locale(identifier: "en_US_POSIX"),
            Self.isoFormatter.string(from: sample.timestamp),
            sample.elapsedSeconds,
            sample.downloadBytesPerSecond / 1_000_000,
            sample.uploadBytesPerSecond / 1_000_000,
            interfaceText
        )
        try handle.write(contentsOf: Data(line.utf8))
        try handle.synchronize()
    }

    func finish(
        endDate: Date,
        statistics: SessionStatistics,
        reason: SessionStopReason
    ) throws {
        guard !isClosed else { return }
        try handle.synchronize()
        try handle.close()
        isClosed = true

        let duration = max(0, endDate.timeIntervalSince(startDate))
        let interfaces = observedInterfaces.sorted().joined(separator: ", ")
        let safeInterfaces = interfaces.replacingOccurrences(of: "|", with: "\\|")
        let summary = usesChinese
            ? chineseSummary(endDate: endDate, duration: duration, statistics: statistics, interfaces: safeInterfaces, reason: reason)
            : englishSummary(endDate: endDate, duration: duration, statistics: statistics, interfaces: safeInterfaces, reason: reason)
        try Data(summary.utf8).write(to: summaryURL, options: .atomic)
    }

    private func englishSummary(
        endDate: Date,
        duration: TimeInterval,
        statistics: SessionStatistics,
        interfaces: String,
        reason: SessionStopReason
    ) -> String {
        """
        # Network Speed Logger Summary

        - Started: \(Self.displayTimestampFormatter.string(from: startDate))
        - Ended: \(Self.displayTimestampFormatter.string(from: endDate))
        - Wall-clock duration: \(duration.clockText)
        - Measured duration: \(statistics.measuredSeconds.clockText)
        - Stop reason: \(englishReason(reason))
        - Samples: \(statistics.sampleCount)
        - Monitored interfaces: \(interfaces.isEmpty ? "None" : interfaces)
        - Received: \(formatBytes(statistics.totalReceivedBytes))
        - Sent: \(formatBytes(statistics.totalSentBytes))

        | Direction | Minimum | Maximum | Average |
        | --- | ---: | ---: | ---: |
        | Download | \(formatMBps(statistics.minimumDownloadBytesPerSecond ?? 0)) | \(formatMBps(statistics.maximumDownloadBytesPerSecond)) | \(formatMBps(statistics.averageDownloadBytesPerSecond)) |
        | Upload | \(formatMBps(statistics.minimumUploadBytesPerSecond ?? 0)) | \(formatMBps(statistics.maximumUploadBytesPerSecond)) | \(formatMBps(statistics.averageUploadBytesPerSecond)) |
        """
    }

    private func chineseSummary(
        endDate: Date,
        duration: TimeInterval,
        statistics: SessionStatistics,
        interfaces: String,
        reason: SessionStopReason
    ) -> String {
        """
        # Network Speed Logger 记录汇总

        - 开始时间：\(Self.displayTimestampFormatter.string(from: startDate))
        - 结束时间：\(Self.displayTimestampFormatter.string(from: endDate))
        - 实际经过时间：\(duration.clockText)
        - 有效采样时长：\(statistics.measuredSeconds.clockText)
        - 结束原因：\(chineseReason(reason))
        - 样本数：\(statistics.sampleCount)
        - 监控过的接口：\(interfaces.isEmpty ? "无" : interfaces)
        - 接收流量：\(formatBytes(statistics.totalReceivedBytes))
        - 发送流量：\(formatBytes(statistics.totalSentBytes))

        | 方向 | 最小速度 | 最大速度 | 平均速度 |
        | --- | ---: | ---: | ---: |
        | 下载 | \(formatMBps(statistics.minimumDownloadBytesPerSecond ?? 0)) | \(formatMBps(statistics.maximumDownloadBytesPerSecond)) | \(formatMBps(statistics.averageDownloadBytesPerSecond)) |
        | 上传 | \(formatMBps(statistics.minimumUploadBytesPerSecond ?? 0)) | \(formatMBps(statistics.maximumUploadBytesPerSecond)) | \(formatMBps(statistics.averageUploadBytesPerSecond)) |
        """
    }

    private func englishReason(_ reason: SessionStopReason) -> String {
        switch reason {
        case .user: return "Stopped by user"
        case .durationCompleted: return "Configured duration completed"
        case .applicationQuit: return "Application quit"
        case .error(let message): return "Error: \(message)"
        }
    }

    private func chineseReason(_ reason: SessionStopReason) -> String {
        switch reason {
        case .user: return "用户手动结束"
        case .durationCompleted: return "已达到设定时长"
        case .applicationQuit: return "应用退出"
        case .error(let message): return "发生错误：\(message)"
        }
    }

    private func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func formatMBps(_ bytesPerSecond: Double) -> String {
        String(format: "%.3f MB/s", locale: Locale(identifier: "en_US_POSIX"), bytesPerSecond / 1_000_000)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1_000, index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        return String(format: "%.2f %@", locale: Locale(identifier: "en_US_POSIX"), value, units[index])
    }
}
