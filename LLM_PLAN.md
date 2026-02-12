# Engram Native Intelligence Plan (The "Exocortex" Module)

**Status**: Draft
**Dependencies**: `llm_plan.md` (Completed)
**Goal**: Implement a native, Zig-based interface for LLM interaction, removing the need for external IDE extensions.

---

## 1. Vision: The Autonomous Cortex

Engram currently has "Memory" (the graph) and "Optimization" (summaries/tokens). The next step is "Reasoning".
By embedding a lightweight HTTP client and a prompt engineering engine directly into the CLI, Engram becomes a self-contained AI agent that can reason about its own data.

**Philosophy:**
- **BYO-Intelligence:** The user brings their own API Key (OpenAI, Anthropic, or Local/Ollama).
- **Privacy-First:** Context is built locally; only relevant Neuronas are sent to the inference engine.
- **Terminal-Native:** No VS Code required. Everything happens in the shell.
- **Cost-Aware:** All API interactions are tracked and reported back to the user.

---

## 2. Architecture

### 2.1 The Synaptic Bridge (`src/core/llm/bridge.zig`)
A unified interface for communicating with inference providers.

**Supported Protocols:**
- `OpenAI Compatible` (Covers OpenAI, Groq, DeepSeek, Ollama, LM Studio).
- `Anthropic` (Claude).
- `Extensible Provider System`: Trait-based design for adding new providers.

**Responsibilities:**
- Managing HTTP connections (using `std.http.Client` with connection pooling).
- Handling streaming responses (SSE with buffering).
- Rate limiting and retries with exponential backoff.
- Error handling with structured error types.
- Cost tracking (tokens in/out per request).

**Key Design Decisions:**
```zig
// Provider trait for extensibility
const Provider = struct {
    vtable: *const VTable,
    name: []const u8,
    max_tokens: u32,
};

const VTable = struct {
    complete: *const fn (*Provider, Context, Prompt) anyerror!Response,
    stream: *const fn (*Provider, Context, Prompt, StreamingCallback) anyerror!void,
    estimateCost: *const fn (*Provider, Prompt) CostEstimate,
};
```

### 2.2 The Context Manager (`src/core/llm/context.zig`)
Leverages the work done in `llm_plan.md`.

**Smart Selection:** Uses `_llm` metadata to decide whether to include the full body (high value) or just the summary (context) of a Neurona.

**Token Budgeting:** Uses `src/utils/token_counter.zig` to ensure the prompt fits the context window (e.g., 128k tokens).

**RAG Pipeline:**
1. User Query → Vector Search (`.activations/vectors.bin`).
2. Graph Traversal → Fetch connected nodes (Up/Down 1 hop).
3. Reranking → Prioritize by `weight`, recency, and semantic relevance.
4. Assembly → Construct System Prompt + Context Block.

**Context Window Strategies:**
- **Hard Cutoff:** Truncate low-relevance items.
- **Smart Summarization:** Use smaller model to summarize multiple items into one.
- **Hierarchical:** Include summaries first, drill into details if needed.

### 2.3 The Interaction Loop (`src/cli/chat.zig`)
A TUI (Terminal User Interface) or REPL for interaction.

**Mode 1: One-Shot (`engram ask`)**
- Input: CLI Argument or STDIN.
- Output: Markdown to Stdout (with streaming support).
- Example: `engram ask "Summarize the auth requirements"`
- Example: `cat bug_report.txt | engram ask "Create a requirement from this"`

**Mode 2: Interactive (`engram chat`)**
- Input: Readline loop with history.
- Output: Streaming text with typewriter effect.
- Features:
  - `/context <artifact_id>`: Add specific artifact to context
  - `/clear`: Clear conversation history
  - `/stats`: Show token usage and cost
  - `/export <file>`: Export conversation to Markdown
  - Arrow keys for history navigation
  - Multi-line input with Ctrl+Enter

### 2.4 The Conversation Manager (`src/core/llm/conversation.zig`)
Manages multi-turn conversations with context persistence.

**Responsibilities:**
- Maintains conversation state across sessions (optional persistence to disk).
- Implements sliding window for token management.
- Handles system prompt injection.
- Provides conversation summarization for long sessions.

---

## 3. Configuration (`cortex.json` extension)

The `cortex.json` schema will be updated to include an `llm` block.

```json
{
  "capabilities": {
    "llm_integration": true
  },
  "llm": {
    "provider": "openai",
    "model": "gpt-4o",
    "base_url": "https://api.openai.com/v1",
    "context_window": 128000,
    "temperature": 0.7,
    "max_tokens": 4096,
    "timeout_ms": 30000,
    "retries": 3,
    "backoff_ms": 1000,
    "stream": true,
    "system_prompt": "You are Engram, a knowledge graph assistant...",
    "embedding_model": "text-embedding-3-small",
    "embedding_dimensions": 1536
  }
}
```

**API Key Sources:**
1. Environment variable: `ENGRAM_API_KEY`
2. Secure local file: `.engram/.secrets` (file permissions: 0600)
3. Interactive prompt on first use (not stored)

**Cost Tracking:**
- Tokens in/out tracked per session and stored in `.engram/.usage.json`
- Monthly cost estimates based on provider pricing
- Warnings before expensive operations

---

## 4. Implementation Roadmap

### Phase 1: The Client (Connectivity)
- [ ] Implement Provider trait and OpenAI adapter in `bridge.zig`
- [ ] Add HTTP client with connection pooling
- [ ] Implement SSE streaming decoder
- [ ] Add `cortex.json` parsing for LLM config
- [ ] Create `engram ping-ai` command to test connection
- [ ] Implement cost tracking structures
- [ ] Add error handling with structured error types

### Phase 2: The RAG Engine (Context)
- [ ] Implement `ContextBuilder` with token budgeting
- [ ] Integrate `src/storage/vectors.zig` (if ready) or fallback to hybrid search
- [ ] Wire up `src/utils/token_counter.zig` to the builder
- [ ] Implement context window strategies (hard cutoff, smart summarization)
- [ ] Add caching layer for frequent queries
- [ ] Implement response caching to avoid redundant API calls

### Phase 3: The Interface (Chat)
- [ ] Implement `engram ask <query>` with STDIN support
- [ ] Implement `engram chat` REPL with readline
- [ ] Add streaming output with buffering
- [ ] Implement conversation state management
- [ ] Add `/context`, `/clear`, `/stats`, `/export` commands
- [ ] Add system prompts with customization

### Phase 4: The Generator (Creation)
- [ ] Implement `engram suggest <file>`: Reads a source file and proposes a Tier 2 Neurona (Requirement/Spec) via LLM
- [ ] Add function calling support (Engram commands as tools)
- [ ] Implement automated test generation from requirements
- [ ] Add refactoring suggestions

### Phase 5: Advanced Features
- [ ] Conversation persistence to `.engram/conversations/`
- [ ] Multi-provider fallback (e.g., OpenAI → Anthropic on failure)
- [ ] Local model support (Ollama with GPU acceleration)
- [ ] Batch processing for multiple queries
- [ ] Integration with CI/CD pipelines

---

## 5. Why this is better than an Extension

1. **Universal:** Works in Vim, Emacs, VS Code terminal, or CI/CD.
2. **Scriptable:** `engram ask` can be piped into other tools.
   - `engram ask "Generate release notes" > RELEASE.md`
   - `git diff HEAD~1 | engram ask "Create requirements from this diff"`
3. **Zig Performance:** Token counting and context selection happen at native speeds before touching the network.
4. **No Dependency Hell:** Ships with Engram, no npm/VS Code marketplace required.
5. **Offline-Ready:** Can work with local models (Ollama) without internet.
6. **Cost Control:** Built-in cost tracking helps manage API expenses.
7. **Privacy:** All context assembly happens locally; only what's needed is sent to the LLM.

---

## 6. Technical Considerations

### 6.1 Memory Management
- Use `ArenaAllocator` for per-request lifecycle (cleared after each LLM call).
- Use `PoolAllocator` for long-lived chat sessions.
- Never hold onto streaming buffers longer than necessary.
- Explicit cleanup of HTTP connections.

### 6.2 Error Handling Strategy
```zig
const LLMError = error{
    NetworkError,
    RateLimitExceeded,
    InvalidAPIKey,
    ContextWindowExceeded,
    Timeout,
    ProviderError,
    StreamingFailed,
} || std.mem.Allocator.Error;
```

### 6.3 Performance Optimizations
- Connection pooling for multiple requests.
- Parallel context assembly (async if Zig supports it).
- Pre-computed token counts for cached artifacts.
- Compressed HTTP requests where appropriate.

### 6.4 Testing Strategy
- Mock provider implementations for unit tests.
- Integration tests with optional real API keys.
- Property-based tests for token counting.
- Load testing for concurrent requests.

### 6.5 Security Considerations
- API keys never logged or committed to git.
- Rate limiting to prevent accidental runaway costs.
- Input sanitization for all user queries.
- TLS 1.3 enforcement for all HTTP connections.

---

## 7. Command Examples

```bash
# Test connection
engram ping-ai

# One-shot query
engram ask "What are the blocking issues for req.001?"

# Pipe input
cat src/auth/login.zig | engram ask "Generate unit tests for this file"

# Interactive chat
engram chat

# Generate artifacts
engram suggest src/api/endpoints.zig > new_requirements.md

# Export conversation
engram chat
> /context req.001
> Summarize the requirements
> /export summary.md
```

---

## 8. Future Extensions

- **Multi-Modal:** Support image inputs for visual documentation.
- **Code Execution:** Safely execute generated code in sandboxed environment.
- **Collaborative:** Multi-user sessions with shared context.
- **Plugins:** Allow custom providers and middleware.
- **Observability:** Detailed logging and metrics for production use.

