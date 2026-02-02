# Engram AI Agents Guide

**Version 0.2.0** | **Last Updated: February 2, 2026**

---

## Overview

Engram provides AI agents and automation systems with programmatic access to Application Lifecycle Management through structured JSON outputs and LLM-optimized data structures.

### Key Features for AI Agents

- **Complete JSON API** - All commands output parseable JSON with full data
- **LLM-optimized metadata** - Token-efficient `_llm` fields for quick consumption
- **Semantic search** - Vector embeddings understand meaning beyond keywords
- **Programmatic updates** - Full CRUD operations via `--set` flags
- **Dependency tracking** - Trace relationships and impact analysis

---

## Quick Start for AI Agents

### Essential Workflow

```bash
# 1. Initialize project
engram init my_project --type alm

# 2. Get project overview
engram status --json

# 3. Query for items
engram query --type requirement --state draft --json

# 4. Update items programmatically
engram update req.auth --set "context.status=approved" \
  --set "context.assignee=alice" \
  --set "_llm_t=OAuth Login"
```

---

## LLM Metadata Structure

### _llm Fields

Every Neurona can include `_llm` metadata for AI consumption:

```json
{
  "_llm": {
    "t": "OAuth 2.0 Login",           // Short title (token efficient)
    "d": 3,                            // Density (1-4 scale)
    "k": ["oauth", "login", "auth"],  // Keywords for filtering
    "c": 850,                          // Token count
    "strategy": "summary"              // Content strategy
  }
}
```

### Setting _llm Metadata

```bash
# Set individual fields
engram update req.auth --set "_llm_t=OAuth Login"
engram update req.auth --set "_llm_d=3"
engram update req.auth --set "_llm_k=oauth,login,auth"

# Update multiple fields
engram update req.auth --set "_llm_t=Short Title" --set "_llm_d=2" --set "_llm_c=500"
```

---

## Common AI Agent Patterns

### Pattern 1: Requirements Analysis

```bash
# Get high-complexity requirements
engram query --type requirement --json | \
  jq '.[] | select(._llm.d >= 3)'

# Find requirements without tests
engram query --type requirement --state approved --json | \
  jq '.[] | select(.connections.validates | length == 0)'

# Get project metrics
engram metrics --json
```

### Pattern 2: Programmatic Updates

```bash
# Update multiple fields
engram update req.auth \
  --set "context.status=implemented" \
  --set "context.assignee=alice" \
  --set "_llm_t=OAuth 2.0" \
  --set content="Implementation completed with PKCE support"

# Set content body
engram update req.api --set content="## API Description\n\nDetailed specification..."
```

### Pattern 3: Impact Analysis

```bash
# Analyze code changes
git diff HEAD~1 --name-only | while read file; do
  engram impact "$file" --json
done

# Get affected tests
engram impact src/auth.zig --json | \
  jq '.[] | select(.type == "test_case")'
```

### Pattern 4: Release Readiness

```bash
# Check release status
engram release-status --json

# Get blockers
engram release-status --json | jq '.blocking_items[]'

# Generate status report
engram status --json | jq 'group_by(.type) | map({type: .[0].type, count: length})'
```

---

## Essential Commands for AI Agents

### status - Project Overview
```bash
engram status --json
# Returns: [{id, title, type, status, priority, tags}, ...]
```

### query - Search and Filter
```bash
# Filter by type and state
engram query --type requirement --state draft --json

# Filter by multiple criteria
engram query --type issue --priority 1 --json

# Natural language search
engram query "authentication problems" --json
```

### show - Get Item Details
```bash
engram show req.auth.oauth2 --json
# Returns: {id, title, type, body, context, _llm, connections, ...}
```

### update - Programmatic Updates
```bash
# Single field
engram update req.auth --set "context.status=implemented"

# Multiple fields
engram update req.auth \
  --set "context.assignee=alice" \
  --set "_llm_t=OAuth 2.0" \
  --set content="Updated description..."

# Content updates
engram update req.api --set content="## API Spec\n\nDetailed description..."

# LLM metadata
engram update req.auth --set "_llm_d=3" --set "_llm_k=oauth,login,auth"
```

### trace - Dependency Analysis
```bash
engram trace req.auth.oauth2 --json --depth 2
# Returns dependencies and relationships
```

### impact - Change Impact Analysis
```bash
engram impact src/auth.zig --json
# Returns affected items and recommendations
```

### metrics - Project Statistics
```bash
engram metrics --json
# Returns: {total_neuronas, by_type, completion_rate, test_coverage}
```

**Response:**
```json
{
  "cortex": "my_project",
  "type": "alm",
  "total": 45,
  "by_type": {
    "requirement": 24,
    "test_case": 18,
    "issue": 3
  },
  "results": [
    {
      "id": "req.auth.login",
      "title": "Support User Login",
      "type": "requirement",
      "updated": "2026-01-21T10:30:00Z",
      "_llm": {
        "t": "User Login",
        "d": 2,
        "k": ["login", "auth", "user"],
        "c": 245
      }
    }
  ]
}
```

#### 2. query - Search and Filter

```bash
# Filter mode
engram query --type requirement --status draft --json

# EQL syntax
engram query "type:issue AND priority:1" --json

# Semantic search
engram query --mode vector "authentication problems" --json

# Natural language
engram query "what's blocking the release?" --json
```

**EQL Syntax:**
```
type:requirement AND state:approved
type:test_case AND (status:passing OR status:failing)
link(validates, req.auth.oauth2)
tag:security AND priority:1
title:contains:oauth
```

#### 3. show - View Neurona Details

```bash
engram show req.auth.oauth2 --json
```

**Response:**
```json
{
  "id": "req.auth.oauth2",
  "title": "Support OAuth 2.0 Authentication",
  "type": "requirement",
  "tags": ["authentication", "security"],
  "connections": {
    "validates": [
      {
        "id": "test.auth.oauth2.001",
        "weight": 100
      }
    ],
    "blocked_by": [
      {
        "id": "issue.db.timeout",
        "weight": 100
      }
    ]
  },
  "context": {
    "status": "implemented",
    "priority": 1,
    "assignee": "alice"
  },
  "content": "Implement OAuth 2.0 with PKCE...",
  "_llm": {
    "t": "OAuth 2.0",
    "d": 3,
    "k": ["oauth", "auth", "login"],
    "c": 850,
    "strategy": "summary",
    "summary": "OAuth 2.0 authentication with PKCE support"
  },
  "updated": "2026-01-21"
}
```

#### 4. trace - Dependency Analysis

```bash
engram trace req.auth.oauth2 --json --depth 3
```

**Response:**
```json
{
  "root": "req.auth.oauth2",
  "direction": "down",
  "depth": 3,
  "results": [
    {
      "id": "test.auth.oauth2.001",
      "relationship": "validates",
      "weight": 100,
      "level": 1,
      "context": {
        "status": "passing"
      }
    },
    {
      "id": "issue.db.timeout",
      "relationship": "blocked_by",
      "weight": 100,
      "level": 1,
      "context": {
        "status": "open",
        "priority": 1
      }
    }
  ]
}
```

#### 5. impact - Change Impact Analysis

```bash
engram impact req.auth.oauth2 --json
```

**Response:**
```json
{
  "root": "req.auth.oauth2",
  "affected_items": [
    {
      "id": "test.auth.oauth2.001",
      "type": "test_case",
      "impact_level": "high"
    },
    {
      "id": "feature.authentication",
      "type": "feature",
      "impact_level": "medium"
    }
  ],
  "recommendations": [
    "Run 3 tests before deploying",
    "Notify assignees of dependent items"
  ]
}
```

#### 6. release-status - Release Readiness

```bash
engram release-status --json
```

**Response:**
```json
{
  "ready": false,
  "readiness_percentage": 67,
  "blocking_items": [
    {
      "id": "issue.db.timeout",
      "priority": 1,
      "blocks": ["req.auth.login", "req.auth.oauth2"]
    }
  ],
  "requirements": {
    "total": 24,
    "implemented": 16,
    "blocked": 3,
    "draft": 5
  },
  "tests": {
    "passing": 42,
    "failing": 2,
    "not_run": 2
  }
}
```

#### 7. metrics - Project Statistics

```bash
engram metrics --json
```

**Response:**
```json
{
  "total_neuronas": 45,
  "by_type": {
    "requirement": 24,
    "test_case": 18,
    "issue": 3
  },
  "completion_rate": 0.67,
  "test_coverage": 0.94,
  "created_this_week": 5,
  "updated_this_week": 12
}
```

---

## AI Agent Workflows

### Workflow 1: Automated Code Review

```bash
#!/bin/bash
# AI Agent: Automated Code Review

# 1. Get changed files
CHANGED_FILES=$(git diff HEAD~1 --name-only)

# 2. For each changed file, analyze impact
for file in $CHANGED_FILES; do
  echo "Analyzing impact of $file..."
  
  # Get affected requirements
  AFFECTED=$(engram impact "$file" --json --up | jq -r '.affected_items[] | .id')
  
  # Get affected tests
  TESTS=$(engram impact "$file" --json --down | jq -r '.affected_items[] | select(.type == "test_case") | .id')
  
  # AI analysis
  echo "$AFFECTED" | ai-analyze --impact-type requirement
  echo "$TESTS" | ai-analyze --impact-type test
  
  # Generate recommendations
  echo "File: $file" > review_report.md
  echo "Affected Requirements:" >> review_report.md
  echo "$AFFECTED" >> review_report.md
  echo "Tests to Run:" >> review_report.md
  echo "$TESTS" >> review_report.md
done

# 3. Suggest tests to run
echo "Suggested tests to run:"
engram impact "$CHANGED_FILES" --json --down | \
  jq -r '.affected_items[] | select(.type == "test_case") | .id'
```

### Workflow 2: Continuous Release Monitoring

```bash
#!/bin/bash
# AI Agent: Continuous Release Monitoring

while true; do
  # Get release status
  STATUS=$(engram release-status --json)
  
  READY=$(echo $STATUS | jq '.ready')
  PERCENTAGE=$(echo $STATUS | jq '.readiness_percentage')
  
  if [ "$READY" = "true" ]; then
    echo "✅ Release ready! Readiness: $PERCENTAGE%"
    
    # Generate release notes
    engram query "type:requirement AND state:implemented" --json | \
      ai-generate-release-notes > release_notes.md
    
    # Notify team
    ai-notify --channel "#releases" --message "Release ready!"
    
    break
  else
    echo "⚠️  Not ready yet. Readiness: $PERCENTAGE%"
    
    # Get blockers
    BLOCKERS=$(echo $STATUS | jq -r '.blocking_items[] | .id')
    
    # Analyze blockers with AI
    echo "$BLOCKERS" | ai-analyze --prioritize-by business-value
    
    # Wait before checking again
    sleep 300
  fi
done
```

### Workflow 3: Automated Test Generation

```bash
#!/bin/bash
# AI Agent: Automated Test Generation

# Get requirements without tests
REQUIREMENTS=$(engram query \
  "type:requirement AND state:approved AND NOT link(validates, type:test_case)" \
  --json)

# For each requirement, generate tests
echo "$REQUIREMENTS" | jq -c '.results[]' | while read req; do
  REQ_ID=$(echo $req | jq -r '.id')
  REQ_TITLE=$(echo $req | jq -r '.title')
  REQ_CONTENT=$(echo $req | jq -r '.content')
  
  echo "Generating tests for $REQ_ID..."
  
  # AI generates tests
  TESTS=$(echo "$req" | ai-generate-tests --framework pytest --min-coverage 80%)
  
  # Create tests in Engram
  echo "$TESTS" | jq -r '.[] | 
    "engram new test_case \"\(.title)\" --validates '$REQ_ID' --framework pytest"' | \
    bash
  
  echo "✓ Generated tests for $REQ_TITLE"
done

# Verify test coverage
COVERAGE=$(engram metrics --json | jq '.test_coverage')
echo "Final test coverage: $COVERAGE"
```

### Workflow 4: Intelligent Bug Triage

```bash
#!/bin/bash
# AI Agent: Intelligent Bug Triage

# Get open issues
ISSUES=$(engram query "type:issue AND state:open" --json)

# Analyze each issue
echo "$ISSUES" | jq -c '.results[]' | while read issue; do
  ISSUE_ID=$(echo $issue | jq -r '.id')
  ISSUE_TITLE=$(echo $issue | jq -r '.title')
  
  echo "Triaging $ISSUE_ID: $ISSUE_TITLE..."
  
  # AI analyzes severity
  SEVERITY=$(echo "$issue" | ai-analyze --severity --business-impact)
  
  # AI suggests assignee based on skills
  ASSIGNEE=$(echo "$issue" | ai-suggest-assignee --skills-required)
  
  # Update issue
  engram update $ISSUE_ID \
    --set "context.severity=$SEVERITY" \
    --set "context.assignee=$ASSIGNEE"
  
  # AI suggests similar issues for deduplication
  SIMILAR=$(echo "$issue" | ai-find-similar --threshold 0.8)
  if [ ! -z "$SIMILAR" ]; then
    echo "⚠️  Similar issue found: $SIMILAR"
  fi
  
  echo "✓ Triage complete for $ISSUE_ID"
done

# Generate triage report
engram query "type:issue AND state:open" --json | \
  ai-generate-triage-report > triage_report.md
```

### Workflow 5: CI/CD Pipeline Integration

```bash
#!/bin/bash
# AI Agent: CI/CD Pipeline Integration

# Before build: Check if release-ready
BEFORE_BUILD=$(engram release-status --json | jq '.ready')
if [ "$BEFORE_BUILD" != "true" ]; then
  echo "❌ Release not ready. Blocking deployment."
  exit 1
fi

# Run build
npm run build

# If build fails, analyze impact
if [ $? -ne 0 ]; then
  echo "Build failed. Analyzing impact..."
  
  # Get changed files
  CHANGED=$(git diff HEAD~1 --name-only)
  
  # Analyze impact
  for file in $CHANGED; do
    IMPACT=$(engram impact "$file" --json --down)
    
    # Create issues for broken tests
    echo "$IMPACT" | jq -r '.affected_items[] | select(.type == "test_case" and .status == "failing") | .id' | \
      while read test_id; do
        echo "Creating issue for failing test: $test_id"
        engram new issue "Test $test_id failing after build" \
          --blocks $(engram show $test_id --json | jq -r '.connections.validates[].id') \
          --priority 2
      done
  done
  
  exit 1
fi

# After build: Update status
engram metrics --json | jq '.test_coverage' > coverage.json
ai-update-dashboard --coverage coverage.json

echo "✅ Build successful. Deployment ready."
```

---

## Search Modes

### Filter Mode - Fast Structured Queries
```bash
engram query --type requirement --state draft --json
engram query --type issue --priority 1 --json
```

### Text Mode - Keyword Search
```bash
engram query --mode text "authentication timeout" --json
engram query --mode text '"OAuth 2.0"' --json
```

### Vector Mode - Semantic Understanding
```bash
engram query --mode vector "user login problems" --json
# Understands related concepts: signin, authentication, etc.
```

### Hybrid Mode - Best Results
```bash
engram query --mode hybrid "login failure" --json
# Combines keywords + semantic search
```

---

## Query Syntax (EQL)

### Basic Filters
```bash
type:requirement
state:implemented
priority:1
tag:security
```

### Logical Operations
```bash
type:requirement AND state:approved
(type:issue OR type:bug) AND priority:1
type:requirement AND NOT state:implemented
```

### Examples
```bash
# High-priority open issues
engram query "type:issue AND priority:1 AND state:open" --json

# Requirements without tests
engram query "type:requirement AND NOT link(validates, type:test_case)" --json

# Security requirements
engram query "type:requirement AND tag:security" --json
```

---

## State Transitions

### Requirements
- draft → approved → implemented
- Can transition backwards (implemented → approved)

### Tests  
- not_run → running → passing/failing
- Can transition between passing/failing

### Issues
- open → in_progress → resolved → closed
- Can reopen from resolved → open

**Note:** State validation enforces valid transitions. Use force flag to bypass for initial setup.

---

## Best Practices

### 1. Always Use --json Flag
```bash
engram status --json        # Parseable output
engram show req.auth --json  # Complete data
```

### 2. Cache Expensive Operations
```bash
# Cache status for 5 minutes
if [ ! -f cache.json ] || [ $(find cache.json -mmin +5) ]; then
  engram status --json > cache.json
fi
```

### 3. Use Batch Updates
```bash
# Multiple fields in one command
engram update req.auth \
  --set "context.status=implemented" \
  --set "_llm_d=3" \
  --set content="Updated description"
```

### 4. Error Handling
```bash
# Check item exists before operations
if engram show req.auth --json >/dev/null 2>&1; then
  # Item exists, proceed
else
  echo "Item not found"
fi
```

### 5. Use Semantic Search
```bash
# Understand meaning beyond keywords
engram query --mode vector "user login issues" --json
```

---

## Integration Examples

### Python Agent
```python
import json, subprocess

def run_engram(cmd):
    return json.loads(subprocess.run(f"engram {cmd} --json", 
                              shell=True, capture_output=True, text=True).stdout)

# Get status and update items
status = run_engram("status")
for item in status:
    if item.get('priority') == 1:
        run_engram(f"update {item['id']} --set context.priority=1")
```

### JavaScript Agent
```javascript
const { execSync } = require('child_process');

function runEngram(cmd) {
    return JSON.parse(execSync(`engram ${cmd} --json`, { encoding: 'utf-8' }));
}

// Find high-priority items
const issues = runEngram('query --type issue --priority 1');
console.log('P1 Issues:', issues.length);
```

---

## Summary

### Core Commands for AI Agents

```bash
engram status --json           # Project overview
engram query --json            # Search and filter  
engram show <id> --json       # Get details
engram update <id> --set ...  # Programmatic updates
engram trace <id> --json       # Dependencies
engram impact <file> --json    # Change impact
```

### Key Features

- ✅ **Complete JSON API** - All data accessible programmatically
- ✅ **LLM metadata** - Token-efficient `_llm` fields  
- ✅ **Programmatic updates** - `--set content`, `--set context.*`, `--set _llm.*`
- ✅ **Semantic search** - Vector embeddings understand meaning
- ✅ **Dependency tracking** - Impact analysis and tracing

### Best Practices

1. **Always use `--json`** for parseable output
2. **Use batch updates** - Multiple `--set` flags in one command
3. **Leverage `_llm` metadata** - Optimized for AI consumption
4. **Cache expensive operations** - Status, queries, metrics
5. **Handle errors gracefully** - Check existence before operations

Engram provides complete programmatic access for AI agents and automation systems.

---

*For complete documentation, see the Engram manual.*