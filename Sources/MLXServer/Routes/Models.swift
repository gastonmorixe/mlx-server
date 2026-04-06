import Foundation
import Hummingbird
import NIOCore

struct ModelsController {
    let service: InferenceService

    func addRoutes(to group: RouterGroup<BasicRequestContext>) {
        group.get("models", use: handle)
    }

    @Sendable
    func handle(request: Request, context: BasicRequestContext) async throws -> Response {
        let response = ModelsResponse(
            data: [
                .init(
                    id: service.modelName,
                    created: service.createdTimestamp
                )
            ]
        )

        let data = try JSONEncoder().encode(response)
        let buffer = ByteBuffer(data: data)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: buffer)
        )
    }
}
