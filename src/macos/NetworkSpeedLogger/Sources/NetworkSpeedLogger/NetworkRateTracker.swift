import Foundation

struct NetworkRate: Equatable {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double

    static let zero = NetworkRate(
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0
    )
}

struct NetworkRateTracker {
    private var previousCounters: [String: InterfaceCounter] = [:]
    private var previousDate: Date?

    mutating func reset(
        counters: [String: InterfaceCounter],
        selectedNames: [String],
        at date: Date
    ) {
        previousCounters = selectedCounters(
            from: counters,
            selectedNames: selectedNames
        )
        previousDate = date
    }

    mutating func sample(
        counters: [String: InterfaceCounter],
        selectedNames: [String],
        at date: Date,
        maximumInterval: TimeInterval
    ) -> NetworkRate {
        let currentCounters = selectedCounters(
            from: counters,
            selectedNames: selectedNames
        )
        defer {
            previousCounters = currentCounters
            previousDate = date
        }

        guard let previousDate else { return .zero }
        let interval = date.timeIntervalSince(previousDate)
        guard interval > 0, interval <= maximumInterval else { return .zero }

        var receivedDelta: UInt64 = 0
        var sentDelta: UInt64 = 0

        for (name, current) in currentCounters {
            guard let previous = previousCounters[name] else { continue }
            if current.receivedBytes >= previous.receivedBytes {
                receivedDelta = receivedDelta.addingWithoutOverflow(
                    current.receivedBytes - previous.receivedBytes
                )
            }
            if current.sentBytes >= previous.sentBytes {
                sentDelta = sentDelta.addingWithoutOverflow(
                    current.sentBytes - previous.sentBytes
                )
            }
        }

        return NetworkRate(
            downloadBytesPerSecond: Double(receivedDelta) / interval,
            uploadBytesPerSecond: Double(sentDelta) / interval
        )
    }

    private func selectedCounters(
        from counters: [String: InterfaceCounter],
        selectedNames: [String]
    ) -> [String: InterfaceCounter] {
        Dictionary(uniqueKeysWithValues: selectedNames.compactMap { name in
            counters[name].map { (name, $0) }
        })
    }
}
