import Foundation
import MLX
import MLXLMCommon

/// Generation defaults read from a model's generation_config.json.
public struct ModelGenerationConfig: Sendable {
    public var temperature: Float?
    public var topP: Float?
    public var topK: Int?

    public static func load(from modelDirectory: URL) -> ModelGenerationConfig {
        let url = modelDirectory.appendingPathComponent("generation_config.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ModelGenerationConfig() }

        return ModelGenerationConfig(
            temperature: (json["temperature"] as? NSNumber)?.floatValue,
            topP: (json["top_p"] as? NSNumber)?.floatValue,
            topK: (json["top_k"] as? NSNumber)?.intValue
        )
    }
}

public final class InferenceService: Sendable {
    public let modelContainer: ModelContainer
    public let modelName: String
    public let createdTimestamp: Int
    public let enableThinking: Bool
    public let defaultMaxTokens: Int
    public let defaultTemperature: Float
    public let defaultTopP: Float
    public let defaultTopK: Int

    /// Serializes generation across requests. MLX/Metal command buffers are not
    /// safe under concurrent compute encoders, so each request holds the gate
    /// for the full prefill + decode lifetime.
    private let gate = GenerationGate()

    public init(
        modelContainer: ModelContainer,
        modelName: String,
        enableThinking: Bool,
        defaultMaxTokens: Int,
        defaultTemperature: Float,
        defaultTopP: Float,
        defaultTopK: Int
    ) {
        self.modelContainer = modelContainer
        self.modelName = modelName
        self.createdTimestamp = Int(Date().timeIntervalSince1970)
        self.enableThinking = enableThinking
        self.defaultMaxTokens = defaultMaxTokens
        self.defaultTemperature = defaultTemperature
        self.defaultTopP = defaultTopP
        self.defaultTopK = defaultTopK
    }

    // MARK: - Per-request reasoning (static for testability)

    static func resolveThinking(reasoningEffort: String?, defaultEnabled: Bool) -> Bool {
        if let effort = reasoningEffort {
            return effort != "none"
        }
        return defaultEnabled
    }

    static func resolveAdditionalContext(
        reasoningEffort: String?,
        thinkingActive: Bool,
        responseFormat: ResponseFormat?
    ) -> [String: any Sendable]? {
        var ctx: [String: any Sendable] = [:]

        if thinkingActive {
            ctx["enable_thinking"] = true
        }
        if let effort = reasoningEffort {
            ctx["reasoning_effort"] = effort
        }
        if let fmt = responseFormat, fmt.type == "json_object" {
            ctx["response_format"] = ["type": "json_object"]
        }

        return ctx.isEmpty ? nil : ctx
    }

    // MARK: - Message conversion (static for testability)

    /// Convert OpenAI messages to raw Message dictionaries for the tokenizer template.
    /// Maps "developer" role to "system" for broad model compatibility.
    static func convertMessages(_ messages: [ChatMessage]) -> [Message] {
        messages.map { msg in
            var dict: Message = ["role": msg.role == "developer" ? "system" : msg.role]

            if let content = msg.content {
                dict["content"] = content.textValue ?? ""
            }

            if let toolCalls = msg.toolCalls {
                dict["tool_calls"] = toolCalls.map { tc -> [String: any Sendable] in
                    [
                        "id": tc.id,
                        "type": tc.type,
                        "function": [
                            "name": tc.function.name,
                            "arguments": tc.function.arguments,
                        ] as [String: any Sendable],
                    ]
                }
            }

            if let toolCallId = msg.toolCallId {
                dict["tool_call_id"] = toolCallId
            }

            if let name = msg.name {
                dict["name"] = name
            }

            return dict
        }
    }

    /// Convert OpenAI tool definitions to ToolSpec format (pass-through, same shape).
    static func convertTools(_ tools: [ToolDefinition]?) -> [ToolSpec]? {
        guard let tools else { return nil }
        return tools.map { tool in
            [
                "type": tool.type,
                "function": [
                    "name": tool.function.name,
                    "description": tool.function.description ?? "",
                    "parameters": tool.function.parameters?.asDictionary ?? [:],
                ] as [String: any Sendable],
            ] as ToolSpec
        }
    }

    // MARK: - Parameter building

    struct Defaults: Sendable {
        let maxTokens: Int
        let temperature: Float
        let topP: Float
        let topK: Int
    }

    var defaults: Defaults {
        Defaults(maxTokens: defaultMaxTokens, temperature: defaultTemperature,
                 topP: defaultTopP, topK: defaultTopK)
    }

    static func buildParameters(from request: ChatCompletionRequest, defaults: Defaults) -> GenerateParameters {
        let resolvedMaxTokens = request.maxCompletionTokens ?? request.maxTokens ?? defaults.maxTokens

        return GenerateParameters(
            maxTokens: resolvedMaxTokens,
            temperature: request.temperature ?? defaults.temperature,
            topP: request.topP ?? defaults.topP,
            topK: request.topK ?? defaults.topK,
            repetitionPenalty: request.repetitionPenalty,
            presencePenalty: request.presencePenalty,
            frequencyPenalty: request.frequencyPenalty
        )
    }

    // MARK: - Generation

    struct CompletionResult: Sendable {
        let text: String
        let toolCalls: [ResponseToolCall]
        let finishReason: String
        let promptTokens: Int
        let completionTokens: Int
        let reasoningTokens: Int
    }

    func generate(request: ChatCompletionRequest) async throws -> CompletionResult {
        try await gate.withLock {
            try await self.generateLocked(request: request)
        }
    }

    private func generateLocked(request: ChatCompletionRequest) async throws -> CompletionResult {
        let messages = Self.convertMessages(request.messages)
        let tools = Self.convertTools(request.tools)
        let parameters = Self.buildParameters(from: request, defaults: defaults)
        let thinkingActive = Self.resolveThinking(
            reasoningEffort: request.reasoningEffort, defaultEnabled: enableThinking)
        let context = Self.resolveAdditionalContext(
            reasoningEffort: request.reasoningEffort, thinkingActive: thinkingActive,
            responseFormat: request.responseFormat)

        if let seed = request.seed {
            MLXRandom.seed(UInt64(seed))
        }

        let userInput = UserInput(messages: messages, tools: tools, additionalContext: context)
        let lmInput = try await modelContainer.prepare(input: userInput)
        let stream = try await modelContainer.generate(input: lmInput, parameters: parameters)

        var text = ""
        var toolCalls = [ResponseToolCall]()
        var finishReason = "stop"
        var promptTokens = 0
        var completionTokens = 0

        for await generation in stream {
            switch generation {
            case .chunk(let chunk):
                text += chunk
            case .toolCall(let tc):
                let argsData = try JSONEncoder().encode(tc.function.arguments)
                let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                let callId = "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))"
                toolCalls.append(ResponseToolCall(
                    id: callId,
                    function: .init(name: tc.function.name, arguments: argsString)
                ))
            case .info(let info):
                promptTokens = info.promptTokenCount
                completionTokens = info.generationTokenCount
                switch info.stopReason {
                case .stop: finishReason = "stop"
                case .length: finishReason = "length"
                case .cancelled: finishReason = "stop"
                }
            }
        }

        if !toolCalls.isEmpty {
            finishReason = "tool_calls"
        }

        let (strippedText, reasoningTokens) = Self.stripThinkingWithCount(
            text, totalTokens: completionTokens, thinkingActive: thinkingActive)

        return CompletionResult(
            text: strippedText,
            toolCalls: toolCalls,
            finishReason: finishReason,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            reasoningTokens: reasoningTokens
        )
    }

    /// Streaming variant: yields SSE-formatted strings.
    /// The generation gate is held from prefill until the stream finishes.
    func generateStream(request: ChatCompletionRequest) async throws -> AsyncStream<String> {
        let messages = Self.convertMessages(request.messages)
        let tools = Self.convertTools(request.tools)
        let parameters = Self.buildParameters(from: request, defaults: defaults)
        let completionId = "chatcmpl-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))"
        let model = request.model ?? modelName
        let created = Int(Date().timeIntervalSince1970)
        let thinkingActive = Self.resolveThinking(
            reasoningEffort: request.reasoningEffort, defaultEnabled: enableThinking)
        let includeUsage = request.streamOptions?.includeUsage == true
        let context = Self.resolveAdditionalContext(
            reasoningEffort: request.reasoningEffort, thinkingActive: thinkingActive,
            responseFormat: request.responseFormat)

        // Acquire the gate before any model interaction. Released inside the
        // stream task once generation is fully drained (or on error below).
        await gate.acquire()

        let lmInput: LMInput
        let generationStream: AsyncStream<Generation>
        do {
            if let seed = request.seed {
                MLXRandom.seed(UInt64(seed))
            }
            let userInput = UserInput(messages: messages, tools: tools, additionalContext: context)
            lmInput = try await modelContainer.prepare(input: userInput)
            generationStream = try await modelContainer.generate(input: lmInput, parameters: parameters)
        } catch {
            await gate.release()
            throw error
        }

        let gate = self.gate
        return AsyncStream<String> { continuation in
            Task {
                var isFirstChunk = true
                var toolCallIndex = 0
                var hasToolCalls = false
                var thinkingBuffer: String?
                var thinkingCharCount = 0
                var contentCharCount = 0

                for await generation in generationStream {
                    switch generation {
                    case .chunk(let text):
                        var emitText: String? = text
                        if thinkingActive {
                            if let buffer = thinkingBuffer {
                                let nextBuffer = buffer + text
                                if nextBuffer.contains("<channel|>") {
                                    let parts = nextBuffer.components(separatedBy: "<channel|>")
                                    thinkingCharCount = parts.first?.count ?? 0
                                    let afterThinking = parts.dropFirst().joined(separator: "<channel|>")
                                    thinkingBuffer = nil
                                    emitText = afterThinking.isEmpty ? nil : afterThinking
                                } else {
                                    thinkingBuffer = nextBuffer
                                    emitText = nil
                                }
                            } else if let start = text.range(of: "<|channel>") {
                                let prefix = String(text[..<start.lowerBound])
                                let suffix = String(text[start.lowerBound...])
                                thinkingBuffer = suffix
                                if suffix.contains("<channel|>") {
                                    let parts = suffix.components(separatedBy: "<channel|>")
                                    thinkingCharCount = parts.first?.count ?? 0
                                    let afterThinking = parts.dropFirst().joined(separator: "<channel|>")
                                    thinkingBuffer = nil
                                    emitText = [prefix, afterThinking].joined()
                                } else {
                                    emitText = prefix.isEmpty ? nil : prefix
                                }
                            } else {
                                emitText = text
                            }
                        }

                        guard let content = emitText else { continue }
                        contentCharCount += content.count
                        let chunk = ChatCompletionChunk(
                            id: completionId,
                            created: created,
                            model: model,
                            choices: [
                                .init(
                                    index: 0,
                                    delta: .init(
                                        role: isFirstChunk ? "assistant" : nil,
                                        content: content,
                                        toolCalls: nil
                                    ),
                                    finishReason: nil
                                )
                            ],
                            usage: nil
                        )
                        isFirstChunk = false
                        if let encoded = try? SSE.encode(chunk) {
                            continuation.yield(encoded)
                        }

                    case .toolCall(let tc):
                        hasToolCalls = true
                        let argsData = (try? JSONEncoder().encode(tc.function.arguments)) ?? Data()
                        let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                        let callId = "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))"

                        let chunk = ChatCompletionChunk(
                            id: completionId,
                            created: created,
                            model: model,
                            choices: [
                                .init(
                                    index: 0,
                                    delta: .init(
                                        role: isFirstChunk ? "assistant" : nil,
                                        content: nil,
                                        toolCalls: [
                                            .init(
                                                index: toolCallIndex,
                                                id: callId,
                                                type: "function",
                                                function: .init(
                                                    name: tc.function.name,
                                                    arguments: argsString
                                                )
                                            )
                                        ]
                                    ),
                                    finishReason: nil
                                )
                            ],
                            usage: nil
                        )
                        isFirstChunk = false
                        toolCallIndex += 1
                        if let encoded = try? SSE.encode(chunk) {
                            continuation.yield(encoded)
                        }

                    case .info(let info):
                        let reason: String
                        if hasToolCalls {
                            reason = "tool_calls"
                        } else {
                            switch info.stopReason {
                            case .stop: reason = "stop"
                            case .length: reason = "length"
                            case .cancelled: reason = "stop"
                            }
                        }

                        let reasoningTokens = Self.estimateReasoningTokens(
                            thinkingChars: thinkingCharCount,
                            contentChars: contentCharCount,
                            totalTokens: info.generationTokenCount
                        )

                        let usage: Usage? = includeUsage ? Usage(
                            promptTokens: info.promptTokenCount,
                            completionTokens: info.generationTokenCount,
                            totalTokens: info.promptTokenCount + info.generationTokenCount,
                            completionTokensDetails: reasoningTokens > 0
                                ? .init(reasoningTokens: reasoningTokens) : nil
                        ) : nil

                        let finalChunk = ChatCompletionChunk(
                            id: completionId,
                            created: created,
                            model: model,
                            choices: [
                                .init(
                                    index: 0,
                                    delta: .init(role: nil, content: nil, toolCalls: nil),
                                    finishReason: reason
                                )
                            ],
                            usage: usage
                        )
                        if let encoded = try? SSE.encode(finalChunk) {
                            continuation.yield(encoded)
                        }
                    }
                }

                continuation.yield(SSE.done)
                continuation.finish()
                await gate.release()
            }
        }
    }

    // MARK: - Thinking helpers

    /// Strip thinking content and estimate reasoning token count.
    static func stripThinkingWithCount(
        _ text: String, totalTokens: Int, thinkingActive: Bool
    ) -> (text: String, reasoningTokens: Int) {
        guard thinkingActive else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), 0)
        }

        let totalChars = text.count
        guard totalChars > 0 else { return ("", 0) }

        var thinkingChars = 0
        var result = text
        while let startRange = result.range(of: "<|channel>") {
            if let endRange = result.range(of: "<channel|>", range: startRange.upperBound..<result.endIndex) {
                let blockLength = result.distance(from: startRange.lowerBound, to: endRange.upperBound)
                thinkingChars += blockLength
                result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                let blockLength = result.distance(from: startRange.lowerBound, to: result.endIndex)
                thinkingChars += blockLength
                result.removeSubrange(startRange.lowerBound..<result.endIndex)
            }
        }

        let reasoningTokens = estimateReasoningTokens(
            thinkingChars: thinkingChars, contentChars: totalChars - thinkingChars, totalTokens: totalTokens)

        return (result.trimmingCharacters(in: .whitespacesAndNewlines), reasoningTokens)
    }

    /// Estimate reasoning tokens via character ratio.
    static func estimateReasoningTokens(thinkingChars: Int, contentChars: Int, totalTokens: Int) -> Int {
        let total = thinkingChars + contentChars
        guard total > 0, thinkingChars > 0 else { return 0 }
        return Int(round(Double(totalTokens) * Double(thinkingChars) / Double(total)))
    }
}
