import Testing
@testable import Ed

// The other tests only touch Swift types. This one crosses into Rust, so a
// framework built from different bindings fails here with UniFFI's checksum
// check instead of at the first call in an app.
@Test func newAgentReachesTheRustCore() async {
    let agent = EdAgent()
    #expect(await agent.isLoaded() == false)

    let info = await agent.info()
    #expect(info.modelName == nil)
    #expect(info.historyLength == 0)
}

@Test func agentAcceptsAnAppIDAndStartsEmpty() async {
    let agent = EdAgent(appID: "test-app")
    #expect(await agent.history().isEmpty)
}

// These need a loaded model to do anything, so without one they must be
// harmless rather than crash across the FFI boundary.
@Test func settersAndRestoreAreNoOpsWithoutAModel() async {
    let agent = EdAgent(appID: nil)
    await agent.setSystemPrompt("You are terse.")
    await agent.clearSystemPrompt()
    await agent.setSampling(EdSamplingConfiguration(temperature: 0.2, maxTokens: 64))
    await agent.restoreHistory([
        EdChatMessage(role: .user, content: "hi"),
        EdChatMessage(role: .assistant, content: "hello"),
    ])
    #expect(await agent.history().isEmpty)
}

@Test func generateAndStreamFailCleanlyWithoutAModel() async {
    let agent = EdAgent()

    await #expect(throws: (any Error).self) {
        _ = try await agent.generate(messages: [EdChatMessage(role: .user, content: "hi")])
    }

    var deltas: [String] = []
    var failure: (any Error)?
    do {
        for try await delta in agent.stream("hi") { deltas.append(delta) }
    } catch {
        failure = error
    }
    #expect(deltas.isEmpty)
    #expect(failure != nil)
}

@Test func eventsStreamReportsStatusChanges() async {
    let agent = EdAgent()
    var events = agent.events().makeAsyncIterator()

    await agent.unload()

    guard case .statusChanged(let status, _, _)? = await events.next() else {
        Issue.record("expected a status change")
        return
    }
    #expect(status == .unloaded)
}
