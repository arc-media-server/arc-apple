import Foundation
#if canImport(os)
import os
#endif

/// The app's log, under the subsystem org.arcmediaserver.apple and category "Arc" (Console.app,
/// or `log stream` on a Mac). Outcomes and failures at info and above, detail at debug; never
/// tokens, passwords or full URLs.
public struct ArcLog: Sendable {
    public static let shared = ArcLog()

    #if canImport(os)
    private let logger = Logger(subsystem: "org.arcmediaserver.apple", category: "Arc")
    #endif

    public init() {}

    public func debug(_ message: String) {
        #if canImport(os)
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    public func info(_ message: String) {
        #if canImport(os)
        logger.info("\(message, privacy: .public)")
        #endif
    }

    public func warn(_ message: String) {
        #if canImport(os)
        logger.warning("\(message, privacy: .public)")
        #else
        print("warning: \(message)")
        #endif
    }
}
