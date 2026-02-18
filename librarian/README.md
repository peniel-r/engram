# Librarian Cortex - Polarion Work Item Integration

**Version 0.2.1** - Vector Search Bugfixes & Clean Demo

> **Note**: This is a demo branch. The `neuronas/` and `assets/` directories containing NDA-protected Polarion work items are excluded from the repository. The demo showcases Engram's vector search capabilities and tooling without sensitive data.

This Cortex is managed by **Engram** - a high-performance CLI tool implementing Neurona Knowledge Protocol.

This cortex contains work items fetched from Polarion and converted to valid Neuronas using the Neurona Open Specification v0.1.0, with automatic relationship extraction and LLM integration capabilities.

## Overview

**Type**: knowledge  
**Semantic Search**: Enabled (GloVe 6B)  
**LLM Integration**: Enabled  
**Language**: en  
**Purpose**: Ford DAT Core Software requirements and work items repository

The librarian cortex serves as a knowledge repository for Ford DAT Core Software requirements and work items sourced from Polarion ALM system, demonstrating Engram's capabilities for AI-assisted knowledge management.

## Directory Structure

```
librarian/
├── cortex.json              # Cortex configuration (v0.2.0 - semantic search enabled)
├── README.md                # This file
├── neuronas/                # Neurona markdown files (excluded from git - NDA)
│   ├── wi.216473.md        # Temperature Sensor Configuration (not in repo)
│   ├── wi.90087.md         # H.264 Encoding (not in repo)
│   └── ...                 # 22 work items total (not in repo)
├── .activations/            # System-generated indices (Git-ignored)
│   ├── graph.idx            # Graph adjacency list
│   ├── vectors.bin          # Vector embeddings for semantic search
│   └── cache/               # LLM cache
├── assets/                  # Source data and manifests (excluded from git - NDA)
│   ├── WI-*.json           # Raw Polarion API responses (not in repo)
│   └── batch_results_*.json # Processing manifests (not in repo)
├── fetch_wi_batch.py       # Enhanced batch work item processor ✨
├── demo_queries.ps1        # PowerShell demo script
├── llm_retrieval_example.py # LLM integration examples
├── setup_glove.sh          # GloVe embeddings setup
└── work_items_sample.txt   # Sample work items list
```

## Quick Start

### 1. Fetch Work Items from Polarion

**Fetch multiple items with relationships:**
```bash
cd librarian
python fetch_wi_batch.py --items WI-216473 WI-97530 WI-123456
```

**Fetch from file:**
```bash
# Create work_items.txt with one ID per line
python fetch_wi_batch.py --file work_items.txt
```

**Fetch from Polarion document:**
```bash
# Fetch all work items from a document
python fetch_wi_batch.py --document "DD-10031600-011_ADAS_ECU_Treerunner_SWRqmts"
```

**Disable relationship extraction (faster):**
```bash
python fetch_wi_batch.py --items WI-123456 --no-links
```

### 2. Sync Indices

```bash
# Always sync after batch import
engram sync
```

### 3. Query Work Items with Engram

```bash
# List all requirements
engram query "type:requirement" --json

# Find approved items
engram query "tag:approved"

# Complex EQL query
engram query "type:requirement AND tag:sensor"

# Text search (title + tags)
engram query --mode text "temperature sensor"

# Semantic search (requires GloVe - see setup below)
engram query --mode vector "sensor configuration"

# Hybrid search (combines text + semantic)
engram query --mode hybrid "temperature calibration"
```

### 4. Trace Dependencies

```bash
# Trace work item relationships
engram trace wi.90087 --json --depth 3

# Impact analysis
engram impact wi.216473 --json --down
```

### 5. Run Demo Scripts

**PowerShell Demo (Windows):**
```powershell
# May need to enable scripts first
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\demo_queries.ps1
```

**Python LLM Integration Examples:**
```bash
python llm_retrieval_example.py
```

## Enhanced Batch Processor (fetch_wi_batch.py v0.2.0)

The batch processor fetches multiple work items from Polarion and converts them to valid Neuronas with automatic relationship extraction.

**✨ New Features in v0.2.0:**
- ✅ **Automatic relationship extraction** - Parses Polarion links and creates Engram connections
- ✅ **Document-based retrieval** - Fetch all work items from a Polarion document
- ✅ **Enhanced metadata** - Extracts priority, assignee, author, and custom fields
- ✅ **Semantic tagging** - Auto-generates tags from content for better searchability
- ✅ **Connection type mapping** - Maps Polarion link types to Engram connection types

**Features:**
- ✅ Fetches work items from Polarion REST API
- ✅ Converts to Neurona format (Tier 2 with Tier 3 context)
- ✅ Automatic relationship extraction from Polarion links
- ✅ Document-based batch fetching
- ✅ Saves raw JSON to `assets/`
- ✅ Saves Neuronas to `neuronas/`
- ✅ Generates processing manifest
- ✅ Handles errors gracefully
- ✅ UTF-8 support for Windows console

**Output Files:**
- Raw JSON: `assets/WI-<id>.json`
- Neurona: `neuronas/wi.<id>.md`
- Manifest: `assets/batch_results_<timestamp>.json`

**Relationship Mapping:**
| Polarion Link Type | Engram Connection Type |
|--------------------|------------------------|
| parent             | parent                 |
| child              | child                  |
| blocks             | blocks                 |
| depends_on         | blocked_by             |
| verifies           | validates              |
| verified_by        | validated_by           |
| implements         | implements             |
| relates_to         | relates_to             |

## Neurona Format

Work items are converted to Tier 2/3 Neuronas with the following mapping:

### Type Mapping

| Polarion Type       | Neurona Type   |
|---------------------|----------------|
| systemRequirement   | requirement    |
| requirement         | requirement    |
| task                | task           |
| defect              | issue          |
| bug                 | issue          |
| testCase            | test_case      |
| feature             | feature        |
| story               | feature        |

### Example Neurona

```yaml
---
id: wi.216473
title: Temperature Sensor Configuration
type: requirement
tags: ["polarion", "systemRequirement", "approved", "active", "sensor", "temperature", "configuration", "fault-detection", "microcontroller"]
updated: "2021-08-18T17:39:40.385Z"
context:
  source: "polarion"
  original_id: "WI-216473"
  status: "approved"
  project: "10033794_Ford_DAT_Core_Software"
  priority: 50.0
connections: ["relates_to:wi.63850:80"]
---

Treerunner micro-controller's temperature sensor shall be configured 
for Average temperature measurement to be used by over-temperature FCCU fault.

## Metadata

- **Original ID**: WI-216473
- **Type**: systemRequirement
- **Status**: approved
- **Priority**: 50.0
- **Portal**: [WI-216473](https://polarionprod1.aptiv.com/...)
```

## Demo Scripts

### PowerShell Demo (`demo_queries.ps1`)

Interactive demonstration of Engram query capabilities with formatted output.

```powershell
# Enable script execution (if needed)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Run demo
.\demo_queries.ps1
```

**Demonstrates:**
- Filter queries by type and tags
- EQL logical operators
- Work item details with metadata
- Dependency tracing
- Status overview

### LLM Integration Example (`llm_retrieval_example.py`)

Python examples showing how LLM agents can retrieve and use Polarion work items.

```bash
python llm_retrieval_example.py
```

**Demonstrates:**
1. Query all requirements
2. Build LLM context from work items
3. Dependency impact analysis
4. Automated test coverage verification

**Example usage in LLM workflow:**
```python
from llm_retrieval_example import EngramRetriever

retriever = EngramRetriever()

# Get relevant work items for LLM context
context = retriever.build_llm_context("temperature sensor", max_items=3)

# Use in LLM prompt
prompt = f"""
You are analyzing automotive requirements.

{context}

Question: What are the temperature sensor requirements?
"""
```

## Semantic Search Setup

To enable semantic search (vector embeddings), setup GloVe embeddings:

### Linux/Mac:
```bash
bash setup_glove.sh
```

### Manual Setup:
1. Download GloVe 6B embeddings (~860MB):
   ```bash
   wget https://nlp.stanford.edu/data/glove.6B.zip
   unzip glove.6B.zip
   ```

2. Set environment variable:
   ```bash
   export ENGRAM_GLOVE_PATH="/path/to/glove.6B.100d.txt"
   ```

3. Rebuild indices:
   ```bash
   engram sync
   ```

4. Test semantic search:
   ```bash
   engram query --mode vector "sensor calibration"
   ```

## Engram Commands

```bash
# Cortex status
engram status --json

# Query requirements
engram query "type:requirement" --json

# Search by text
engram query --mode text "sensor" --json

# Show specific item
engram show wi.216473 --json

# Create connections
engram link wi.216473 --validates test.001

# Impact analysis
engram impact wi.216473 --json --up --down

# Get metrics
engram metrics --json
```

## Configuration

### Polarion Settings

Edit `fetch_wi_batch.py`:

```python
PROJECT_ID = "10033794_Ford_DAT_Core_Software"
BASE_URL = "https://polarionprod1.aptiv.com/polarion"
TOKEN = "your_pat_token"
```

## Dependencies

```bash
pip install requests
```

## Troubleshooting

### Unicode Errors on Windows

```bash
# Set console to UTF-8
chcp 65001
```

### API Authentication

- Verify PAT token is valid
- Check token expiration
- Ensure read permissions

## Learn More

- [Neurona Open Spec](../docs/NEURONA_OPEN_SPEC.md)
- [Engram AI Agents Guide](../docs/AI_AGENTS_GUIDE.md)
- [Engram Core Usage](../docs/CORE_USAGE_GUIDE.md)

---

**Version**: 0.2.0  
**Created**: 2026-02-17T14:31:15Z  
**Updated**: 2026-02-17T20:25:00Z  
**Features**: Auto-relationship extraction, semantic search, LLM integration, document retrieval

