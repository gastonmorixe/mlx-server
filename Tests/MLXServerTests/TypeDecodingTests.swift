import Foundation
import Testing

@testable import MLXServer

@Test func decodeRequest_minimal() throws {
    let json = #"{"messages":[{"role":"user","content":"hi"}]}"#
    let req = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    #expect(req.messages.count == 1)
    #expect(req.messages[0].role == "user")
    #expect(req.temperature == nil)
    #expect(req.stream == nil)
    #expect(req.reasoningEffort == nil)
}

@Test func decodeRequest_allFields() throws {
    let json = """
    {
        "model": "test-model",
        "messages": [{"role": "user", "content": "hi"}],
        "temperature": 0.7,
        "top_p": 0.9,
        "top_k": 32,
        "max_tokens": 100,
        "max_completion_tokens": 200,
        "stream": true,
        "stream_options": {"include_usage": true},
        "reasoning_effort": "high",
        "seed": 42,
        "n": 1,
        "response_format": {"type": "json_object"},
        "user": "test-user",
        "frequency_penalty": 0.5,
        "presence_penalty": 0.3,
        "repetition_penalty": 1.1,
        "logprobs": true,
        "top_logprobs": 5
    }
    """
    let req = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    #expect(req.model == "test-model")
    #expect(req.temperature == 0.7)
    #expect(req.topP == 0.9)
    #expect(req.topK == 32)
    #expect(req.maxTokens == 100)
    #expect(req.maxCompletionTokens == 200)
    #expect(req.stream == true)
    #expect(req.streamOptions?.includeUsage == true)
    #expect(req.reasoningEffort == "high")
    #expect(req.seed == 42)
    #expect(req.n == 1)
    #expect(req.responseFormat?.type == "json_object")
    #expect(req.user == "test-user")
    #expect(req.frequencyPenalty == 0.5)
    #expect(req.presencePenalty == 0.3)
    #expect(req.repetitionPenalty == 1.1)
    #expect(req.logprobs == true)
    #expect(req.topLogprobs == 5)
}

@Test func decodeMessageContent_textString() throws {
    let json = #"{"role":"user","content":"hello world"}"#
    let msg = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    #expect(msg.content?.textValue == "hello world")
}

@Test func decodeMessageContent_partsArray() throws {
    let json = """
    {
        "role": "user",
        "content": [
            {"type": "text", "text": "Look at this"},
            {"type": "image_url", "image_url": {"url": "https://example.com/img.png"}}
        ]
    }
    """
    let msg = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    #expect(msg.content?.textValue == "Look at this")
}

@Test func decodeToolChoice_stringVariants() throws {
    for value in ["auto", "none", "required"] {
        let json = #""\#(value)""#
        let choice = try JSONDecoder().decode(ToolChoice.self, from: Data(json.utf8))
        switch (value, choice) {
        case ("auto", .auto), ("none", .none), ("required", .required): break
        default: Issue.record("Unexpected ToolChoice for \(value): \(choice)")
        }
    }
}

@Test func decodeToolChoice_functionObject() throws {
    let json = #"{"type":"function","function":{"name":"get_weather"}}"#
    let choice = try JSONDecoder().decode(ToolChoice.self, from: Data(json.utf8))
    if case .function(let name) = choice {
        #expect(name == "get_weather")
    } else {
        Issue.record("Expected .function, got \(choice)")
    }
}

@Test func decodeStopSequences_single() throws {
    let json = #""\n\n""#
    let stop = try JSONDecoder().decode(StopSequences.self, from: Data(json.utf8))
    #expect(stop.sequences == ["\n\n"])
}

@Test func decodeStopSequences_array() throws {
    let json = #"["stop1", "stop2"]"#
    let stop = try JSONDecoder().decode(StopSequences.self, from: Data(json.utf8))
    #expect(stop.sequences == ["stop1", "stop2"])
}

@Test func decodeStreamOptions() throws {
    let json = #"{"include_usage": true}"#
    let opts = try JSONDecoder().decode(StreamOptions.self, from: Data(json.utf8))
    #expect(opts.includeUsage == true)
}

@Test func decodeResponseFormat() throws {
    let json = #"{"type": "json_object"}"#
    let fmt = try JSONDecoder().decode(ResponseFormat.self, from: Data(json.utf8))
    #expect(fmt.type == "json_object")
}

@Test func decodeChatMessage_withToolCalls() throws {
    let json = """
    {
        "role": "assistant",
        "content": null,
        "tool_calls": [{
            "id": "call_abc",
            "type": "function",
            "function": {"name": "get_weather", "arguments": "{\\"city\\":\\"Tokyo\\"}"}
        }]
    }
    """
    let msg = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    #expect(msg.role == "assistant")
    #expect(msg.content == nil)
    let tc = try #require(msg.toolCalls?.first)
    #expect(tc.id == "call_abc")
    #expect(tc.function.name == "get_weather")
}

@Test func decodeChatMessage_toolResult() throws {
    let json = #"{"role":"tool","tool_call_id":"call_abc","content":"{\"temp\":22}"}"#
    let msg = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    #expect(msg.role == "tool")
    #expect(msg.toolCallId == "call_abc")
    #expect(msg.content?.textValue == "{\"temp\":22}")
}
