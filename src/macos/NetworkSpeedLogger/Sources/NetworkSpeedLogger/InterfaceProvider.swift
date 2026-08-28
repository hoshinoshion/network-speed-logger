import Darwin
import Foundation
import SystemConfiguration

struct InterfaceProvider {
    private static let virtualPrefixes = [
        "lo", "gif", "stf", "utun", "ipsec", "ppp", "tun", "tap", "bridge",
        "awdl", "llw", "anpi", "ap", "p2p", "vmnet", "vboxnet", "wg", "fw"
    ]

    func capture() -> InterfaceCapture {
        let hardware = hardwareInterfaceMetadata()
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let firstAddress = addressList else {
            return InterfaceCapture(interfaces: [], counters: [:])
        }
        defer { freeifaddrs(addressList) }

        var counters: [String: InterfaceCounter] = [:]
        var flagsByName: [String: UInt32] = [:]
        var linkStateByName: [String: UInt8] = [:]
        var interfacesWithIPAddress = Set<String>()
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let current = pointer {
            let address = current.pointee
            defer { pointer = address.ifa_next }

            guard let namePointer = address.ifa_name,
                  let socketAddress = address.ifa_addr else {
                continue
            }

            let name = String(cString: namePointer)
            let family = Int32(socketAddress.pointee.sa_family)
            flagsByName[name] = address.ifa_flags

            if family == AF_INET || family == AF_INET6 {
                interfacesWithIPAddress.insert(name)
                continue
            }

            guard family == AF_LINK, let rawData = address.ifa_data else { continue }
            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = InterfaceCounter(
                receivedBytes: UInt64(data.ifi_ibytes),
                sentBytes: UInt64(data.ifi_obytes)
            )
            linkStateByName[name] = data.ifi_link_state
        }

        let interfaces = counters.keys.map { name -> NetworkInterfaceInfo in
            let flags = flagsByName[name] ?? 0
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isRunning = (flags & UInt32(IFF_RUNNING)) != 0
            let hasIPAddress = interfacesWithIPAddress.contains(name)
            let linkState = linkStateByName[name] ?? 0
            let hasUsableLink = linkState == UInt8(LINK_STATE_UP)
            let isVirtual = Self.virtualPrefixes.contains { name.hasPrefix($0) }
            let isPhysical = hardware[name] != nil && !isVirtual
            return NetworkInterfaceInfo(
                name: name,
                displayName: hardware[name] ?? friendlyFallbackName(for: name),
                isActive: isUp && isRunning && hasUsableLink && hasIPAddress,
                isPhysical: isPhysical,
                isVirtual: isVirtual
            )
        }
        .sorted {
            if $0.isPhysical != $1.isPhysical { return $0.isPhysical && !$1.isPhysical }
            if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        return InterfaceCapture(interfaces: interfaces, counters: counters)
    }

    func selectedNames(
        from capture: InterfaceCapture,
        mode: InterfaceSelectionMode,
        manuallySelected: Set<String>
    ) -> [String] {
        switch mode {
        case .automatic:
            return capture.interfaces
                .filter { $0.isPhysical && $0.isActive }
                .map(\.name)
                .sorted()
        case .manual:
            return capture.interfaces
                .filter { manuallySelected.contains($0.name) }
                .map(\.name)
                .sorted()
        }
    }

    private func hardwareInterfaceMetadata() -> [String: String] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var result: [String: String] = [:]

        for interface in interfaces {
            guard let bsdNameReference = SCNetworkInterfaceGetBSDName(interface) else { continue }
            let name = bsdNameReference as String
            let displayName = (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?) ?? name
            result[name] = displayName
        }
        return result
    }

    private func friendlyFallbackName(for name: String) -> String {
        if name.hasPrefix("utun") { return "VPN / Tunnel" }
        if name.hasPrefix("bridge") { return "Network Bridge" }
        if name.hasPrefix("awdl") || name.hasPrefix("llw") { return "Apple Wireless Direct Link" }
        if name.hasPrefix("lo") { return "Loopback" }
        return name
    }
}
