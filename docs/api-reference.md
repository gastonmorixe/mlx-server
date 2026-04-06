# API reference

## POST /v1/chat/completions

### Request

```json
{
  "model": "string | null",
  "messages": [
    {
      "role": "system | developer | user | assistant | tool",
      "content": "string | array | null",
      "tool_calls": [{"id": "string", "type": "function", "function": {"name": "string", "arguments": "string"}}],
      "tool_call_id": "string",
      "name": "string"
    }
  ],
  "temperature": "float | null",
  "top_p": "float | null",
  "top_k": "int | null",
  "max_tokens": "int | null (deprecated)",
  "max_completion_tokens": "int | null",
  "stream": "bool | null",
  "stream_options": {"include_usage": "bool"},
  "tools": [{"type": "function", "function": {"name": "string", "description": "string", "parameters": {}}}],
  "tool_choice": "auto | none | required | {\"type\": \"function\", \"function\": {\"name\": \"string\"}}",
  "reasoning_effort": "none | minimal | low | medium | high | xhigh",
  "seed": "int | null",
  "n": "int | null",
  "response_format": {"type": "text | json_object"},
  "frequency_penalty": "float | null",
  "presence_penalty": "float | null",
  "repetition_penalty": "float | null",
  "stop": "string | array | null",
  "user": "string | null",
  "logprobs": "bool | null",
  "top_logprobs": "int | null"
}
```

### Request fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `model` | string | server's model | Model identifier. Accepted but the server always uses its loaded model. |
| `messages` | array | required | Conversation messages. See message format below. |
| `temperature` | float | model config | Sampling temperature (0-2). |
| `top_p` | float | model config | Nucleus sampling threshold (0-1). |
| `top_k` | int | model config | Top-k sampling. 0 disables. |
| `max_tokens` | int | 4096 | Max tokens to generate. Deprecated; use `max_completion_tokens`. |
| `max_completion_tokens` | int | 4096 | Max tokens to generate (includes reasoning tokens). Takes precedence over `max_tokens`. |
| `stream` | bool | false | Enable Server-Sent Events streaming. |
| `stream_options` | object | null | `{"include_usage": true}` to get token counts on the final streaming chunk. Only used when `stream: true`. |
| `tools` | array | null | Available tool/function definitions. |
| `tool_choice` | string/object | "auto" | Controls tool calling behavior. |
| `reasoning_effort` | string | CLI default | Per-request thinking control. `"none"` disables, any other value enables. |
| `seed` | int | null | Seed for reproducible generation. |
| `n` | int | 1 | Number of completions. Only `1` is supported; values > 1 return 400. |
| `response_format` | object | null | `{"type": "json_object"}` hints JSON output. Model compliance varies. |
| `frequency_penalty` | float | null | Penalize tokens by frequency (-2 to 2). |
| `presence_penalty` | float | null | Penalize tokens by presence (-2 to 2). |
| `repetition_penalty` | float | null | Repetition penalty factor. |
| `stop` | string/array | null | Stop sequences. Parsed but not yet wired. |
| `user` | string | null | User identifier. Accepted for compatibility, not used. |
| `logprobs` | bool | null | Accepted for compatibility, not implemented. |
| `top_logprobs` | int | null | Accepted for compatibility, not implemented. |

### Message format

**System/developer message:**
```json
{"role": "system", "content": "You are a helpful assistant."}
```

**User message (text):**
```json
{"role": "user", "content": "Hello"}
```

**User message (multimodal):**
```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "What is this?"},
    {"type": "image_url", "image_url": {"url": "https://..."}}
  ]
}
```

**Assistant message:**
```json
{"role": "assistant", "content": "The answer is 42."}
```

**Assistant message with tool calls:**
```json
{
  "role": "assistant",
  "content": null,
  "tool_calls": [{
    "id": "call_abc123",
    "type": "function",
    "function": {"name": "get_weather", "arguments": "{\"city\":\"Tokyo\"}"}
  }]
}
```

**Tool result:**
```json
{
  "role": "tool",
  "tool_call_id": "call_abc123",
  "content": "{\"temp\": 22}"
}
```

### Non-streaming response

```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1700000000,
  "model": "mlx-community/gemma-4-31b-it-4bit",
  "system_fingerprint": "mlx-server-v1",
  "choices": [{
    "index": 0,
    "message": {
      "role": "assistant",
      "content": "Hello!",
      "tool_calls": null
    },
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 15,
    "completion_tokens": 3,
    "total_tokens": 18,
    "completion_tokens_details": {
      "reasoning_tokens": 0
    }
  }
}
```

`completion_tokens_details` is present only when `reasoning_tokens > 0` (i.e., when reasoning was active).

### Streaming response

Each chunk is sent as an SSE event:

```
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":1700000000,"model":"...","system_fingerprint":"mlx-server-v1","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":1700000000,"model":"...","system_fingerprint":"mlx-server-v1","choices":[{"index":0,"delta":{"content":"!"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":1700000000,"model":"...","system_fingerprint":"mlx-server-v1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":15,"completion_tokens":2,"total_tokens":17}}

data: [DONE]
```

The `usage` field appears only on the final chunk and only when `stream_options.include_usage` is `true`.

### Finish reasons

| Value | Meaning |
|-------|---------|
| `stop` | Natural end of generation (EOS token) |
| `length` | Hit max_tokens / max_completion_tokens limit |
| `tool_calls` | Model generated one or more tool calls |

### Error response

```json
{
  "error": {
    "message": "description of the error",
    "type": "invalid_request_error",
    "code": "unsupported_parameter"
  }
}
```

HTTP status codes: 400 for validation errors, 500 for internal errors.

## GET /v1/models

### Response

```json
{
  "object": "list",
  "data": [{
    "id": "mlx-community/gemma-4-31b-it-4bit",
    "object": "model",
    "created": 1700000000,
    "owned_by": "mlx-server"
  }]
}
```

## GET /health

Returns `ok` with status 200 when the server is running.
