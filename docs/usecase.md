# Engram CLI: Software Project Management Flows

## Flow 1: Developer Creates a Requirement (Human-Friendly)

### Developer starts a new requirement

```bash
$ engram new requirement "Support OAuth 2.0 Authentication"
✓ Created: neuronas/req.auth.oauth2.md
  Opening in $EDITOR...
```

**File created** (Tier 2 - ALM optimized):
```yaml
---
id: req.auth.oauth2
title: Support OAuth 2.0 Authentication
type: requirement
tags: [authentication, security]

connections:
  parent:
    - id: feature.authentication
      weight: 90

context:
  verification_method: test
  assignee: unassigned
  priority: 2
  status: draft

updated: "2026-01-21"
language: en
---

# Support OAuth 2.0 Authentication

## Description
[User writes requirement description]

## Acceptance Criteria
- [ ] User can authenticate via OAuth 2.0
- [ ] Tokens are securely stored
- [ ] Token refresh is automatic

## Verification Method
Test-driven validation via automated test suite
```

### Developer connects to parent feature

```bash
$ engram link req.auth.oauth2 to feature.authentication --type child
✓ Linked requirement to parent feature
  Parent: feature.authentication
  Type: hierarchical (child_of)
```

---

## Flow 2: QA Engineer Creates Test Specification (Human-Friendly)

### QA creates test linked to requirement

```bash
$ engram new test "OAuth Token Refresh Test"
✓ Created: neuronas/test.auth.oauth2.001.md

Which requirement does this validate?: req.auth.oauth2
Test framework [pytest]: 
Priority [1-5]: 3

✓ Test specification created
✓ Auto-linked to req.auth.oauth2
```

**File created**:
```yaml
---
id: test.auth.oauth2.001
title: OAuth Token Refresh Test
type: test_case
tags: [authentication, oauth, automated]

connections:
  validates:
    - id: req.auth.oauth2
      weight: 100

context:
  framework: pytest
  test_file: tests/auth/test_oauth_refresh.py
  status: not_run
  priority: 3
  assignee: unassigned

updated: "2026-01-21"
---

# OAuth Token Refresh Test

## Test Objective
Verify that OAuth tokens are automatically refreshed before expiration

## Test Steps
1. Authenticate user and obtain token
2. Wait until token is near expiration
3. Make authenticated request
4. Verify token was refreshed automatically

## Expected Results
- Token refresh occurs automatically
- User session remains active
- No authentication errors occur
```

### QA checks test coverage

```bash
$ engram trace req.auth.oauth2 --show tests
Requirement: Support OAuth 2.0 Authentication (req.auth.oauth2)

Test Coverage:
└─ test.auth.oauth2.001 - OAuth Token Refresh Test [NOT RUN]

Coverage: 1 test | 0 passing | 0 failing | 1 not run
Status: ⚠ Partial coverage
```

---

## Flow 3: Project Manager Creates Issue (Human-Friendly)

### PM creates blocking issue

```bash
$ engram new issue "OAuth library incompatible with Python 3.12"
✓ Created: neuronas/issue.auth.001.md

Priority [1-5]: 1
Assign to: @alice
Blocks requirement [optional]: req.auth.oauth2

✓ Issue created
✓ Linked as blocker to req.auth.oauth2
```

**File created**:
```yaml
---
id: issue.auth.001
title: OAuth library incompatible with Python 3.12
type: issue
tags: [bug, p1, authentication]

connections:
  blocks:
    - id: req.auth.oauth2
      weight: 100
  relates_to:
    - id: issue.deps.001
      type: similar

context:
  status: open
  priority: 1
  assignee: alice
  created: "2026-01-21"
  updated: "2026-01-21"

updated: "2026-01-21"
---

# OAuth library incompatible with Python 3.12

## Problem
The `authlib` package version 1.2.0 fails to import on Python 3.12
due to deprecated `asyncio` methods.

## Impact
Blocks implementation of req.auth.oauth2

## Proposed Solution
Upgrade to `authlib` 1.3.0 or find alternative library
```

### PM checks what's blocking the release

```bash
$ engram status --blocking release.v2.0
Issues blocking release.v2.0:

🔴 P1: OAuth library incompatible with Python 3.12
   ID: issue.auth.001
   Assignee: @alice
   Age: 2 hours
   Blocks: req.auth.oauth2 → feature.authentication → release.v2.0

🟡 P2: Database migration script incomplete
   ID: issue.db.002
   Assignee: @bob
   Age: 1 day
   Blocks: req.data.005 → release.v2.0

Total blocking issues: 2
```

---

## Flow 4: CI/CD System Queries Status (AI-Friendly)

### Build pipeline checks requirement validation

```bash
$ engram query "type:requirement AND link(child_of, feature.authentication)" --json
{
  "query": "type:requirement AND link(child_of, feature.authentication)",
  "results": [
    {
      "id": "req.auth.oauth2",
      "title": "Support OAuth 2.0 Authentication",
      "type": "requirement",
      "status": "draft",
      "validation": {
        "method": "test",
        "coverage": 1,
        "passing_tests": 0,
        "failing_tests": 0,
        "blocked_by": ["issue.auth.001"]
      }
    },
    {
      "id": "req.auth.2fa",
      "title": "Two-Factor Authentication",
      "type": "requirement",
      "status": "approved",
      "validation": {
        "method": "test",
        "coverage": 3,
        "passing_tests": 3,
        "failing_tests": 0,
        "blocked_by": []
      }
    }
  ],
  "total": 2,
  "execution_time_ms": 6.2
}
```

### CI pipeline checks if release is ready

```bash
$ engram release-status release.v2.0 --json
{
  "release": "release.v2.0",
  "ready": false,
  "requirements": {
    "total": 12,
    "validated": 8,
    "blocked": 2,
    "draft": 2
  },
  "blockers": [
    {
      "type": "issue",
      "id": "issue.auth.001",
      "priority": 1,
      "blocks": ["req.auth.oauth2"]
    }
  ],
  "test_results": {
    "total": 45,
    "passing": 42,
    "failing": 1,
    "not_run": 2
  },
  "completion": 0.67
}
```

---

## Flow 5: Developer Updates Test Results (Mixed Human-AI)

### Developer runs tests and updates status

```bash
$ pytest tests/auth/test_oauth_refresh.py --engram-report
....
4 passed in 2.3s

Updating Engram test status...
✓ Updated test.auth.oauth2.001 → status: passing
```

Behind the scenes, this runs:
```bash
$ engram update test.auth.oauth2.001 --set "context.status=passing" \
  --set "context.last_run=2026-01-21T14:30:00Z" \
  --set "context.duration=2.3s"
```

### Check requirement status after test pass

```bash
$ engram show req.auth.oauth2
Requirement: Support OAuth 2.0 Authentication
ID: req.auth.oauth2
Status: draft
Priority: 2
Assignee: unassigned

Validation:
✓ test.auth.oauth2.001 - OAuth Token Refresh Test [PASSING]

Blockers:
🔴 issue.auth.001 - OAuth library incompatible with Python 3.12 (P1)

Parent Feature:
└─ feature.authentication

Status: ⚠ Tests passing but blocked by 1 critical issue
```

---

## Flow 6: Tech Lead Reviews Full Traceability (V-Model)

### Show complete requirement chain

```bash
$ engram trace req.auth.oauth2 --full-chain
┌─────────────────────────────────────┐
│ Feature: Authentication             │
│ feature.authentication              │
└──────────────┬──────────────────────┘
               │ (parent)
     ┌─────────▼──────────────────────────────────┐
     │ Requirement: Support OAuth 2.0 Auth        │
     │ req.auth.oauth2                            │
     │ Status: draft | Priority: 2                │
     └──┬────────────────────────────────┬────────┘
        │ (validates)                    │ (blocks)
   ┌────▼──────────────────┐      ┌──────▼─────────────────────┐
   │ Test: OAuth Refresh   │      │ Issue: Library incompatible│
   │ test.auth.oauth2.001  │      │ issue.auth.001             │
   │ [✓ PASSING]           │      │ [🔴 OPEN - P1]             │
   └───────────────────────┘      └────────────────────────────┘
        │ (implements)
   ┌────▼──────────────────┐
   │ Code: oauth_client.py │
   │ artifact.oauth.client │
   └───────────────────────┘

Traceability: ✓ COMPLETE
All levels connected: Feature → Requirement → Test → Code
```

### Find untested requirements

```bash
$ engram query "type:requirement AND NOT link(validates, type:test_case)"
Found 3 untested requirements:

⚠ req.auth.2fa - Two-Factor Authentication
  Priority: 1 | Assignee: @bob
  Parent: feature.authentication
  
⚠ req.payments.refund - Refund Processing
  Priority: 2 | Assignee: @carol
  Parent: feature.payments
  
⚠ req.api.ratelimit - API Rate Limiting
  Priority: 3 | Assignee: unassigned
  Parent: feature.api

Recommendation: Create test specifications for P1/P2 requirements
```

---

## Flow 7: Developer Links Code Artifact to Requirement

### Link actual source code to requirement

```bash
$ engram link-artifact src/auth/oauth_client.py to req.auth.oauth2 --type implements
✓ Created artifact neurona: artifact.oauth.client
✓ Linked to requirement: req.auth.oauth2
```

**File created**:
```yaml
---
id: artifact.oauth.client
title: OAuth Client Implementation
type: artifact
tags: [code, python, authentication]

connections:
  implements:
    - id: req.auth.oauth2
      weight: 100
  tested_by:
    - id: test.auth.oauth2.001
      weight: 100

context:
  runtime: python
  file_path: src/auth/oauth_client.py
  safe_to_exec: false
  language_version: "3.12"
  last_modified: "2026-01-21"

updated: "2026-01-21"
---

# OAuth Client Implementation

**Source File**: `src/auth/oauth_client.py`

This artifact implements the OAuth 2.0 client logic as specified in req.auth.oauth2.
```

### Show impact analysis for code changes

```bash
$ engram impact src/auth/oauth_client.py
Analyzing impact of changes to: src/auth/oauth_client.py

Direct Impact:
└─ artifact.oauth.client (this file)
   ├─ Implements: req.auth.oauth2 (Support OAuth 2.0 Authentication)
   ├─ Tested by: test.auth.oauth2.001 (OAuth Token Refresh Test)
   └─ Part of: feature.authentication

Upstream Impact:
└─ feature.authentication
   └─ Required by: release.v2.0

Affected Tests (should run):
- test.auth.oauth2.001 - OAuth Token Refresh Test

Recommendation: Run affected tests before committing
```

---

## Flow 8: Automated Metrics Dashboard (AI Query)

### Generate project health report

```bash
$ engram metrics --period 7d --json
{
  "period": "last_7_days",
  "requirements": {
    "total": 24,
    "new": 5,
    "validated": 18,
    "blocked": 3,
    "test_coverage": 0.75
  },
  "issues": {
    "total_open": 12,
    "created": 8,
    "resolved": 6,
    "p1_open": 2,
    "p2_open": 5,
    "avg_resolution_time_hours": 18.5
  },
  "tests": {
    "total": 67,
    "passing": 63,
    "failing": 2,
    "not_run": 2,
    "pass_rate": 0.94
  },
  "velocity": {
    "requirements_per_week": 5,
    "tests_per_week": 8,
    "issues_resolved_per_week": 6
  },
  "traceability": {
    "requirements_with_tests": 0.75,
    "tests_with_code": 0.68,
    "complete_chains": 0.62
  }
}
```

---

## Key Patterns for Human-AI Accessibility

### 1. **Command Aliases**
```bash
# Human-friendly
engram new requirement "Title"

# AI-friendly (same result)
engram create --type requirement --title "Title" --json
```

### 2. **Natural Status Checks**
```bash
# Human
engram status

# AI
engram query "type:issue AND context.status:open" --json
```

### 3. **Flexible Linking**
```bash
# Human (fuzzy match on titles)
engram link "OAuth requirement" to "Authentication feature"

# AI (exact IDs)
engram link req.auth.oauth2 feature.authentication --type child_of
```

### 4. **Progressive Output**
```bash
# Human sees:
✓ 3 tests passing
⚠ 1 requirement blocked
🔴 2 P1 issues open

# AI gets (with --json):
{"passing": 3, "blocked": 1, "p1_issues": 2}
```

### 5. **Contextual Help**
```bash
$ engram trace
Error: Missing target

Usage: engram trace <requirement|test|issue> [OPTIONS]

Show dependency chains in the V-model.

Examples (human):
  engram trace req.auth.oauth2           # Show all connections
  engram trace req.auth.oauth2 --up      # Show parent features
  engram trace req.auth.oauth2 --down    # Show tests and code

AI Usage:
  engram trace <id> --json --depth 5 --direction both
```

---

## Summary: Engram as ALM Tool

Engram implements software project management as a **graph of Neuronas**:

- **Requirements** (`type: requirement`) - What to build
- **Test Cases** (`type: test_case`) - How to validate  
- **Issues** (`type: issue`) - What's blocking progress
- **Code Artifacts** (`type: artifact`) - What's implemented
- **Features** (`type: feature`) - Organizational grouping

The **Neurona Open Specification** provides:
- **Tier 1**: Simple YAML anyone can write
- **Tier 2**: Structured connections for traceability
- **Tier 3**: Machine-queryable metadata for CI/CD

The CLI bridges both worlds:
- **Humans** get natural commands and readable output
- **AI/CI** gets JSON, fast queries, and programmatic access