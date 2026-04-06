import Testing

@testable import MLXServer

@Test func stripThinking_noThinkingContent() {
    let (text, tokens) = InferenceService.stripThinkingWithCount(
        "Hello world", totalTokens: 5, thinkingActive: true)
    #expect(text == "Hello world")
    #expect(tokens == 0)
}

@Test func stripThinking_singleBlock() {
    let input = "<|channel>thought\nLet me think about this...<channel|>The answer is 42."
    let (text, tokens) = InferenceService.stripThinkingWithCount(
        input, totalTokens: 20, thinkingActive: true)
    #expect(text == "The answer is 42.")
    #expect(tokens > 0)
    #expect(tokens < 20)
}

@Test func stripThinking_unclosedBlock() {
    let input = "<|channel>thought\nStill thinking..."
    let (text, tokens) = InferenceService.stripThinkingWithCount(
        input, totalTokens: 10, thinkingActive: true)
    #expect(text == "")
    #expect(tokens == 10)
}

@Test func stripThinking_thinkingDisabled() {
    let input = "<|channel>thought\nreasoning<channel|>answer"
    let (text, tokens) = InferenceService.stripThinkingWithCount(
        input, totalTokens: 10, thinkingActive: false)
    // When thinking is not active, text passes through with trimming only
    #expect(text == input)
    #expect(tokens == 0)
}

@Test func stripThinking_emptyInput() {
    let (text, tokens) = InferenceService.stripThinkingWithCount(
        "", totalTokens: 0, thinkingActive: true)
    #expect(text == "")
    #expect(tokens == 0)
}

@Test func estimateReasoningTokens_halfAndHalf() {
    let result = InferenceService.estimateReasoningTokens(
        thinkingChars: 50, contentChars: 50, totalTokens: 100)
    #expect(result == 50)
}

@Test func estimateReasoningTokens_allThinking() {
    let result = InferenceService.estimateReasoningTokens(
        thinkingChars: 100, contentChars: 0, totalTokens: 40)
    #expect(result == 40)
}

@Test func estimateReasoningTokens_noThinking() {
    let result = InferenceService.estimateReasoningTokens(
        thinkingChars: 0, contentChars: 100, totalTokens: 40)
    #expect(result == 0)
}

@Test func estimateReasoningTokens_zeroBoth() {
    let result = InferenceService.estimateReasoningTokens(
        thinkingChars: 0, contentChars: 0, totalTokens: 0)
    #expect(result == 0)
}
