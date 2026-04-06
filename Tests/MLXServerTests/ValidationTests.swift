import Foundation
import Testing

@testable import MLXServer

@Test func validate_validRequest() throws {
    let json = #"{"messages":[{"role":"user","content":"hi"}]}"#
    let request = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    #expect(request.validate() == nil)
}

@Test func validate_nGreaterThanOne() throws {
    let json = #"{"messages":[{"role":"user","content":"hi"}],"n":3}"#
    let request = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    let error = try #require(request.validate())
    #expect(error.error.code == "unsupported_parameter")
    #expect(error.error.message.contains("n > 1"))
}

@Test func validate_nEqualsOne() throws {
    let json = #"{"messages":[{"role":"user","content":"hi"}],"n":1}"#
    let request = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    #expect(request.validate() == nil)
}

@Test func validate_invalidReasoningEffort() throws {
    let json = #"{"messages":[{"role":"user","content":"hi"}],"reasoning_effort":"turbo"}"#
    let request = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    let error = try #require(request.validate())
    #expect(error.error.code == "invalid_parameter")
    #expect(error.error.message.contains("turbo"))
}

@Test(arguments: ["none", "minimal", "low", "medium", "high", "xhigh"])
func validate_validReasoningEffort(effort: String) throws {
    let json = #"{"messages":[{"role":"user","content":"hi"}],"reasoning_effort":"\#(effort)"}"#
    let request = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    #expect(request.validate() == nil)
}
