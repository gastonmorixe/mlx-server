# Usage guide

## Starting the server

```bash
cd mlx-server
./build.sh release

.build/release/MLXServerCLI \
  --model-path ~/.lmstudio/models/mlx-community/gemma-4-31b-it-4bit \
  --port 8080
```

Generation defaults (temperature, top_p, top_k) are loaded from the model's `generation_config.json`. CLI flags override them if specified.

## Basic request

```bash
curl http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [{"role": "user", "content": "What is 2+2?"}],
    "max_tokens": 50
  }'
```

## Streaming

```bash
curl -N http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [{"role": "user", "content": "Tell me a joke"}],
    "stream": true,
    "stream_options": {"include_usage": true}
  }'
```

When `stream_options.include_usage` is true, the final SSE chunk includes token counts. When omitted or false, no usage is sent in streaming mode (per OpenAI spec).

## Reasoning mode

Control thinking per-request with `reasoning_effort`:

```bash
# Enable reasoning
curl http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [{"role": "user", "content": "Solve: 23 * 47"}],
    "reasoning_effort": "high",
    "max_tokens": 300
  }'
```

The model thinks internally before responding. Thinking content is stripped from the output. The response includes `completion_tokens_details.reasoning_tokens` so you can see how many tokens were spent on reasoning.

Values: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`. The `--enable-thinking` CLI flag sets the default when `reasoning_effort` is not sent in the request.

## Tool calling

```bash
curl http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [{"role": "user", "content": "What is the weather in Tokyo?"}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get current weather",
        "parameters": {
          "type": "object",
          "properties": {
            "city": {"type": "string"}
          },
          "required": ["city"]
        }
      }
    }],
    "max_tokens": 200
  }'
```

When the model calls a tool, the response has `finish_reason: "tool_calls"` and `message.tool_calls` with the function name and arguments. Send the result back as a `tool` message to continue the conversation.

### Multi-turn with tool results

```bash
curl http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [
      {"role": "user", "content": "What is the weather in Tokyo?"},
      {
        "role": "assistant",
        "content": null,
        "tool_calls": [{
          "id": "call_abc123",
          "type": "function",
          "function": {"name": "get_weather", "arguments": "{\"city\":\"Tokyo\"}"}
        }]
      },
      {
        "role": "tool",
        "tool_call_id": "call_abc123",
        "content": "{\"temp\": 22, \"condition\": \"sunny\"}"
      }
    ],
    "max_tokens": 100
  }'
```

## Message roles

| Role | Purpose |
|------|---------|
| `system` | System prompt, sets model behavior |
| `developer` | Alias for system (used by OpenAI reasoning models) |
| `user` | User message |
| `assistant` | Model's previous response (include `tool_calls` for tool call history) |
| `tool` | Tool result (must include `tool_call_id`) |

## Multimodal content

User messages can mix text and images using content parts:

```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "Describe this image"},
    {"type": "image_url", "image_url": {"url": "https://example.com/photo.jpg"}}
  ]
}
```

Note: image URL fetching is not yet implemented. The field is parsed for forward compatibility.

## Reproducible generation

Use `seed` for deterministic output:

```bash
curl http://localhost:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [{"role": "user", "content": "Pick a number"}],
    "seed": 42,
    "max_tokens": 10
  }'
```

## JSON output

Request JSON output with `response_format`:

```json
{
  "messages": [{"role": "user", "content": "List 3 colors as JSON"}],
  "response_format": {"type": "json_object"}
}
```

This is passed as a hint to the model's chat template. Compliance depends on model support.
