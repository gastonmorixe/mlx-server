import Foundation
import Testing

@testable import MLXServer

@Test func convertMessages_basicUserMessage() throws {
    let json = #"[{"role":"user","content":"hello"}]"#
    let messages = try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    let result = InferenceService.convertMessages(messages)

    #expect(result.count == 1)
    #expect(result[0]["role"] as? String == "user")
    #expect(result[0]["content"] as? String == "hello")
}

@Test func convertMessages_developerMappedToSystem() throws {
    let json = #"[{"role":"developer","content":"Be concise"}]"#
    let messages = try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    let result = InferenceService.convertMessages(messages)

    #expect(result[0]["role"] as? String == "system")
    #expect(result[0]["content"] as? String == "Be concise")
}

@Test func convertMessages_systemPassesThrough() throws {
    let json = #"[{"role":"system","content":"You are helpful"}]"#
    let messages = try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    let result = InferenceService.convertMessages(messages)

    #expect(result[0]["role"] as? String == "system")
}

@Test func convertMessages_toolCallId() throws {
    let json = #"[{"role":"tool","tool_call_id":"call_123","content":"result"}]"#
    let messages = try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    let result = InferenceService.convertMessages(messages)

    #expect(result[0]["role"] as? String == "tool")
    #expect(result[0]["tool_call_id"] as? String == "call_123")
    #expect(result[0]["content"] as? String == "result")
}

@Test func convertMessages_assistantWithToolCalls() throws {
    let json = """
    [{
        "role": "assistant",
        "content": null,
        "tool_calls": [{
            "id": "call_abc",
            "type": "function",
            "function": {"name": "get_weather", "arguments": "{\\"city\\":\\"SF\\"}"}
        }]
    }]
    """
    let messages = try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    let result = InferenceService.convertMessages(messages)

    #expect(result[0]["role"] as? String == "assistant")
    let toolCalls = result[0]["tool_calls"] as? [[String: any Sendable]]
    #expect(toolCalls?.count == 1)
}

@Test func convertMessages_multiTurnConversation() throws {
    let json = """
    [
        {"role": "system", "content": "Be helpful"},
        {"role": "user", "content": "Hi"},
        {"role": "assistant", "content": "Hello!"},
        {"role": "user", "content": "Bye"}
    ]
    """
    let messages = try JSONDecoder().decode([ChatMessage].self, from: Data(json.utf8))
    let result = InferenceService.convertMessages(messages)

    #expect(result.count == 4)
    #expect(result[0]["role"] as? String == "system")
    #expect(result[1]["role"] as? String == "user")
    #expect(result[2]["role"] as? String == "assistant")
    #expect(result[3]["role"] as? String == "user")
}
