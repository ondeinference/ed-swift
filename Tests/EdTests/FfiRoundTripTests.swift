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
