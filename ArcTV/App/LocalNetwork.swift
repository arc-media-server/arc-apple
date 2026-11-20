import ArcKit
import Darwin

/// This Apple TV's own address on the home network, for finding Arc (Discovery).
enum LocalNetwork {
    /// The IPv4 address and network size of a private network the Apple TV is on, Ethernet or
    /// Wi-Fi ("en…") first; nil off a home network.
    static func ipv4() -> (address: [UInt8], prefix: Int)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var fallback: (address: [UInt8], prefix: Int)?
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = entry.pointee
            guard let addr = i.ifa_addr, let mask = i.ifa_netmask, addr.pointee.sa_family == UInt8(AF_INET),
                  i.ifa_flags & UInt32(IFF_UP) != 0, i.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let bits = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            // In network order in memory, so its bytes read as the address does.
            let bytes = withUnsafeBytes(of: ip) { Array($0) }
            guard Discovery.isPrivate(bytes) else { continue }
            let found = (address: bytes, prefix: bits.nonzeroBitCount)
            if String(cString: i.ifa_name).hasPrefix("en") { return found }
            if fallback == nil { fallback = found }
        }
        return fallback
    }
}
