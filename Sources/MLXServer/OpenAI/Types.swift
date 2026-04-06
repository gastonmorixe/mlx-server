import Foundation

// MARK: - Request types

struct StreamOptions: Decodable, Sendable {
    let includeUsage: Bool?

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

struct ResponseFormat: Decodable, Sendable {
    let type: String  // "text" or "json_object"
}

struct ChatCompletionRequest: Decodable, Sendable {
    let model: String?
    let messages: [ChatMessage]
    let temperature: Float?
    let topP: Float?
    let topK: Int?
    let maxTokens: Int?
    let maxCompletionTokens: Int?
    let stream: Bool?
    let streamOptions: StreamOptions?
    let tools: [ToolDefinition]?
    let toolChoice: ToolChoice?
    let frequencyPenalty: Float?
    let presencePenalty: Float?
    let repetitionPenalty: Float?
    let stop: StopSequences?
    let reasoningEffort: String?
    let seed: Int?
    let n: Int?
    let responseFormat: ResponseFormat?
    let user: String?
    let logprobs: Bool?
    let topLogprobs: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, tools, stop, seed, n, user, logprobs
        case topP = "top_p"
        case topK = "top_k"
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case streamOptions = "stream_options"
        case toolChoice = "tool_choice"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
        case repetitionPenalty = "repetition_penalty"
        case reasoningEffort = "reasoning_effort"
        case responseFormat = "response_format"
        case topLogprobs = "top_logprobs"
    }

    static let validReasoningEfforts: Set<String> = [
        "none", "minimal", "low", "medium", "high", "xhigh",
    ]

    func validate() -> ErrorResponse? {
        if let n, n > 1 {
            return ErrorResponse(error: .init(
                message: "n > 1 is not supported. Only single completions are available.",
                type: "invalid_request_error",
                code: "unsupported_parameter"
            ))
        }
        if let effort = reasoningEffort,
           !Self.validReasoningEfforts.contains(effort)
        {
            return ErrorResponse(error: .init(
                message: "Invalid reasoning_effort '\(effort)'. Must be one of: none, minimal, low, medium, high, xhigh.",
                type: "invalid_request_error",
                code: "invalid_parameter"
            ))
        }
        return nil
    }
}

enum StopSequences: Decodable, Sendable {
    case single(String)
    case multiple([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .single(s)
        } else {
            self = .multiple(try container.decode([String].self))
        }
    }

    var sequences: [String] {
        switch self {
        case .single(let s): [s]
        case .multiple(let a): a
        }
    }
}

enum ToolChoice: Decodable, Sendable {
    case auto
    case none
    case required
    case function(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            switch s {
            case "auto": self = .auto
            case "none": self = .none
            case "required": self = .required
            default: self = .auto
            }
        } else {
            let obj = try container.decode(ToolChoiceObject.self)
            self = .function(obj.function.name)
        }
    }

    private struct ToolChoiceObject: Decodable {
        let function: FunctionName
        struct FunctionName: Decodable {
            let name: String
        }
    }
}

struct ChatMessage: Decodable, Sendable {
    let role: String
    let content: MessageContent?
    let toolCalls: [RequestToolCall]?
    let toolCallId: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }
}

enum MessageContent: Decodable, Sendable {
    case text(String)
    case parts([ContentPart])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .text(s)
        } else {
            self = .parts(try container.decode([ContentPart].self))
        }
    }

    var textValue: String? {
        switch self {
        case .text(let s): s
        case .parts(let parts):
            parts.compactMap {
                if case .text(let t) = $0 { return t }
                return nil
            }.joined()
        }
    }
}

enum ContentPart: Decodable, Sendable {
    case text(String)
    case imageURL(String)

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    private struct ImageURL: Decodable {
        let url: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image_url":
            let img = try container.decode(ImageURL.self, forKey: .imageURL)
            self = .imageURL(img.url)
        default:
            self = .text("")
        }
    }
}

struct RequestToolCall: Decodable, Sendable {
    let id: String
    let type: String
    let function: RequestToolFunction
}

struct RequestToolFunction: Decodable, Sendable {
    let name: String
    let arguments: String
}

struct ToolDefinition: Decodable, Sendable {
    let type: String
    let function: FunctionDefinition
}

struct FunctionDefinition: Decodable, Sendable {
    let name: String
    let description: String?
    let parameters: JSONObject?
}

/// Loosely-typed JSON object for tool parameter schemas.
struct JSONObject: Decodable, Sendable {
    let storage: [String: AnyCodable]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: AnyCodable].self)
        self.storage = dict
    }

    var asDictionary: [String: any Sendable] {
        storage.mapValues { $0.value }
    }
}

struct AnyCodable: Decodable, Sendable {
    let value: any Sendable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let a = try? container.decode([AnyCodable].self) {
            value = a.map { $0.value }
        } else if let o = try? container.decode([String: AnyCodable].self) {
            value = o.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
}

// MARK: - Response types

struct ChatCompletionResponse: Encodable, Sendable {
    let id: String
    let object: String = "chat.completion"
    let created: Int
    let model: String
    let systemFingerprint: String? = "mlx-server-v1"
    let choices: [Choice]
    let usage: Usage

    enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage
        case systemFingerprint = "system_fingerprint"
    }

    struct Choice: Encodable, Sendable {
        let index: Int
        let message: ResponseMessage
        let finishReason: String

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct ResponseMessage: Encodable, Sendable {
        let role: String = "assistant"
        let content: String?
        let toolCalls: [ResponseToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }
}

struct ResponseToolCall: Encodable, Sendable {
    let id: String
    let type: String = "function"
    let function: ResponseToolFunction

    struct ResponseToolFunction: Encodable, Sendable {
        let name: String
        let arguments: String
    }
}

struct Usage: Encodable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let completionTokensDetails: CompletionTokensDetails?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case completionTokensDetails = "completion_tokens_details"
    }

    struct CompletionTokensDetails: Encodable, Sendable {
        let reasoningTokens: Int

        enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
        }
    }
}

// MARK: - Streaming types

struct ChatCompletionChunk: Encodable, Sendable {
    let id: String
    let object: String = "chat.completion.chunk"
    let created: Int
    let model: String
    let systemFingerprint: String? = "mlx-server-v1"
    let choices: [ChunkChoice]
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage
        case systemFingerprint = "system_fingerprint"
    }

    struct ChunkChoice: Encodable, Sendable {
        let index: Int
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Encodable, Sendable {
        let role: String?
        let content: String?
        let toolCalls: [DeltaToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }

    struct DeltaToolCall: Encodable, Sendable {
        let index: Int
        let id: String?
        let type: String?
        let function: DeltaFunction?

        struct DeltaFunction: Encodable, Sendable {
            let name: String?
            let arguments: String?
        }
    }
}

// MARK: - Models endpoint

struct ModelsResponse: Encodable, Sendable {
    let object: String = "list"
    let data: [ModelObject]

    struct ModelObject: Encodable, Sendable {
        let id: String
        let object: String = "model"
        let created: Int
        let ownedBy: String = "mlx-server"

        enum CodingKeys: String, CodingKey {
            case id, object, created
            case ownedBy = "owned_by"
        }
    }
}

// MARK: - Error response

struct ErrorResponse: Encodable, Sendable {
    let error: ErrorDetail

    struct ErrorDetail: Encodable, Sendable {
        let message: String
        let type: String
        let code: String?
    }
}
