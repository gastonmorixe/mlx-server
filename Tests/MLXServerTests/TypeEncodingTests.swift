import Foundation
import Testing

@testable import MLXServer

@Test func encodeResponse_hasSystemFingerprint() throws {
    let response = ChatCompletionResponse(
        id: "test-id",
        created: 1000,
        model: "test-model",
        choices: [
            .init(
                index: 0,
                message: .init(content: "hello", toolCalls: nil),
                finishReason: "stop"
            )
        ],
        usage: Usage(promptTokens: 5, completionTokens: 3, totalTokens: 8,
                     completionTokensDetails: nil)
    )

    let data = try JSONEncoder().encode(response)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["system_fingerprint"] as? String == "mlx-server-v1")
    #expect(json["object"] as? String == "chat.completion")
}

@Test func encodeResponse_snakeCaseKeys() throws {
    let response = ChatCompletionResponse(
        id: "test-id",
        created: 1000,
        model: "m",
        choices: [
            .init(
                index: 0,
                message: .init(content: "ok", toolCalls: nil),
                finishReason: "stop"
            )
        ],
        usage: Usage(promptTokens: 1, completionTokens: 2, totalTokens: 3,
                     completionTokensDetails: nil)
    )

    let data = try JSONEncoder().encode(response)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let usage = try #require(json["usage"] as? [String: Any])

    #expect(usage["prompt_tokens"] != nil)
    #expect(usage["completion_tokens"] != nil)
    #expect(usage["total_tokens"] != nil)
    // camelCase should NOT appear
    #expect(usage["promptTokens"] == nil)

    let choice = try #require((json["choices"] as? [[String: Any]])?.first)
    #expect(choice["finish_reason"] as? String == "stop")
    #expect(choice["finishReason"] == nil)
}

@Test func encodeUsage_withReasoningTokens() throws {
    let usage = Usage(
        promptTokens: 10, completionTokens: 50, totalTokens: 60,
        completionTokensDetails: .init(reasoningTokens: 30)
    )

    let data = try JSONEncoder().encode(usage)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let details = try #require(json["completion_tokens_details"] as? [String: Any])
    #expect(details["reasoning_tokens"] as? Int == 30)
}

@Test func encodeUsage_withoutReasoningTokens() throws {
    let usage = Usage(
        promptTokens: 10, completionTokens: 5, totalTokens: 15,
        completionTokensDetails: nil
    )

    let data = try JSONEncoder().encode(usage)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    // completion_tokens_details should be absent (nil is not encoded)
    #expect(json["completion_tokens_details"] == nil)
}

@Test func encodeChunk_hasSystemFingerprint() throws {
    let chunk = ChatCompletionChunk(
        id: "test",
        created: 1000,
        model: "m",
        choices: [
            .init(
                index: 0,
                delta: .init(role: "assistant", content: "hi", toolCalls: nil),
                finishReason: nil
            )
        ],
        usage: nil
    )

    let data = try JSONEncoder().encode(chunk)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["system_fingerprint"] as? String == "mlx-server-v1")
    #expect(json["object"] as? String == "chat.completion.chunk")
}

@Test func encodeErrorResponse() throws {
    let error = ErrorResponse(error: .init(
        message: "test error", type: "invalid_request_error", code: "bad_param"
    ))

    let data = try JSONEncoder().encode(error)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let errorObj = try #require(json["error"] as? [String: Any])
    #expect(errorObj["message"] as? String == "test error")
    #expect(errorObj["type"] as? String == "invalid_request_error")
    #expect(errorObj["code"] as? String == "bad_param")
}
