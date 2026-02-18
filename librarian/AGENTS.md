# AI Agent Rules for Librarian Cortex

**Version 1.0** | **Last Updated: February 17, 2026**

---

## Overview

This file contains mandatory rules for AI agents interacting with the Librarian cortex. These rules ensure proper use of Engram CLI commands to retrieve information from the knowledge base instead of accessing raw files directly.

---

## Critical Rules

### Rule 1: NEVER Read Raw Neurona Files Directly

**FORBIDDEN:**
- ❌ Reading `.md` files from `neuronas/` directory
- ❌ Reading `.json` files from `assets/` directory
- ❌ Using `cat`, `grep`, `find`, or file system tools to access neurona content
- ❌ Parsing neurona markdown manually

**REASON:** Raw files may not exist in demo branches or may contain outdated cached data. Always query through Engram's synchronized indices.

### Rule 2: ALWAYS Use Engram CLI for Data Retrieval

**REQUIRED:**
When users ask for information about work items, requirements, or any Polarion objects:

1. **Use `engram query`** with appropriate search mode
2. **Use `engram show`** for detailed views of specific items
3. **Use `engram trace`** for dependency analysis
4. **Use `engram status`** for cortex overview

**REASON:** Engram maintains synchronized indices (graph, vector, text) and provides consistent JSON output for programmatic access.

### Rule 3: Select Appropriate Search Mode

Based on the user's query type, choose the correct search mode:

| Query Type | Search Mode | Command Example |
|------------|-------------|-----------------|
| **Exact filters** (type, status, tags) | `filter` (default) | `engram query "type:requirement AND tag:sensor"` |
| **Keyword search** | `text` | `engram query --mode text "temperature calibration"` |
| **Semantic/concept search** | `vector` | `engram query --mode vector "sensor calibration"` |
| **Combined approach** | `hybrid` | `engram query --mode hybrid "fault detection"` |
| **Specific item details** | N/A (use show) | `engram show wi.216473 --json` |
| **Relationship tracing** | N/A (use trace) | `engram trace wi.90087 --depth 2 --json` |

### Rule 4: Always Use JSON Output for Parsing

**REQUIRED:**
Always append `--json` flag when parsing results programmatically:

```bash
# Good - machine parseable
engram query "type:requirement" --json

# Bad - human-readable only
engram query "type:requirement"
```

**REASON:** JSON output is stable, structured, and easier to parse programmatically.

### Rule 5: Workflow for Answering User Questions

When a user asks about work items or requirements:

```
1. Understand Query
   ├─ Identify: What information is needed?
   ├─ Classify: Filter, text, semantic, or specific item?
   └─ Plan: Which Engram command(s) to use?

2. Execute Engram Command
   ├─ Use appropriate search mode
   ├─ Add --json flag for parsing
   └─ Set limits if needed (--limit N)

3. Parse Results
   ├─ Extract relevant fields (id, title, type, tags, etc.)
   ├─ Format for human readability
   └─ Cite sources (neurona IDs)

4. Provide Answer
   ├─ Summarize findings
   ├─ Include neurona IDs for reference
   └─ Suggest follow-up queries if helpful
```

---

## Command Reference

### Query Commands

```bash
# Filter query (EQL syntax)
engram query "type:requirement AND tag:sensor" --json

# Text search (keywords)
engram query --mode text "temperature calibration" --json

# Semantic search (concepts)
engram query --mode vector "sensor configuration" --json

# Hybrid search (combined)
engram query --mode hybrid "fault detection" --json

# Limit results
engram query "type:requirement" --limit 5 --json
```

### Show Command

```bash
# Show specific item with full details
engram show wi.216473 --json

# Show multiple items
engram show wi.216473 wi.90087 --json
```

### Trace Command

```bash
# Trace dependencies (downstream)
engram trace wi.90087 --json

# Trace with depth limit
engram trace wi.90087 --depth 2 --json

# Trace upstream and downstream
engram trace wi.90087 --up --down --json
```

### Status Command

```bash
# Cortex overview
engram status --json
```

---

## Example Queries

### Example 1: Find Requirements About Sensors

**User asks:** "What requirements are related to sensors?"

**Agent workflow:**
```bash
# Step 1: Use filter query with tag
engram query "type:requirement AND tag:sensor" --json

# Step 2: Parse JSON output
# Step 3: Format results for user
```

**Expected response format:**
```
Found 3 requirements related to sensors:

1. **wi.216473** - Temperature Sensor Configuration
   - Type: requirement
   - Tags: sensor, temperature, configuration
   - Status: approved

2. **wi.97530** - Temperature Sensor Configuration
   - Type: requirement  
   - Tags: sensor, temperature, configuration
   - Status: approved

Use `engram show wi.216473` for more details.
```

### Example 2: Semantic Search for Concepts

**User asks:** "Find items related to video streaming"

**Agent workflow:**
```bash
# Step 1: Use vector search for semantic matching
engram query --mode vector "video streaming" --json

# Step 2: Parse results with similarity scores
# Step 3: Format results for user
```

**Expected response format:**
```
Found 3 items semantically related to "video streaming":

1. **wi.96811** - Video Streaming Activation (similarity: 0.810)
   - Type: requirement
   - Description: H.264 video stream activation requirements

2. **wi.96812** - Video Streaming Termination (similarity: 0.797)
   - Type: requirement
   - Description: Video stream termination procedures

3. **wi.90087** - H.264 Encoding (similarity: 0.720)
   - Type: requirement
   - Description: H.264 encoding parameters

Use `engram trace wi.96811` to see dependencies.
```

### Example 3: Get Specific Work Item Details

**User asks:** "Show me details for WI-216473"

**Agent workflow:**
```bash
# Step 1: Convert to neurona ID format (wi.216473)
# Step 2: Use show command
engram show wi.216473 --json

# Step 3: Extract and format key fields
```

**Expected response format:**
```
**wi.216473 - Temperature Sensor Configuration**

- **Type**: requirement
- **Status**: approved
- **Tags**: sensor, temperature, configuration, polarion
- **Updated**: 2024-01-15T10:30:00Z

**Description:**
Configuration requirements for temperature sensor calibration...

**Connections:**
- blocks: wi.63850
- relates_to: wi.97530

**Source**: Polarion (Original ID: WI-216473)
```

### Example 4: Trace Dependencies

**User asks:** "What depends on WI-90087?"

**Agent workflow:**
```bash
# Step 1: Use trace command with --down flag
engram trace wi.90087 --down --json

# Step 2: Parse dependency tree
# Step 3: Format as hierarchical list
```

**Expected response format:**
```
Dependency tree for wi.90087 (H.264 Encoding):

wi.90087 (H.264 Encoding)
├─ blocks → wi.33529
├─ blocks → wi.99171
├─ blocks → wi.33527
├─ blocks → wi.33444
├─ blocks → wi.33555
└─ blocks → wi.99172

Total downstream dependencies: 6 items

Use `engram show wi.33529` for details on any item.
```

---

## Error Handling

### If Engram Command Fails

```bash
# Check cortex status
engram status --json

# If indices are out of sync, rebuild
engram sync
```

### If No Results Found

1. Try different search modes (vector vs text vs filter)
2. Broaden search terms
3. Check available tags: `engram query "type:*" --json | jq -r '.[] | .tags[]' | sort -u`
4. Verify cortex status: `engram status --json`

### If Neurona ID Unknown

Users may provide Polarion IDs (WI-216473) instead of neurona IDs (wi.216473):

```bash
# Search by original ID in context
engram query "type:* AND context.original_id:WI-216473" --json

# Or use text search
engram query --mode text "WI-216473" --json
```

---

## Testing Protocol

Before responding to users, agents should:

1. ✅ Verify Engram is available: `engram status --json`
2. ✅ Check cortex has data: Look for `total_neuronas > 0`
3. ✅ Test query works: Run the command before formatting response
4. ✅ Parse JSON successfully: Validate structure before extraction
5. ✅ Handle empty results gracefully: Provide helpful suggestions

---

## Prohibited Actions

**NEVER:**
- ❌ Read neurona `.md` files directly from `neuronas/` directory
- ❌ Parse raw Polarion JSON from `assets/` directory  
- ❌ Bypass Engram indices by accessing files manually
- ❌ Cache results outside Engram's index (indices may be rebuilt)
- ❌ Assume file structure (demo branches exclude sensitive data)

**ALWAYS:**
- ✅ Use `engram query` for searching
- ✅ Use `engram show` for details
- ✅ Use `engram trace` for dependencies
- ✅ Add `--json` flag for parsing
- ✅ Cite neurona IDs in responses

---

## Summary

**Golden Rule:** When users ask about work items, requirements, or any Polarion data → **Use Engram CLI commands, never read files directly.**

This ensures:
- ✅ Consistent behavior across demo/production environments
- ✅ Up-to-date results from synchronized indices
- ✅ Proper handling of missing files in demo branches
- ✅ Efficient query performance (indices are optimized)
- ✅ Correct dependency resolution through graph indices

---

**For questions or issues, refer to the main AGENTS.md in the repository root.**
