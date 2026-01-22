# Product Specification: Engram CLI

**Project**: Engram
**Version**: 0.1.0 (Draft)  
**Date**: 2026-01-21  
**Language**: Zig  
**Scope**: Command Line Interface & Core Engine  

---

## 1. Executive Summary
**Engram** is a high-performance, cross-platform CLI tool designed to implement the *Neurona Knowledge Protocol*. It treats documentation, requirements, issues, and code artifacts as nodes in a unified, biomimetic graph.

Unlike traditional wikis or issue trackers, Engram operates locally on the filesystem, uses explicitly typed relationships ("Synapses"), and targets **sub-10ms** traversal times for complex graph queries. It bridges the gap between a **Zettelkasten notebook** and a **Software Lifecycle Management (ALM)** system.

---

## 2. Technical Architecture

### 2.1 Technology Stack
*   **Language**: **Zig** (chosen for manual memory control, zero-overhead, and cross-compilation).
*   **Storage**: Plain Text (Markdown + YAML Frontmatter) for the "Soma" (Source of Truth).
*   **Indexing**: Custom binary adjacency lists and vector embeddings for "Memory" (Ephemeral).
*   **Distribution**: Single binary with no external dependencies (Static linking).

### 2.2 Cross-Platform Strategy
*   Native builds for **Windows (x86_64)**, **Linux**, and **macOS (Apple Silicon/Intel)** via Zig's build system.
*   Zero system-level dependencies (no Python runtime, no JVM, no Node.js required).

---

## 3. Key Use Cases

### 3.1 The "Engineering V-Model" (ALM)
Engram enables full traceability across the software development lifecycle without leaving the terminal.
*   **Requirements**: Define atoms of logic (`type: requirement`).
*   **Tests**: Link validation specs to requirements (`type: test_case`).
*   **Code**: Reference actual source files as "Artifact Neuronas".
*   **Query**: "Show me all requirements impacted by `auth.py` that lack a passing test."

### 3.2 Decentralized Issue Tracking
*   **Offline-First**: Issues are files (`type: issue`). Git manages the history/sync.
*   **Context-Aware**: An issue is linked directly to the code file or spec it relates to.
*   **State Enforcement**: The CLI enforces state transitions (e.g., `open` $\to$ `in_progress`) based on valid graph movements.

### 3.3 Knowledge Graph & Data Structures
*   **Native Trees**: Supports strict hierarchies (Binary Trees, DOMs) via typed edges (`parent`/`child`, `left`/`right`).
*   **Neural Search**: Hybrid search combining keyword matching (BM25) and vector similarity (Embeddings).

---

## 4. CLI Interface Design

The CLI uses a `noun-verb` or `verb-object` syntax optimized for speed.

### 4.1 Core Commands
| Command | Arguments | Description |
| :--- | :--- | :--- |
| `engram init` | `[name]` | Initialize a new Cortex in the current directory. |
| `engram new` | `<title>` `--type` | Create a new Neurona. Opens default `$EDITOR`. |
| `engram link` | `<src_id> <tgt_id>` | Create a Synapse (connection) between nodes. |
| `engram show` | `<id>` | Render a Neurona and its immediate connections. |
| `engram sync` | | Rebuild the ephemeral indices (`.activations/`). |

### 4.2 Engineering Commands
| Command | Description |
| :--- | :--- |
| `engram trace <id> --up/--down` | Visualizes the dependency tree (e.g., Requirement $\to$ Test). |
| `engram status` | Lists open issues (`type: issue`) sorted by graph weight/priority. |
| `engram run <id>` | (Tier 3) Executes the context of an artifact (e.g., runs the test script). |

### 4.3 Query Language (EQL)
A simple query interface for the graph.
```bash
# Find all high-priority bugs blocking the release
engram query "type:issue AND tag:p1 AND link(type:blocked_by, target:release.v1)"
```

---

## 5. Performance Constraints (The "10ms Rule")

To ensure the tool feels "instant" and can be used in CI/CD pipelines:

1.  **Cold Start**: The CLI must parse `cortex.json` and be ready to accept input in **< 50ms**.
2.  **Graph Traversal**: Finding adjacent nodes (depth 1) must be **O(1)**.
3.  **Pathfinding**: Finding the shortest path between two nodes (depth 5) must be **< 10ms**.
4.  **Index Build**: Rebuilding the index for 10,000 files must take **< 1 second** (leveraging Zig's multi-threading).

---

## 6. Data Schema (Tier 2 Mapping)

To support the discussed domains, Engram will ship with standard "Flavors" embedded in the binary:

### 6.1 `type: issue`
*   **Context**: `assignee`, `status` (open, closed), `priority` (1-5).
*   **Mandatory Links**: None.
*   **Optional Links**: `blocked_by`, `relates_to`.

### 6.2 `type: requirement`
*   **Context**: `verification_method` (test, analysis, inspection).
*   **Mandatory Links**: `parent` (Feature).

### 6.3 `type: binary_node`
*   **Context**: `value` (payload).
*   **Allowed Links**: `left`, `right` (Strict cardinality of 1).

---

## 7. Roadmap

### Phase 1: The Soma (MVP)
*   [ ] CLI Skeleton in Zig.
*   [ ] Markdown Parsing (Frontmatter extraction).
*   [ ] `init`, `new`, `link`, `show` commands.
*   [ ] Basic Indexer (JSON dump).

### Phase 2: The Axon (Connectivity)
*   [ ] Graph Traversal Engine (BFS/DFS implementation).
*   [ ] `trace` command for Requirements/Tests.
*   [ ] Issue Tracking logic (State filters).

### Phase 3: The Cortex (Intelligence)
*   [ ] Vector Embeddings (via C-interop with llama.cpp or similar).
*   [ ] Natural Language Querying.
*   [ ] `engram run` for executing code artifacts.