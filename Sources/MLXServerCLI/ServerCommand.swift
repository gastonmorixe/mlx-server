import ArgumentParser
import Foundation
import Logging
import MLX
import MLXLLM
import MLXLMCommon
import MLXServer
import MLXVLM

@main
struct ServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mlx-server",
        abstract: "OpenAI-compatible inference server powered by MLX Swift"
    )

    @Option(name: .long, help: "Path to local model directory")
    var modelPath: String

    @Option(name: .long, help: "Model name reported in API responses (default: derived from path)")
    var modelName: String?

    @Option(name: .long, help: "Host to bind to")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "Port to bind to")
    var port: Int = 8080

    @Option(name: .long, help: "Default max tokens for generation")
    var maxTokens: Int = 4096

    @Option(name: .long, help: "Default temperature (overrides model's generation_config.json)")
    var temperature: Float?

    @Option(name: .long, help: "Default top-p (overrides model's generation_config.json)")
    var topP: Float?

    @Option(name: .long, help: "Default top-k (overrides model's generation_config.json)")
    var topK: Int?

    @Flag(name: .long, help: "Enable thinking/reasoning mode (model must support it)")
    var enableThinking: Bool = false

    @Option(name: .long, help: "GPU cache limit in MB")
    var cacheSize: Int?

    @Option(name: .long, help: "GPU memory limit in MB")
    var memorySize: Int?

    mutating func run() async throws {
        var logger = Logger(label: "mlx-server")
        logger.logLevel = .info

        // Configure Metal memory limits
        if let cacheSize {
            MLX.Memory.cacheLimit = cacheSize * 1024 * 1024
            logger.info("GPU cache limit: \(cacheSize) MB")
        }
        if let memorySize {
            MLX.Memory.memoryLimit = memorySize * 1024 * 1024
            logger.info("GPU memory limit: \(memorySize) MB")
        }

        // Resolve model path (expand ~)
        let expandedPath = NSString(string: modelPath).expandingTildeInPath
        let modelURL = URL(filePath: expandedPath)

        // Derive model name from path if not provided
        let resolvedName = modelName ?? {
            let components = modelURL.pathComponents
            let count = components.count
            if count >= 2 {
                return "\(components[count - 2])/\(components[count - 1])"
            }
            return modelURL.lastPathComponent
        }()

        // Load generation defaults from model config, CLI flags override
        let genConfig = ModelGenerationConfig.load(from: modelURL)
        let resolvedTemp = temperature ?? genConfig.temperature ?? 0.6
        let resolvedTopP = topP ?? genConfig.topP ?? 1.0
        let resolvedTopK = topK ?? genConfig.topK ?? 0

        logger.info("Loading model: \(resolvedName)")
        logger.info("Model path: \(expandedPath)")
        logger.info("Generation defaults: temperature=\(resolvedTemp), top_p=\(resolvedTopP), top_k=\(resolvedTopK), max_tokens=\(maxTokens)")
        logger.info("Thinking default: \(enableThinking ? "enabled" : "disabled") (per-request via reasoning_effort)")

        let container = try await loadModelContainer(
            from: modelURL,
            using: TokenizersLoader()
        )

        let isVLM = await container.isVLM
        logger.info("Model loaded (VLM: \(isVLM))")

        let service = InferenceService(
            modelContainer: container,
            modelName: resolvedName,
            enableThinking: enableThinking,
            defaultMaxTokens: maxTokens,
            defaultTemperature: resolvedTemp,
            defaultTopP: resolvedTopP,
            defaultTopK: resolvedTopK
        )

        logger.info("Starting server at http://\(host):\(port)")
        logger.info("Endpoints:")
        logger.info("  POST /v1/chat/completions")
        logger.info("  GET  /v1/models")
        logger.info("  GET  /health")

        let app = buildApp(
            host: host,
            port: port,
            service: service,
            logger: logger
        )

        try await app.runService()
    }
}
