import Foundation
import Testing
@testable import FlowCore

struct BrowserConnectionRecoveryTests {
    @Test func retriesTransportErrorsWithBoundedBackoff() {
        var policy = BrowserConnectionRecovery()
        let initial = policy.request(now: 0, active: false, needsLogin: false, hasDraft: false)
        #expect(initial)
        let tooSoon = policy.request(now: 1, active: false, needsLogin: false, hasDraft: false)
        #expect(!tooSoon)
        let retry = policy.request(now: 2, active: false, needsLogin: false, hasDraft: false)
        #expect(retry)
        #expect(policy.retryAfter == 6)
        for _ in 0..<20 { let allowed = policy.request(now: policy.retryAfter, active: false, needsLogin: false, hasDraft: false); #expect(allowed) }
        #expect(policy.retryAfter > 0)
        let last = policy.retryAfter
        let capped = policy.request(now: last, active: false, needsLogin: false, hasDraft: false)
        #expect(capped)
        #expect(policy.retryAfter - last == 30)
        policy.ready(); #expect(policy.attempts == 0 && policy.retryAfter == 0)
    }
    @Test func protectsActiveCaptureLoginAndDrafts() {
        var policy = BrowserConnectionRecovery()
        let active = policy.request(now: 100, active: true, needsLogin: false, hasDraft: false)
        let login = policy.request(now: 100, active: false, needsLogin: true, hasDraft: false)
        let draft = policy.request(now: 100, active: false, needsLogin: false, hasDraft: true)
        #expect(!active && !login && !draft)
        #expect(policy.attempts == 0)
    }
    @Test func expectedNavigationCancellationIsNotAConnectionFailure() {
        #expect(BrowserConnectionRecovery.cancelledNavigation(URLError(.cancelled)))
        #expect(!BrowserConnectionRecovery.cancelledNavigation(URLError(.notConnectedToInternet)))
        #expect(!BrowserConnectionRecovery.cancelledNavigation(NSError(domain: "other", code: NSURLErrorCancelled)))
    }
}
