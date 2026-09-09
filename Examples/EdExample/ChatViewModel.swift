import Ed
import Foundation
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var input = "What is my battery level?"
    @Published var transcript = ""
    @Published var status = "Not loaded"
    @Published var isLoaded = false
    @Published var isBusy = false
    @Published var showApproval = false
    @Published var approvalSummary = ""

    private let notes = NotesStore()
    private lazy var agent = EdAgent { [weak self] call in
        guard let self else { return .deny }
        return await self.requestApproval(for: call)
    }
    private var approvalContinuation: CheckedContinuation<EdApprovalDecision, Never>?

    func load() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await agent.register(BatteryTool())
            try await agent.register(SaveNoteTool(notes: notes))
            _ = try await agent.loadDefaultAgentModel(
                systemPrompt: "You are a concise assistant inside an iOS app. Use tools when useful."
            )
            isLoaded = true
            status = "Ready"
        } catch {
            status = "Load failed: \(error.localizedDescription)"
        }
    }

    func send() async {
        let message = input
        input = ""
        isBusy = true
        defer { isBusy = false }
        do {
            let reply = try await agent.run(message)
            transcript += "You: \(message)\n\nEd: \(reply.text)\n\n"
            status = "Finished in \(reply.duration) with \(reply.toolRounds) tool round(s)"
        } catch {
            status = "Turn failed: \(error.localizedDescription)"
        }
    }

    func resolveApproval(_ decision: EdApprovalDecision) {
        showApproval = false
        approvalContinuation?.resume(returning: decision)
        approvalContinuation = nil
    }

    private func requestApproval(for call: EdToolCall) async -> EdApprovalDecision {
        approvalSummary = "\(call.name) wants to run with: \(call.arguments)"
        showApproval = true
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }
}

private struct BatteryTool: EdTool {
    let definition = EdToolDefinition.readOnly(
        name: "battery_level",
        description: "Read the device battery percentage",
        parametersSchema: #"{"type":"object","properties":{},"additionalProperties":false}"#
    )

    func execute(arguments: String) async throws -> String {
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            return level < 0 ? "Battery level is unavailable." : "Battery is at \(Int(level * 100)) percent."
        }
    }
}

private actor NotesStore {
    private var notes: [String] = []

    func save(_ note: String) -> Int {
        notes.append(note)
        return notes.count
    }
}

private struct SaveNoteTool: EdTool {
    struct Arguments: Decodable { let text: String }

    let notes: NotesStore
    let definition = EdToolDefinition.mutating(
        name: "save_note",
        description: "Save a note in the app",
        parametersSchema: #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"],"additionalProperties":false}"#
    )

    func execute(arguments: String) async throws -> String {
        let decoded = try JSONDecoder().decode(Arguments.self, from: Data(arguments.utf8))
        let count = await notes.save(decoded.text)
        return "Saved note number \(count)."
    }
}
