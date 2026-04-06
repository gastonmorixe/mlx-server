import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

struct ChatCompletionsController {
    let service: InferenceService

    func addRoutes(to group: RouterGroup<BasicRequestContext>) {
        group.post("chat/completions", use: handle)
    }

    @Sendable
    func handle(request: Request, context: BasicRequestContext) async throws -> Response {
        let body = try await JSONDecoder().decode(
            ChatCompletionRequest.self, from: request, context: context
        )

        if let error = body.validate() {
            let data = try JSONEncoder().encode(error)
            return Response(
                status: .badRequest,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        }

        if body.stream == true {
            return try await handleStreaming(body)
        } else {
            return try await handleNonStreaming(body)
        }
    }

    private func handleNonStreaming(_ request: ChatCompletionRequest) async throws -> Response {
        let result = try await service.generate(request: request)
        let completionId = "chatcmpl-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24))"
        let model = request.model ?? service.modelName

        let response = ChatCompletionResponse(
            id: completionId,
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [
                .init(
                    index: 0,
                    message: .init(
                        content: result.toolCalls.isEmpty ? result.text : nil,
                        toolCalls: result.toolCalls.isEmpty ? nil : result.toolCalls
                    ),
                    finishReason: result.finishReason
                )
            ],
            usage: Usage(
                promptTokens: result.promptTokens,
                completionTokens: result.completionTokens,
                totalTokens: result.promptTokens + result.completionTokens,
                completionTokensDetails: result.reasoningTokens > 0
                    ? .init(reasoningTokens: result.reasoningTokens) : nil
            )
        )

        let data = try JSONEncoder().encode(response)
        let buffer = ByteBuffer(data: data)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: buffer)
        )
    }

    private func handleStreaming(_ request: ChatCompletionRequest) async throws -> Response {
        let sseStream = try await service.generateStream(request: request)

        let byteBufferStream = sseStream.map { str in
            ByteBuffer(string: str)
        }

        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .init("Cache-Control")!: "no-cache",
                .init("Connection")!: "keep-alive",
            ],
            body: .init(asyncSequence: byteBufferStream)
        )
    }

}
