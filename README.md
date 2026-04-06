# mlx-server

OpenAI-compatible inference server for Apple Silicon, powered by [mlx-swift-lm](https://github.com/osaurus-ai/mlx-swift-lm).

Runs LLMs and VLMs locally via MLX and exposes them through a standard `/v1/chat/completions` API. Works with any client that speaks the OpenAI protocol.

## Quick start

```bash
cd mlx-server
./build.sh release

.build/release/MLXServerCLI \
  --model-path ~/.lmstudio/models/mlx-community/gemma-4-31b-it-4bit
```

```bash
curl http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": true
  }'
```

## Features

- **OpenAI-compatible API** -- POST /v1/chat/completions, GET /v1/models
- **Streaming SSE** with optional usage reporting via `stream_options`
- **Tool/function calling** -- pass tools, get tool_calls back
- **Reasoning mode** -- per-request via `reasoning_effort` (none/low/medium/high/xhigh)
- **VLM support** -- auto-detected at load time
- **Generation config** -- reads model's `generation_config.json` for defaults (temperature, top_p, top_k)
- **Seed** for reproducible generation

## CLI options

```
--model-path <path>       Local model directory (required)
--model-name <name>       Model name in API responses (default: from path)
--host <addr>             Bind address (default: 127.0.0.1)
--port <port>             Bind port (default: 8080)
--max-tokens <n>          Default max tokens (default: 4096)
--temperature <f>         Override model's default temperature
--top-p <f>               Override model's default top-p
--top-k <n>               Override model's default top-k
--enable-thinking         Enable reasoning by default (clients can override per-request)
--cache-size <mb>         GPU cache limit in MB
--memory-size <mb>        GPU memory limit in MB
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | /v1/chat/completions | Chat completions (streaming + non-streaming) |
| GET | /v1/models | List loaded model |
| GET | /health | Health check |

## Documentation

- [Usage guide](docs/how-to-use.md) -- examples, message roles, tool calling
- [API reference](docs/api-reference.md) -- complete request/response schemas

## Build requirements

- macOS 15+
- Xcode 16+ / Swift 6.1
- Apple Silicon (M1 or later)

The build script compiles Metal shaders automatically. If you get "Failed to load the default metallib" at runtime, delete `.build/*/mlx.metallib` and rebuild.

## Architecture

mlx-server is a standalone Swift Package that depends on mlx-swift-lm (local path `..`). It uses:

- **Hummingbird** for HTTP serving
- **ArgumentParser** for CLI
- **swift-tokenizers** for tokenizer loading
- **MLXLLM / MLXVLM / MLXLMCommon** for model inference
