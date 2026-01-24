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
engram query --type requirement --limit 10 --json
```

## 🧪 Development

### Running Tests
Engram maintains a comprehensive test suite with leak detection enabled.
```bash
zig build test
```

### Performance Benchmarks
```bash
zig build bench
```

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---
*Part of the Neurona Knowledge Protocol ecosystem.*
