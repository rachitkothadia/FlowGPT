import Testing
@testable import FlowCore

@Suite struct PanelPresentationTests {
    @Test func stopKeepsLoaderUntilDeliveryFinishes() {
        let workflow: [SessionState] = [.starting, .recording, .transcribing, .generating, .inserting, .success]
        #expect(workflow.map { PanelPresentation(state: $0) } == [.processing, .recording, .processing, .processing, .processing, .hidden])
    }
    @Test func completedAndCancelledSessionsHideImmediately() {
        for state: SessionState in [.idle, .cancelled, .success, .attempted, .tip] {
            #expect(PanelPresentation(state: state) == .hidden)
        }
    }
    @Test func errorsRemainRecoverable() {
        #expect(PanelPresentation(state: .error) == .error)
    }
}
