# Engram AI Agents Guide

**Version 0.1.0** | **Last Updated: January 31, 2026**

---

## Overview

This guide is specifically designed for **AI Agents and LLM-powered systems** to integrate with Engram. Engram is an Application Lifecycle Management (ALM) tool that provides structured data, optimized metadata, and AI-friendly APIs for seamless automation.

### Why Engram for AI Agents?

Engram is built from the ground up for AI integration with:

- **Structured JSON outputs** - Every command returns parseable JSON
- **LLM-optimized metadata** - Token-efficient data structures
- **Semantic search** - Vector embeddings for understanding meaning
- **Intelligent caching** - LLM response caching to avoid redundant API calls
- **Natural language queries** - Parse plain English queries programmatically

---

## Quick Start for AI Agents

### Basic AI Agent Workflow

```bash
# 1. Initialize an ALM project
engram init my_project --type alm

# 2. Get project structure as JSON
engram status --json > project_structure.json

# 3. Query for specific items
engram query "type:requirement AND state:draft" --json > draft_requirements.json

# 4. Analyze and make decisions
# (AI processes JSON and determines actions)

# 5. Execute actions based on analysis
engram update req.auth --set "context.status=approved"
```

---

## LLM-Optimized Data Structures

### Neurona Metadata Schema

Every Neurona contains `_llm` metadata optimized for AI consumption:

```json
{
  "_llm": {
    "t": "OAuth 2.0 Login",           // Short title (token efficient)
    "d": 3,                            // Density/difficulty (1-4 scale)
    "k": ["oauth", "login", "auth"],  // Top keywords for quick filtering
    "c": 850,                          // Token count
    "strategy": "summary"              // Consumption strategy
  }
}
```

### Token Optimization Strategies

**Full Strategy** - Complete Neurona content:
```json
{
  "_llm": {
    "strategy": "full"
  }
}
```

**Summary Strategy** - Pre-generated summary (token-efficient):
```json
{
  "_llm": {
    "strategy": "summary",
    "summary": "Implement OAuth 2.0 authentication with token refresh and user session management."
  }
}
```

**Hierarchical Strategy** - Drill-down on demand:
```json
{
  "_llm": {
    "strategy": "hierarchical",
    "summary": "Authentication system with OAuth 2.0 support",
    "sections": ["User Registration", "Login", "Token Management", "Session Handling"]
  }
}
```

### LLM Response Caching

Engram automatically caches LLM responses:

```bash
# Cache location
.activations/cache/

# Automatic invalidation when content changes
# Reduces API calls and improves performance
```

---

## AI Agent Integration Patterns

### Pattern 1: Automated Requirements Analysis

```bash
# Get all draft requirements
engram query "type:requirement AND state:draft" --json | \
  jq '.results[] | select(._llm.d >= 3)' | \
  ai-analyze --complexity-risks

# Get requirements without tests
engram query "type:requirement AND state:approved AND NOT link(validates, type:test_case)" --json | \
  ai-suggest-tests

# Identify blocked requirements
engram query "type:requirement AND state:blocked" --json | \
  ai-impact-analysis
```

### Pattern 2: Smart Test Generation

```bash
# Analyze a requirement and generate tests
engram show req.auth.oauth2 --json | \
  ai-generate-tests --framework pytest --coverage 90% > tests_generated.json

# Create tests from JSON
cat tests_generated.json | \
  jq -r '.[] | "engram new test_case \"\(.title)\" --validates \(.validates)"' | \
  bash
```

### Pattern 3: Release Prediction

```bash
# Get release status
engram release-status --json > release_status.json

# AI predicts release date
cat release_status.json | \
  ai-predict-date --historical-data > predicted_release.json

# Get detailed metrics
engram metrics --json | \
  ai-generate-velocity-report
```

### Pattern 4: Impact Analysis Automation

```bash
# Analyze code changes
git diff HEAD~1 --name-only | \
  while read file; do
    engram impact "$file" --json --down
  done | \
  jq -s 'flatten | unique' | \
  ai-affected-tests

# Automated test selection for CI/CD
engram impact src/auth/login.zig --json --down | \
  jq -r '.[] | select(.type == "test_case") | .id' | \
  xargs -I {} engram show {} --json
```

### Pattern 5: Natural Language Processing

```bash
# Parse natural language queries
engram query "show me all P1 issues blocking authentication" --json

# Get structured results
{
  "results": [
    {
      "id": "issue.db.timeout",
      "type": "issue",
      "priority": 1,
      "blocks": ["req.auth.login", "req.auth.oauth"]
    }
  ]
}
```

---

## Command Reference for AI Agents

### Core Commands with JSON Output

#### 1. status - List Project Artifacts

```bash
engram status --json
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

## Search Modes for AI Agents

### 1. Filter Mode - Structured Queries

```bash
# Precise filtering
engram query --type requirement --state draft --json

# Combine filters
engram query --type issue --priority 1 --state open --json
```

### 2. Text Mode - Keyword Search (BM25)

```bash
# Full-text search with ranking
engram query --mode text "authentication timeout" --json

# Phrase search
engram query --mode text '"OAuth 2.0 implementation"' --json
```

### 3. Vector Mode - Semantic Search

```bash
# Find semantically similar items
engram query --mode vector "user sign in problems" --json

# Understands related concepts
engram query --mode vector "performance issues" --json
# Returns: "slow database queries", "high memory usage", etc.
```

### 4. Hybrid Mode - Combined Search

```bash
# Best general search
engram query --mode hybrid "login failure" --json

# Combines keyword matching + semantic understanding
```

### 5. Activation Mode - Neural Propagation

```bash
# Follow connections through the graph
engram query --mode activation "critical bug" --json

# Explores related items through connections
```

---

## EQL (Engram Query Language) Reference

### Basic Syntax

```
type:requirement
state:implemented
priority:1
tag:security
```

### Logical Operators

```
type:requirement AND state:approved
(type:issue OR type:bug) AND priority:1
type:requirement AND NOT link(validates, type:test_case)
```

### Comparison Operators

```
priority:>=2
priority:<=3
priority!=1
```

### Content Matching

```
title:contains:oauth
content:contains:authentication
```

### Connection Queries

```
link(validates, req.auth.oauth2)
link(blocks, type:requirement)
```

### Complex Examples

```bash
# Find all high-priority open issues
engram query "type:issue AND priority:1 AND state:open" --json

# Find requirements without tests
engram query "type:requirement AND NOT link(validates, type:test_case)" --json

# Find tests that are failing
engram query "type:test_case AND state:failing" --json

# Find items linked to a specific requirement
engram query "link(validates, req.auth.oauth2)" --json

# Find security-related requirements
engram query "type:requirement AND tag:security" --json
```

---

## State Transitions

### Issues
```json
{
  "states": ["open", "in_progress", "resolved", "closed"],
  "valid_transitions": {
    "open": ["in_progress", "resolved"],
    "in_progress": ["resolved", "open"],
    "resolved": ["closed", "open"],
    "closed": ["open"]
  }
}
```

### Tests
```json
{
  "states": ["not_run", "running", "passing", "failing"],
  "valid_transitions": {
    "not_run": ["running"],
    "running": ["passing", "failing", "not_run"],
    "passing": ["running", "failing"],
    "failing": ["running", "passing"]
  }
}
```

### Requirements
```json
{
  "states": ["draft", "approved", "implemented"],
  "valid_transitions": {
    "draft": ["approved"],
    "approved": ["implemented", "draft"],
    "implemented": ["approved"]
  }
}
```

---

## Best Practices for AI Agents

### 1. Always Use JSON Output

```bash
# Good
engram status --json

# Bad (hard to parse)
engram status
```

### 2. Cache Frequently Accessed Data

```bash
# Cache status checks
if [ ! -f status_cache.json ] || [ $(find status_cache.json -mmin +5) ]; then
  engram status --json > status_cache.json
fi
```

### 3. Use Semantic Search for Understanding

```bash
# Vector mode understands meaning
engram query --mode vector "user authentication" --json
```

### 4. Leverage _llm Metadata

```bash
# Use token counts for optimization
TOKEN_COUNT=$(engram show req.auth --json | jq '._llm.c')
if [ $TOKEN_COUNT -gt 1000 ]; then
  # Use summary instead
  STRATEGY=$(engram show req.auth --json | jq '._llm.strategy')
fi
```

### 5. Chain Commands for Complex Workflows

```bash
# Get requirements → Generate tests → Create tests
engram query "type:requirement AND state:approved" --json | \
  ai-generate-tests | \
  jq -r '.[] | "engram new test_case \"\(.title)\" --validates \(.validates)"' | \
  bash
```

### 6. Handle Errors Gracefully

```bash
# Check if Neurona exists before operating
if engram show req.auth --json >/dev/null 2>&1; then
  # Proceed with operations
else
  echo "Neurona not found. Handle gracefully."
fi
```

### 7. Use Impact Analysis Before Changes

```bash
# Always analyze impact before modifying code
IMPACT=$(engram impact src/auth.zig --json)
AFFECTED_TESTS=$(echo $IMPACT | jq -r '.affected_items[] | select(.type == "test_case") | .id')

if [ ! -z "$AFFECTED_TESTS" ]; then
  echo "Warning: This will affect $AFFECTED_TESTS"
fi
```

---

## Performance Optimization

### 1. Use Filters to Limit Results

```bash
# Limit number of results
engram query --mode text "authentication" --limit 10 --json
```

### 2. Cache Expensive Operations

```bash
# Rebuild index periodically, not on every query
engram sync --force-rebuild
```

### 3. Use Specific Query Modes

```bash
# Filter mode is fastest
engram query --type requirement --json

# Hybrid mode is slower but more accurate
engram query --mode hybrid "authentication" --json
```

### 4. Batch Operations

```bash
# Batch updates instead of one at a time
engram update req.001 --set "status=implemented" \
  --set "assignee=alice" \
  --set "priority=1"
```

---

## Troubleshooting for AI Agents

### Issue: Neurona Not Found

```bash
# Search instead of direct reference
engram query --mode text "partial title" --json

# Or list all and find
engram status --json | jq '.results[] | select(.title | contains("auth"))'
```

### Issue: Invalid JSON Output

```bash
# Verify JSON is valid
engram status --json | jq .

# Check for errors
engram status --json 2>&1 | jq '.error // .'
```

### Issue: Slow Queries

```bash
# Sync index
engram sync --force-rebuild

# Use filters
engram query --type requirement --limit 100 --json
```

### Issue: Connections Not Updated

```bash
# Always sync after manual edits
engram sync
```

---

## Integration Examples

### Python AI Agent

```python
import json
import subprocess

def run_engram(command):
    """Run engram command and return JSON output"""
    result = subprocess.run(
        f"engram {command} --json",
        shell=True,
        capture_output=True,
        text=True
    )
    return json.loads(result.stdout)

# Get project status
status = run_engram("status")
print(f"Total items: {status['total']}")

# Find untested requirements
requirements = run_engram(
    'query "type:requirement AND NOT link(validates, type:test_case)"'
)

for req in requirements['results']:
    print(f"Untested: {req['title']}")

# Check release readiness
release = run_engram("release-status")
if not release['ready']:
    blockers = [b['id'] for b in release['blocking_items']]
    print(f"Blocked by: {blockers}")
```

### Node.js AI Agent

```javascript
const { execSync } = require('child_process');

function runEngram(command) {
    const output = execSync(`engram ${command} --json`, { encoding: 'utf-8' });
    return JSON.parse(output);
}

// Get project metrics
const metrics = runEngram('metrics');
console.log(`Coverage: ${metrics.test_coverage * 100}%`);

// Find high-priority issues
const issues = runEngram('query --type issue --priority 1');
issues.results.forEach(issue => {
    console.log(`P1 Issue: ${issue.title}`);
});

// Impact analysis
const impact = runEngram('impact src/auth/login.zig');
console.log('Affected items:', impact.affected_items.length);
```

---

## CI/CD Integration

### GitHub Actions

```yaml
name: Engram Release Check

on: [push, pull_request]

jobs:
  release-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Install Engram
        run: |
          wget https://github.com/yourusername/Engram/releases/latest/download/engram
          chmod +x engram
          
      - name: Check Release Readiness
        run: |
          ./engram init . --type alm
          READY=$(./engram release-status --json | jq '.ready')
          if [ "$READY" != "true" ]; then
            echo "❌ Not ready for release"
            exit 1
          fi
          echo "✅ Release ready"
          
      - name: Generate Release Notes
        if: success()
        run: |
          ./engram query "type:requirement AND state:implemented" --json | \
            jq -r '.results[] | "- \(.title)"' > RELEASE_NOTES.md
```

### Jenkins Pipeline

```groovy
pipeline {
    agent any
    
    stages {
        stage('Check Release Status') {
            steps {
                script {
                    def status = sh(
                        script: 'engram release-status --json',
                        returnStdout: true
                    ).trim()
                    
                    def ready = readJSON(text: status).ready
                    
                    if (!ready) {
                        error("Release not ready")
                    }
                }
            }
        }
        
        stage('Run Tests') {
            steps {
                script {
                    def tests = sh(
                        script: 'engram query "type:test_case AND state:passing" --json',
                        returnStdout: true
                    ).trim()
                    
                    def testCount = readJSON(text: status).results.size()
                    echo "Running ${testCount} tests"
                }
            }
        }
    }
}
```

---

## API-Like Usage Patterns

### RESTful Wrapper (Pseudo-code)

```bash
# GET /status
engram status --json

# GET /requirements
engram query --type requirement --json

# GET /requirements/{id}
engram show req.auth --json

# POST /requirements
engram new requirement "New Feature"

# PUT /requirements/{id}
engram update req.auth --set "status=implemented"

# DELETE /requirements/{id}
engram delete req.auth

# GET /requirements/{id}/trace
engram trace req.auth --json

# GET /impact?artifact=src/auth.zig
engram impact src/auth.zig --json
```

---

## Summary

Engram provides AI agents with:

1. **Structured JSON outputs** for easy parsing
2. **LLM-optimized metadata** for token efficiency
3. **Multiple search modes** including semantic understanding
4. **Complete traceability** through dependency analysis
5. **Automated workflows** for CI/CD integration
6. **Natural language queries** for flexible interaction
7. **Intelligent caching** for performance
8. **Impact analysis** for change management

### Key Commands for AI Agents

- `engram status --json` - Project overview
- `engram query --json` - Search and filter
- `engram show <id> --json` - Get details
- `engram trace <id> --json` - Dependency analysis
- `engram impact <artifact> --json` - Change impact
- `engram release-status --json` - Release readiness
- `engram metrics --json` - Statistics

### Best Practices

1. Always use `--json` flag for programmatic access
2. Cache frequently accessed data
3. Use semantic search for understanding
4. Chain commands for complex workflows
5. Handle errors gracefully
6. Use impact analysis before changes
7. Optimize queries with filters

Engram is designed to be the bridge between human project management and AI automation. Use these patterns to build intelligent, automated workflows for your software projects.

---

*For more information, see the main Engram manual at docs/manual.md*