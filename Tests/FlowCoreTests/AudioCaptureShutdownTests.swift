import Dispatch
import Foundation
import Testing
@testable import FlowCore

private final class TailSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var accepting = true
    private var frames: [Data] = []
    func append(_ frame: Data) {
        lock.lock(); defer { lock.unlock() }
        if accepting { frames.append(frame) }
    }
    func freeze() { lock.lock(); accepting = false; lock.unlock() }
    func snapshot() -> [Data] { lock.lock(); defer { lock.unlock() }; return frames }
}

@Suite struct AudioCaptureShutdownTests {
    @Test func stopKeepsInFlightAndLastProducerFramesBeforeFreezing() throws {
        let delivery = DispatchQueue(label: "flow.capture.shutdown.test")
        let callbackStarted = DispatchSemaphore(value: 0)
        let finishCallback = DispatchSemaphore(value: 0)
        let sink = TailSamples()
        let opening = Data([1, 2]), inFlightTail = Data([3, 4]), finalTail = Data([5, 6])
        sink.append(opening)
        delivery.async {
            callbackStarted.signal()
            finishCallback.wait()
            sink.append(inFlightTail)
        }
        guard callbackStarted.wait(timeout: .now() + 2) == .success else {
            finishCallback.signal()
            Issue.record("Fixture callback did not start")
            return
        }
        AudioCaptureShutdown.stopAndDrain(stopCapture: {
            finishCallback.signal()
            // The capture API delivers its final frame before stop returns.
            delivery.async { sink.append(finalTail) }
        }, deliveryQueue: delivery, freezeSamples: { sink.freeze() })
        #expect(sink.snapshot() == [opening, inFlightTail, finalTail])
        delivery.sync { sink.append(Data([99])) }
        #expect(sink.snapshot() == [opening, inFlightTail, finalTail])
    }
}
