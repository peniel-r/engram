# The Neurona System Specification v0.1.0

**Status**: Draft  
**Date**: 2026-01-19  
**License**: CC-BY-4.0  

*A Neurona is knowledge. A Cortex is a library.*

---

## Table of Contents

1.  [Introduction](#introduction)
2.  [Terminology](#terminology)
3.  [Philosophy](#philosophy)
4.  [Architecture](#architecture)
5.  [File Structure](#file-structure)
6.  [The Neural Activation Engine](#the-neural-activation-engine)
7.  [Neurona Specification](#neurona-specification)
8.  [URI Scheme](#uri-scheme)
9.  [Compliance & Constraints](#compliance--constraints)

---

## Introduction

The Neurona System is a **biomimetic knowledge management standard**. It models documentation not as a static file tree, but as a neural network where concepts (Neuronas) connect via weighted relationships (Synapses).

**The System is a facilitator, not a gatekeeper.**

This specification is designed to support two extremes simultaneously:
1.  **The Analog Layer**: Simple notes usable in a physical notebook or plain text editor.
2.  **The Machine Layer**: High-performance, AI-ready knowledge graphs for complex software agents.

### Version 0.1.0 Scope
This initial release establishes the core file structure, the tiered metadata standard, and the definition of the Neural Activation algorithm.

---

## Terminology

| Term | Definition | Biological Analogy |
| :--- | :--- | :--- |
| **Neurona** | The atomic unit of knowledge. A single document containing one concept. | Neuron / Cell Body |
| **Cortex** | A collection of Neuronas organized around a domain or purpose. | Brain Region / Cortex |
| **Synapse** | A connection between Neuronas defined in metadata. | Synapse / Axon |
| **Activation** | The process of searching and traversing the graph based on a query. | Firing Potential |
| **Soma** | The directory containing the raw Neurona files (`neuronas/`). | Cell Body (content holder) |
| **Memory** | The directory containing system-generated indices (`.activations/`). | Synaptic Cleft (signal space) |
| **DNA** | The configuration file defining the Cortex (`cortex.json`). | Genetic Code |

---

## Philosophy

### The Neurona-First Principle
> **Write one Neurona. Connect it. Let the network emerge.**

A single well-written Neurona with strong connections is more valuable than a thousand unlinked documents.

### Core Principles

1.  **Neurona-Centric** — The smallest unit is the most important.
2.  **Complexity is Opt-In**: A Tier 1 Neurona is a valid Tier 3 Neurona. Higher tiers only add metadata; they never invalidate lower tiers.
3.  **Medium-Agnostic**: The system works in Markdown, JSON, or a physical paper notebook.
4.  **Performance Critical**: Sub-10ms traversal across thousands of Neuronas via pre-computed indices.
5.  **Graph-Native**: Relationships are explicit data structures, not implicit folder hierarchies.
6.  **Machine-Queryable** — Structured metadata for agents (when digital).
7.  **Universal Compatibility**: From Zettelkasten notes to State Machines and Code Artifacts.

---

## Architecture

The specification uses a **Three-Tier Architecture** to balance simplicity with capability.

### Tier 1: Essential (The Atomic Layer)
**Goal**: Usable by hand. No software required.
*   **Fields**: `id`, `title`, `tags`, `links`.
*   **Use Case**: Zettelkasten, physical notebooks, brainstorming.

### Tier 2: Standard (The Semantic Layer)
**Goal**: Graph structure and categorization.
*   **Fields**: `type` (Flavor), `connections` (Structured links), `language`.
*   **Use Case**: Documentation sites, knowledge graphs, search optimization.

### Tier 3: Advanced (The Machine Layer)
**Goal**: AI reasoning and high-performance automation.
*   **Fields**: `_llm` (Token optimization), `hash` (Integrity), `context` (Extensions).
*   **Use Case**: Coding agents, state machine execution, semantic search.

### General Purpose Flavors
To support diverse use cases, Tier 2 introduces the `type` field, which changes the interpretation of the Neurona:

*   **`concept`**: Default. Generic knowledge, notes.
*   **`reference`**: API docs, definitions, facts.
*   **`artifact`**: Code snippets, scripts, tools.
*   **`state_machine`**: A node in a state graph (requires `context` extensions).
*   **`lesson`**: Educational content (implies `prerequisites` are locks).

---

## File Structure

A Cortex is a directory containing four main subdirectories.

### The Cortical Layout

```text
my_cortex/                      # Root: The Cortex
│
├── cortex.json                 # THE DNA: Identity & Capabilities
├── README.md                   # Human readable overview
│
├── neuronas/                   # THE SOMA: User-created Markdown files
│   ├── logic.modal.md
│   ├── math.set.md
│   └── 20260119.md
│
├── .activations/               # THE MEMORY: System-generated indices (Ephemeral)
│   ├── graph.idx               # Adjacency list (O(1) traversal)
│   ├── vectors.bin             # Embeddings (Semantic search)
│   └── cache/                  # Computed LLM summaries / Activation states
│
└── assets/                     # THE MATTER: Static Binary Files
    ├── diagrams/
    └── pdfs/
```

### cortex.json (The DNA)

The configuration file for the Cortex.

```json
{
  "id": "my_cortex",
  "name": "My Personal Knowledge Base",
  "version": "1.0.0",
  "spec_version": "0.1.0",
  "capabilities": {
    "type": "zettelkasten",        // Flavor of the whole cortex
    "semantic_search": true,       // Enables .activations/vectors.bin
    "llm_integration": true,       // Enables .activations/cache/
    "default_language": "en"
  },
  "indices": {
    "strategy": "lazy",            // [lazy, eager, on_save]
    "embedding_model": "all-MiniLM-L6-v2"
  }
}
```

### .activations/ (The Memory)

This directory stores the pre-computed indices required for high-performance traversal. It is **ephemeral** and should be ignored by version control (Git).

*   **`graph.idx`**: A serialized adjacency list mapping `Neurona_ID -> [Targets, Weights]`.
*   **`vectors.bin`**: A vector index (HNSW/FAISS) for semantic matching.
*   **`cache/`**: Stored derived data (e.g., LLM summaries) to avoid recomputation.

---

## The Neural Activation Engine

Search in the Neurona System is not text matching; it is **Neural Activation**.

### The Algorithm

The process consists of three stages: **Stimulus**, **Propagation**, and **Response**.

#### 1. Stimulus (The Spark)
Input: User query or Agent intent.
*   **Text Match**: Query `.activations/graph.idx` (inverted index) for keyword matches.
*   **Vector Match**: Query `.activations/vectors.bin` for semantic similarity (Tier 3 capability).

*Result:* An initial `Active_Set` of Neuronas with an initial score (0.0 to 1.0).

#### 2. Propagation (The Signal)
The signal travels through Synapses (links).
*   For every active Neurona, inspect its connections in `graph.idx`.
*   **Decay**: Signal strength decays as it passes through links based on **Tier 3 Weights**.
    *   Formula: `Incoming_Signal = Current_Signal * (Link_Weight / 100)`
    *   If no weight exists (Tier 1/2 link), default to `0.5`.
*   **Summation**: If a Neurona receives signals from multiple sources, sum their strengths (capped at 1.0).
*   **Threshold**: Stop propagation when signal strength drops below `0.2`.

#### 3. Response (The Firing)
Output: A ranked list of Neuronas.
1.  Filter out Neuronas with score < 0.1 (Noise).
2.  Sort remaining Neuronas by Score (Descending).
3.  Retrieve full content from `neuronas/` only for the top N results (Lazy Loading).

---

## Neurona Specification

A Neurona is a Markdown file with YAML Frontmatter.

### Tier 1: Essential Fields

**Validation Rule**: If you can't write it by hand in 10 seconds, it doesn't belong in Tier 1.

```yaml
---
id: "py.async.basics"           # Unique ID (Dot notation or UID)
title: "Async Basics"           # Human readable
tags: [python, async]           # Search index
links:                          # Simple connections
  - "py.async.advanced"
---
```

### Tier 2: Standard Fields

Adds semantics and "Flavors".

```yaml
---
# TIER 1 FIELDS...
id: "py.async.basics"
title: "Async Basics"
tags: [python, async]
links: ["py.async.advanced"]

# TIER 2 FIELDS...
type: concept                   # Flavor: [concept, reference, artifact, state_machine]

# Structured Connections (Replaces 'links' if present)
connections:
  prerequisites:                # Hard dependency
    - id: "py.basics"
      weight: 90                # 0-100 (Quantized)
  next:                        # Suggestion
    - id: "py.async.tasks"
      weight: 70
  related:                     # Bidirectional
    - id: "py.threads"
      type: contrast           # [similar, contrast, complement]

updated: "2026-01-19"
language: "en"                  # IETF Tag
---
```

### Tier 3: Advanced Fields

Machine optimization and Extensions.

```yaml
---
# TIER 1 & 2 FIELDS...

# TIER 3 FIELDS...

# Integrity
hash: "sha256:abc123..."         # Content addressable ID

# LLM Optimization (Token Efficiency)
_llm:
  t: "Async HTTP"                # Short Title
  d: 3                          # Density/Difficulty (1-4)
  k: [aiohttp, fetch]           # Top keywords
  c: 850                        # Token count of body
  strategy: summary             # [full, summary, hierarchical]

# Extensions (Open Schema)
# This allows 'General Purpose' usage (e.g. State Machines)
context:
  # If type=state_machine
  triggers: ["on_request", "on_timeout"]
  entry_action: "init_session"
  
  # If type=artifact
  runtime: python
  safe_to_exec: true
---
```

### Example: State Machine Neurona

Demonstrating the General Purpose capability using the `state_machine` flavor.

```yaml
---
id: "sm.auth.logged_in"
title: "Logged In State"
type: state_machine

connections:
  next:
    - id: "sm.auth.logged_out"
      trigger: "logout"
      weight: 100

context:
  entry_action: "restore_session_tokens"
  exit_action: "clear_user_context"
  allowed_roles: ["user", "admin"]
---
```

---

## URI Scheme

To ensure interoperability between tools (CLI, GUI, Web), the Neurona System defines a standard URI scheme.

**Format:**
`neurona://<cortex-id>/<neurona-id>`

**Examples:**
*   `neurona://my_cortex/20260119`
*   `neurona://python_docs/py.async.basics`

**Resolution:**
1.  Locate the Cortex directory mapped to `<cortex-id>`.
2.  Look up `<neurona-id>` in the `.activations/graph.idx`.
3.  Retrieve the file path from the index and load the Neurona.

---

## Compliance & Constraints

### Backward Compatibility
*   **Tier 1 Compliance**: A file containing only Tier 1 fields MUST be accepted by any Tier 3 parser.
*   **Virtual Defaults**: If Tier 2/3 fields are missing, parsers MUST assume safe defaults (e.g., `type: concept`, `weight: 50`).

### Performance Constraints
*   **Cold Start**: Loading a Cortex (parsing `cortex.json`) must be < 200ms.
*   **Traversal**: Traversing 3 hops in the graph must be < 10ms (using `.activations/graph.idx`).
*   **Search**: Full text search + Neural Activation must be < 50ms for 10,000 Neuronas.

### Security
*   **Untrusted Inputs**: All external Cortex content is treated as untrusted.
*   **Execution**: Code execution is strictly opt-in via the `context` extension and requires explicit user approval (sandboxed).
*   **Tamper Detection**: Tier 3 `hash` fields allow validation of content integrity.

### Git Workflow (Recommended)
To keep the repository clean, `.gitignore` should exclude the ephemeral memory:

```text
# Ignore System Memory
.activations/

# Ignore OS metadata
.DS_Store
Thumbs.db
```

---

## Changelog

### v0.1.0 (2026-01-19)
*   Initial Draft.
*   Definition of Neurona, Cortex, and Soma/Memory terminology.
*   Establishment of the Three-Tier Architecture.
*   Specification of the Neural Activation Algorithm.
*   Introduction of General Purpose "Flavors" (State Machine, Artifact).
