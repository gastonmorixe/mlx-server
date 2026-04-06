// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "mlx-server",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "MLXServer",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-tokenizers"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/MLXServer"
        ),
        .executableTarget(
            name: "MLXServerCLI",
            dependencies: [
                "MLXServer",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-tokenizers"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MLXServerCLI"
        ),
        .testTarget(
            name: "MLXServerTests",
            dependencies: [
                "MLXServer",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/MLXServerTests"
        ),
    ]
)

package.dependencies = [
    .package(path: ".."),
    .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers", from: "0.2.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
]
