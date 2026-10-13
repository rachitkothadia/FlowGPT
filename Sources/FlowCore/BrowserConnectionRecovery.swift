import Foundation

/// Retries transport/renderer failures, never login expiration or user drafts.
public struct BrowserConnectionRecovery {
    public private(set) var attempts = 0
    public private(set) var retryAfter: TimeInterval = 0
    public init() {}
    public mutating func request(now: TimeInterval, active: Bool, needsLogin: Bool, hasDraft: Bool) -> Bool {
        guard !active, !needsLogin, !hasDraft, now >= retryAfter else { return false }
        attempts += 1
        retryAfter = now + min(30, pow(2, Double(min(attempts, 5))))
        return true
    }
    public mutating func ready() { attempts = 0; retryAfter = 0 }
    public static func cancelledNavigation(_ error: any Error) -> Bool {
        let value = error as NSError
        return value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled
    }
}
