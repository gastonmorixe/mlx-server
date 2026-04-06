import Foundation
import Testing

@testable import MLXServer

private let testDefaults = InferenceService.Defaults(
    maxTokens: 4096, temperature: 1.0, topP: 0.95, topK: 64
)

@Test func resolveThinking_effortHigh() {
    let result = InferenceService.resolveThinking(
        reasoningEffort: "high", defaultEnabled: false)
    #expect(result == true)
}

@Test func resolveThinking_effortNone() {
    let result = InferenceService.resolveThinking(
        reasoningEffort: "none", defaultEnabled: true)
    #expect(result == false)
}

@Test func resolveThinking_effortNil_defaultEnabled() {
    let result = InferenceService.resolveThinking(
        reasoningEffort: nil, defaultEnabled: true)
    #expect(result == true)
}

@Test func resolveThinking_effortNil_defaultDisabled() {
    let result = InferenceService.resolveThinking(
        reasoningEffort: nil, defaultEnabled: false)
    #expect(result == false)
}

@Test func resolveThinking_effortMinimal() {
    let result = InferenceService.resolveThinking(
        reasoningEffort: "minimal", defaultEnabled: false)
    #expect(result == true)
}

@Test func resolveAdditionalContext_thinkingEnabled() {
    let ctx = InferenceService.resolveAdditionalContext(
        reasoningEffort: "high", thinkingActive: true, responseFormat: nil)
    #expect(ctx?["enable_thinking"] as? Bool == true)
    #expect(ctx?["reasoning_effort"] as? String == "high")
}

@Test func resolveAdditionalContext_thinkingDisabled() {
    let ctx = InferenceService.resolveAdditionalContext(
        reasoningEffort: "none", thinkingActive: false, responseFormat: nil)
    #expect(ctx?["enable_thinking"] == nil)
    #expect(ctx?["reasoning_effort"] as? String == "none")
}

@Test func resolveAdditionalContext_jsonFormat() {
    let fmt = ResponseFormat(type: "json_object")
    let ctx = InferenceService.resolveAdditionalContext(
        reasoningEffort: nil, thinkingActive: false, responseFormat: fmt)
    let rf = ctx?["response_format"] as? [String: String]
    #expect(rf?["type"] == "json_object")
}

@Test func resolveAdditionalContext_nilWhenEmpty() {
    let ctx = InferenceService.resolveAdditionalContext(
        reasoningEffort: nil, thinkingActive: false, responseFormat: nil)
    #expect(ctx == nil)
}

@Test func buildParameters_usesDefaults() throws {
    let json = #"{"messages":[{"role":"user","content":"hi"}]}"#
    let req = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    let params = InferenceService.buildParameters(from: req, defaults: testDefaults)
    #expect(params.temperature == 1.0)
    #expect(params.topP == 0.95)
    #expect(params.topK == 64)
    #expect(params.maxTokens == 4096)
}

@Test func buildParameters_requestOverridesDefaults() throws {
    let json = #"{"messages":[{"role":"user","content":"hi"}],"temperature":0.3,"top_p":0.5,"top_k":10,"max_tokens":100}"#
    let req = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    let params = InferenceService.buildParameters(from: req, defaults: testDefaults)
    #expect(params.temperature == 0.3)
    #expect(params.topP == 0.5)
    #expect(params.topK == 10)
    #expect(params.maxTokens == 100)
}

@Test func buildParameters_maxCompletionTokensPrecedence() throws {
    let json = #"{"messages":[{"role":"user","content":"hi"}],"max_tokens":100,"max_completion_tokens":200}"#
    let req = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    let params = InferenceService.buildParameters(from: req, defaults: testDefaults)
    #expect(params.maxTokens == 200)
}

@Test func buildParameters_maxCompletionTokensAlone() throws {
    let json = #"{"messages":[{"role":"user","content":"hi"}],"max_completion_tokens":150}"#
    let req = try JSONDecoder().decode(ChatCompletionRequest.self, from: Data(json.utf8))
    let params = InferenceService.buildParameters(from: req, defaults: testDefaults)
    #expect(params.maxTokens == 150)
}
