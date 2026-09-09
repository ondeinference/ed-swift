import Testing
@testable import Ed

@Test func readOnlyDefinitionKeepsItsSchema() {
    let definition = EdToolDefinition.readOnly(
        name: "current_battery",
        description: "Read the current battery percentage",
        parametersSchema: #"{"type":"object","properties":{}}"#
    )

    #expect(definition.name == "current_battery")
    #expect(definition.parametersSchema.contains("properties"))
}

@Test func configurationHasSafeDefaults() {
    let configuration = EdAgentConfiguration()
    #expect(configuration.maxToolRounds == 8)
    #expect(configuration.maxToolOutputCharacters == 10_000)
}
