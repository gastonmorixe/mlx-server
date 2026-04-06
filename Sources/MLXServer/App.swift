import Hummingbird
import Logging

public func buildApp(
    host: String,
    port: Int,
    service: InferenceService,
    logger: Logger
) -> some ApplicationProtocol {
    let router = Router()

    let v1 = router.group("v1")
    ChatCompletionsController(service: service).addRoutes(to: v1)
    ModelsController(service: service).addRoutes(to: v1)

    // Health check
    router.get("health") { _, _ in
        "ok"
    }

    return Application(
        router: router,
        configuration: .init(
            address: .hostname(host, port: port),
            serverName: "mlx-server"
        ),
        logger: logger
    )
}
