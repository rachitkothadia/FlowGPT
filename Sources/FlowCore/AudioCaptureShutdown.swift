import Dispatch

/// Stop the producer before draining its serial delivery queue. Call from the
/// capture owner, never from deliveryQueue, whose callbacks must not await it.
public enum AudioCaptureShutdown {
    public static func stopAndDrain(stopCapture: () -> Void, deliveryQueue: DispatchQueue,
        freezeSamples: () -> Void) {
        stopCapture()
        deliveryQueue.sync {}
        freezeSamples()
    }
}
