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
- **HTML Documentation Viewer**: On-demand markdown-to-HTML conversion with browser rendering (cross-platform).

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

### Update Neuronas
```bash
engram update test.001 --set "context.status=passing"
engram update req.001 --set "context.status=implemented"
```

### Visualize Dependencies
```bash
engram trace req.auth.user-authentication
```

### Impact Analysis
```bash
engram impact req.auth
```

### Link Code Artifacts
```bash
engram link-artifact req.auth zig --file src/auth.zig
```

### Check Status
```bash
engram status
engram status --type issue --filter "state:open AND priority:1"
```

### Release Readiness
```bash
engram release-status
engram release-status --verbose
```

### Project Metrics
```bash
engram metrics
engram metrics --last 7
```

### View Documentation
```bash
# View quick reference in terminal
engram man

# Open full manual in web browser (HTML format)
engram man --html
```

### Query Interface
```bash
# Filter mode (default) - by type, tags, connections
engram query --type issue
engram query --type issue --limit 10

# EQL Query Language
engram query "type:issue AND priority:1"
engram query "state:open AND tag:critical"

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

# Natural language queries (auto-detected)
engram query "show me all open issues"
engram query "find tests that are failing"

# JSON output (works with all modes)
engram query --mode text "authentication" --json
engram query --mode hybrid "login" --json --limit 3
engram release-status --json
engram metrics --json
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
