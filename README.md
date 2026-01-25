# Engram

**Engram** is a high-performance CLI tool implementing the **Neurona Knowledge Protocol**. It provides a robust foundation for managing structured knowledge graphs, specifically optimized for Application Lifecycle Management (ALM) and AI-assisted workflows.

Built with **Zig 0.15.2**, Engram offers zero-overhead performance, manual memory control, and sub-10ms graph traversal.

## 🚀 Features

- **Graph-Aware Knowledge Management**: Create and link Neuronas (knowledge nodes) with 15+ semantic connection types.
- **ALM First**: Built-in support for requirements, test cases, issues, artifacts, and features.
- **High Performance**: Sub-millisecond cold start and ultra-fast graph traversal.
- **Offline-First**: Plain-text storage using Markdown and YAML frontmatter.
- **AI-Ready**: Structured metadata and JSON output for seamless LLM integration.
- **Traceability**: Visualize dependency trees and perform impact analysis.
- **Semantic Search**: Five query modes for intelligent search:
  - **Filter Mode**: By type, tags, and connections (default)
  - **Text Mode**: BM25 full-text search with relevance scoring
  - **Vector Mode**: Cosine similarity search with embeddings
  - **Hybrid Mode**: Combined BM25 + vector fusion (0.6/0.4 weights)
  - **Activation Mode**: Neural propagation across graph connections

## 🛠️ Installation

### Prerequisites
- [Zig 0.15.2](https://ziglang.org/download/) or higher.

### Build from Source
```bash
git clone https://github.com/yourusername/Engram.git
cd Engram
zig build -Doptimize=ReleaseSafe
```
The binary will be available in `zig-out/bin/Engram`.

## 📖 Usage

### Initialize a Cortex
```bash
engram init my_project --type alm
```

### Create a Neurona
```bash
engram new requirement "User Authentication" --tag auth
engram new test_case "Login Test" --validates req.auth.user-authentication
```

### Link Neuronas
```bash
engram link req.auth.user-authentication issue.auth.001 blocks
```

### Visualize Dependencies
```bash
engram trace req.auth.user-authentication
```

### Check Status
```bash
engram status --type issue --status open
```

### Query Interface
```bash
# Filter mode (default) - by type, tags, connections
engram query
engram query --type issue --limit 10

# BM25 full-text search
engram query --mode text "authentication"
engram query --mode text "password validation" --limit 5

# Vector similarity search
engram query --mode vector "user login"
engram query --mode vector "performance" --limit 3

# Hybrid search (BM25 + vector fusion)
engram query --mode hybrid "login failure"
engram query --mode hybrid "performance" --limit 5

# Neural activation search
engram query --mode activation "login"
engram query --mode activation "critical" --limit 5

# JSON output (works with all modes)
engram query --mode text "authentication" --json
engram query --mode hybrid "login" --json --limit 3
```

## 🧪 Development

### Running Tests
Engram maintains a comprehensive test suite with leak detection enabled.
```bash
# Run all tests
zig build test

# Run integration tests (Linux/Git Bash)
bash test_query_integration.sh

# Run integration tests (Windows)
test_query_integration.bat
```

See [QUERY_INTEGRATION_TESTS.md](QUERY_INTEGRATION_TESTS.md) for complete integration test documentation.

### Performance Benchmarks
```bash
zig build bench
```

## 📄 License
This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

## 📚 Documentation
- [Master Plan](docs/PLAN.md) - Complete project roadmap and architecture
- [Query Integration Tests](QUERY_INTEGRATION_TESTS.md) - Comprehensive query mode testing

---
*Part of the Neurona Knowledge Protocol ecosystem.*
