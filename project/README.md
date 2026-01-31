# project

This Cortex is managed by **Engram** - a high-performance CLI tool implementing Neurona Knowledge Protocol.

## Overview

**Type**: alm

**Language**: en

## Directory Structure

```
project/
├── cortex.json              # Cortex configuration and DNA
├── README.md                # This file
├── neuronas/                # Your Neuronas (knowledge nodes)
├── .activations/            # System-generated indices (Git-ignored)
│   ├── graph.idx            # Graph adjacency list
│   ├── vectors.bin          # Vector embeddings (if semantic search enabled)
│   └── cache/               # Cached computations
└── assets/                  # Static files (diagrams, PDFs, etc.)
```

## Getting Started

### Create a Neurona

```bash
cd project
engram new concept "My First Note"
```

### View a Neurona

```bash
engram show my.first.note
```

### List All Neuronas

```bash
engram status
```

## Cortex Type Details

This is an **ALM (Application Lifecycle Management)** Cortex, optimized for:
- Requirements management
- Test case tracking
- Issue and defect management
- Traceability and impact analysis

### ALM-Specific Commands

```bash
# Create a requirement
engram new requirement "User Authentication"

# Create a test case
engram new test_case "Auth Test" --validates req.auth.oauth2

# Create an issue
engram new issue "Login bug" --priority 1

# Trace dependencies
engram trace req.auth.oauth2

# Check release readiness
engram release-status
```

## Learn More

- [Neurona Spec](https://github.com/modelcontextprotocol/)
- [Engram Documentation](https://github.com/yourusername/Engram)

---

Created with Engram on 2026-01-31T16:23:16Z

