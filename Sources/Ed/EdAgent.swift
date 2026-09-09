import Foundation

/// A capability your app makes available to the local model.
///
/// Ed never invents native capabilities. Your app registers each tool and
/// remains responsible for executing it.
public protocol EdTool: Sendable {
    var definition: EdToolDefinition { get }

    /// Executes the tool with the JSON object produced by the model.
    func execute(arguments: String) async throws -> String
}

public enum EdToolRisk: Sendable {
    /// Safe to run without asking, such as reading app state.
    case readOnly

    /// Changes state and must be approved first, such as saving or deleting.
    case mutating
}

public struct EdToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let parametersSchema: String
    public let risk: EdToolRisk

    public init(
        name: String,
        description: String,
        parametersSchema: String,
        risk: EdToolRisk
    ) {
        self.name = name
        self.description = description
        self.parametersSchema = parametersSchema
        self.risk = risk
    }

    public static func readOnly(
        name: String,
        description: String,
        parametersSchema: String
    ) -> Self {
        Self(
            name: name,
            description: description,
            parametersSchema: parametersSchema,
            risk: .readOnly
        )
    }

    public static func mutating(
        name: String,
        description: String,
        parametersSchema: String
    ) -> Self {
        Self(
            name: name,
            description: description,
            parametersSchema: parametersSchema,
            risk: .mutating
        )
    }
}

public struct EdToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let arguments: String
}

public enum EdApprovalDecision: Sendable {
    case allowOnce
    case allowForSession
    case deny
}

public typealias EdApprovalHandler = @Sendable (EdToolCall) async -> EdApprovalDecision

public struct EdAgentConfiguration: Sendable {
    public var maxToolRounds: UInt8
    public var maxToolOutputCharacters: UInt64

    public init(maxToolRounds: UInt8 = 8, maxToolOutputCharacters: UInt64 = 10_000) {
        self.maxToolRounds = maxToolRounds
        self.maxToolOutputCharacters = maxToolOutputCharacters
    }
}

public struct EdAgentReply: Sendable, Equatable {
    public let text: String
    public let durationSeconds: Double
    public let duration: String
    public let toolRounds: UInt8
}

public struct EdReply: Sendable, Equatable {
    public let text: String
    public let duration: String
}

public enum EdEngineStatus: Sendable {
    case unloaded
    case loading
    case ready
    case generating
    case error
}

public struct EdEngineInfo: Sendable {
    public let status: EdEngineStatus
    public let modelName: String?
    public let approximateMemory: String?
    public let historyLength: UInt64
}

public enum EdChatRole: Sendable {
    case system
    case user
    case assistant
}

public struct EdChatMessage: Sendable {
    public let role: EdChatRole
    public let content: String
}

public enum EdEvent: Sendable {
    case statusChanged(status: EdEngineStatus, modelName: String?, error: String?)
    case toolRequested(EdToolCall)
    case approvalRequested(EdToolCall)
    case toolStarted(EdToolCall)
    case toolFinished(callID: String, content: String, isError: Bool)
    case agentReplied(EdAgentReply)
    case warning(String)
}

public struct EdSamplingConfiguration: Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var topK: UInt64?
    public var minP: Double?
    public var maxTokens: UInt64?
    public var frequencyPenalty: Float?
    public var presencePenalty: Float?

    public init(
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: UInt64? = nil,
        minP: Double? = nil,
        maxTokens: UInt64? = nil,
        frequencyPenalty: Float? = nil,
        presencePenalty: Float? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.maxTokens = maxTokens
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
    }
}

public struct EdGGUFModelConfiguration: Sendable {
    public var modelID: String
    public var files: [String]
    public var tokenizerModelID: String?
    public var displayName: String
    public var approximateMemory: String
    public var chatTemplate: String?

    public init(
        modelID: String,
        files: [String],
        tokenizerModelID: String? = nil,
        displayName: String,
        approximateMemory: String,
        chatTemplate: String? = nil
    ) {
        self.modelID = modelID
        self.files = files
        self.tokenizerModelID = tokenizerModelID
        self.displayName = displayName
        self.approximateMemory = approximateMemory
        self.chatTemplate = chatTemplate
    }
}

public struct EdUQFFModelConfiguration: Sendable {
    public var modelID: String
    public var files: [String]
    public var displayName: String
    public var approximateMemory: String
    public var chatTemplate: String?

    public init(
        modelID: String,
        files: [String],
        displayName: String,
        approximateMemory: String,
        chatTemplate: String? = nil
    ) {
        self.modelID = modelID
        self.files = files
        self.displayName = displayName
        self.approximateMemory = approximateMemory
        self.chatTemplate = chatTemplate
    }
}

public enum EdEnvironment: Sendable {
    case development
    case production
}

/// A local agent powered by Onde.
///
/// The actor protects model history, the tool registry, and inference so your
/// UI can call it safely from Swift concurrency.
public actor EdAgent {
    private let core: FfiEdAgent
    private let tools: ToolDispatcher
    private let approvals: ApprovalAdapter
    private nonisolated let eventHub: EventHub

    public init(
        configuration: EdAgentConfiguration = .init(),
        approvalHandler: @escaping EdApprovalHandler = { _ in .deny }
    ) {
        let tools = ToolDispatcher()
        let approvals = ApprovalAdapter(handler: approvalHandler)
        let eventHub = EventHub()

        self.tools = tools
        self.approvals = approvals
        self.eventHub = eventHub
        self.core = FfiEdAgent(
            executor: tools,
            approvals: approvals,
            events: eventHub,
            config: FfiAgentConfig(
                maxToolRounds: configuration.maxToolRounds,
                maxToolOutputChars: configuration.maxToolOutputCharacters
            )
        )
    }

    /// A separate stream for each observer. Stop its task to unsubscribe.
    public nonisolated func events() -> AsyncStream<EdEvent> {
        eventHub.makeStream()
    }

    public func register(_ tool: any EdTool) async throws {
        try await core.registerTool(tool: tool.definition.ffi)
        tools.set(tool)
    }

    @discardableResult
    public func unregisterTool(named name: String) async -> Bool {
        let removed = await core.unregisterTool(name: name)
        if removed {
            tools.remove(named: name)
        }
        return removed
    }

    public func removeAllTools() async {
        await core.removeAllTools()
        tools.removeAll()
    }

    /// Runs the full agent loop: model -> tool calls -> tool results -> model.
    public func run(_ message: String) async throws -> EdAgentReply {
        try await withTaskCancellationHandler {
            try await core.run(message: message).swift
        } onCancel: {
            core.cancel()
        }
    }

    /// Sends one ordinary chat turn without exposing tools to the model.
    public func send(_ message: String) async throws -> EdReply {
        let reply = try await core.send(message: message)
        return EdReply(text: reply.text, duration: reply.duration)
    }

    /// Loads a small tool-capable model chosen for the current Apple device.
    @discardableResult
    public func loadDefaultAgentModel(systemPrompt: String? = nil) async throws -> Double {
        try await core.loadDefaultAgentModel(systemPrompt: systemPrompt)
    }

    @discardableResult
    public func load(
        gguf config: EdGGUFModelConfiguration,
        systemPrompt: String? = nil,
        sampling: EdSamplingConfiguration? = nil
    ) async throws -> Double {
        try await core.loadGgufModel(
            config: config.ffi,
            systemPrompt: systemPrompt,
            sampling: sampling?.ffi
        )
    }

    @discardableResult
    public func load(
        uqff config: EdUQFFModelConfiguration,
        systemPrompt: String? = nil,
        sampling: EdSamplingConfiguration? = nil
    ) async throws -> Double {
        try await core.loadUqffModel(
            config: config.ffi,
            systemPrompt: systemPrompt,
            sampling: sampling?.ffi
        )
    }

    @discardableResult
    public func loadAssignedModel(
        environment: EdEnvironment,
        appID: String,
        appSecret: String,
        systemPrompt: String? = nil,
        sampling: EdSamplingConfiguration? = nil
    ) async throws -> Double {
        try await core.loadAssignedModel(
            environment: environment.ffi,
            appId: appID,
            appSecret: appSecret,
            systemPrompt: systemPrompt,
            sampling: sampling?.ffi
        )
    }

    public nonisolated func cancel() {
        core.cancel()
    }

    @discardableResult
    public func unload() async -> String? {
        await core.unload()
    }

    public func isLoaded() async -> Bool {
        await core.isLoaded()
    }

    public func info() async -> EdEngineInfo {
        let info = await core.info()
        return EdEngineInfo(
            status: info.status.swift,
            modelName: info.modelName,
            approximateMemory: info.approxMemory,
            historyLength: info.historyLength
        )
    }

    public func history() async -> [EdChatMessage] {
        await core.history().map(\.swift)
    }

    @discardableResult
    public func clearHistory() async -> UInt64 {
        await core.clearHistory()
    }

    public static func configureCacheDirectory(_ url: URL) {
        configureCacheDir(path: url.path)
    }

    public static func defaultAgentModelConfiguration() -> EdGGUFModelConfiguration {
        defaultAgentModelConfig().swift
    }
}

private final class ToolDispatcher: FfiToolExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var tools: [String: any EdTool] = [:]

    func set(_ tool: any EdTool) {
        lock.withLock { tools[tool.definition.name] = tool }
    }

    func remove(named name: String) {
        lock.withLock { _ = tools.removeValue(forKey: name) }
    }

    func removeAll() {
        lock.withLock { tools.removeAll() }
    }

    func execute(toolName: String, arguments: String) async -> FfiToolOutput {
        let tool = lock.withLock { tools[toolName] }
        guard let tool else {
            return FfiToolOutput(content: "", error: "Unknown tool: \(toolName)")
        }

        do {
            return FfiToolOutput(
                content: try await tool.execute(arguments: arguments),
                error: nil
            )
        } catch {
            return FfiToolOutput(content: "", error: String(describing: error))
        }
    }
}

private final class ApprovalAdapter: FfiApprovalHandler, @unchecked Sendable {
    private let handler: EdApprovalHandler

    init(handler: @escaping EdApprovalHandler) {
        self.handler = handler
    }

    func approve(call: FfiToolCall) async -> FfiApprovalDecision {
        await handler(call.swift).ffi
    }
}

private final class EventHub: FfiEventListener, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<EdEvent>.Continuation] = [:]

    func makeStream() -> AsyncStream<EdEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    func statusChanged(update: FfiStatusUpdate) {
        emit(.statusChanged(
            status: update.status.swift,
            modelName: update.modelName,
            error: update.error
        ))
    }

    func toolRequested(call: FfiToolCall) { emit(.toolRequested(call.swift)) }
    func approvalRequested(call: FfiToolCall) { emit(.approvalRequested(call.swift)) }
    func toolStarted(call: FfiToolCall) { emit(.toolStarted(call.swift)) }

    func toolFinished(toolCallId: String, content: String, isError: Bool) {
        emit(.toolFinished(callID: toolCallId, content: content, isError: isError))
    }

    func agentReplied(reply: FfiAgentReply) { emit(.agentReplied(reply.swift)) }
    func warning(message: String) { emit(.warning(message)) }

    private func emit(_ event: EdEvent) {
        let current = lock.withLock { Array(continuations.values) }
        current.forEach { $0.yield(event) }
    }
}

private extension EdToolDefinition {
    var ffi: FfiToolDefinition {
        FfiToolDefinition(
            name: name,
            description: description,
            parametersSchema: parametersSchema,
            risk: risk == .readOnly ? .readOnly : .mutating
        )
    }
}

private extension FfiToolCall {
    var swift: EdToolCall { EdToolCall(id: id, name: name, arguments: arguments) }
}

private extension EdApprovalDecision {
    var ffi: FfiApprovalDecision {
        switch self {
        case .allowOnce: .allowOnce
        case .allowForSession: .allowForSession
        case .deny: .deny
        }
    }
}

private extension FfiAgentReply {
    var swift: EdAgentReply {
        EdAgentReply(
            text: text,
            durationSeconds: durationSeconds,
            duration: duration,
            toolRounds: toolRounds
        )
    }
}

private extension FfiEngineStatus {
    var swift: EdEngineStatus {
        switch self {
        case .unloaded: .unloaded
        case .loading: .loading
        case .ready: .ready
        case .generating: .generating
        case .error: .error
        }
    }
}

private extension FfiChatMessage {
    var swift: EdChatMessage {
        let role: EdChatRole = switch self.role {
        case .system: .system
        case .user: .user
        case .assistant: .assistant
        }
        return EdChatMessage(role: role, content: content)
    }
}

private extension EdSamplingConfiguration {
    var ffi: FfiSamplingConfig {
        FfiSamplingConfig(
            temperature: temperature,
            topP: topP,
            topK: topK,
            minP: minP,
            maxTokens: maxTokens,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty
        )
    }
}

private extension EdGGUFModelConfiguration {
    var ffi: FfiGgufModelConfig {
        FfiGgufModelConfig(
            modelId: modelID,
            files: files,
            tokModelId: tokenizerModelID,
            displayName: displayName,
            approxMemory: approximateMemory,
            chatTemplate: chatTemplate
        )
    }
}

private extension FfiGgufModelConfig {
    var swift: EdGGUFModelConfiguration {
        EdGGUFModelConfiguration(
            modelID: modelId,
            files: files,
            tokenizerModelID: tokModelId,
            displayName: displayName,
            approximateMemory: approxMemory,
            chatTemplate: chatTemplate
        )
    }
}

private extension EdUQFFModelConfiguration {
    var ffi: FfiUqffModelConfig {
        FfiUqffModelConfig(
            modelId: modelID,
            files: files,
            displayName: displayName,
            approxMemory: approximateMemory,
            chatTemplate: chatTemplate
        )
    }
}

private extension EdEnvironment {
    var ffi: FfiEnvironment {
        switch self {
        case .development: .development
        case .production: .production
        }
    }
}
