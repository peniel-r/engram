# Engram User Manual

**Version 0.1.0** | **Last Updated: January 31, 2026**

---

## Welcome to Engram

**Engram** is a high-performance Application Lifecycle Management (ALM) tool that helps software teams manage requirements, tests, issues, and code artifacts through a connected knowledge graph. Think of it as your project's digital brain where every requirement, test, bug report, and code file is linked together with meaningful relationships.

**Built for Both Humans and AI**

Engram is uniquely designed to work seamlessly with both human users and AI agents:

- **For Humans**: Intuitive commands, clear visual output, and natural language queries make it easy to manage your project
- **For AI/LLM Agents**: Structured data, JSON outputs, optimized metadata, and intelligent caching enable seamless AI integration and automated workflows

**Primary Use Case: Software Project Management**

Engram is designed for:
- **Software Developers** - Track requirements from design to implementation, link code to tests, and understand what breaks when you change code
- **Project Managers** - See the complete picture of what's built, what's tested, and what's blocking your release
- **QA Engineers** - Ensure every requirement has tests, track test coverage, and validate that all acceptance criteria are met
- **Tech Leads** - Perform impact analysis before making changes, trace dependencies, and check release readiness
- **AI Agents** - Access structured project data, perform automated analysis, generate reports, and integrate with CI/CD pipelines

**Secondary Use Case: Knowledge Management**

While Engram's primary focus is ALM, it also provides powerful knowledge management capabilities for:
- Researchers organizing notes and concepts
- Knowledge workers building personal knowledge bases
- Teams documenting and connecting related information

Engram's knowledge graph foundation enables both use cases, but its core features and workflows are optimized for software project management with full LLM integration.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Basic Concepts](#basic-concepts)
3. [Getting Started](#getting-started)
4. [AI/LLM Integration](#aillm-integration)
5. [Creating Project Artifacts](#creating-project-artifacts)
6. [Managing Your Knowledge](#managing-your-knowledge)
7. [Searching and Querying](#searching-and-querying)
8. [Project Management Features with AI Integration](#project-management-features-with-ai-integration)
9. [Advanced Features](#advanced-features)
10. [Practical Examples](#practical-examples)
11. [Tips and Tricks](#tips-and-tricks)
12. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Installation

**For Developers:**

```bash
# Clone the repository
git clone https://github.com/yourusername/Engram.git
cd Engram

# Build the project (requires Zig 0.15.2 or higher)
zig build -Doptimize=ReleaseSafe

# The binary will be in: zig-out/bin/engram.exe (Windows) or zig-out/bin/engram (Linux/Mac)
```

### Your First Software Project in 5 Minutes

A **Cortex** is your project's workspace containing all requirements, tests, issues, and related information.

```bash
# 1. Create a new Cortex for your software project
engram init my_project --type alm

# 2. Enter your project directory
cd my_project

# 3. Create your first requirement
engram new requirement "Support User Login"

# 4. Create a test that validates your requirement
engram new test_case "Login Test" --validates req.support-user-login

# 5. Report a blocking issue
engram new issue "Database timeout on login" --blocks req.support-user-login --priority 1

# 6. See your project status
engram status

# 7. View your requirement with all its connections
engram show req.support-user-login

# 8. Check if your project is ready for release
engram release-status
```

That's it! You now have a fully functional ALM system with:
- Requirements that need to be built
- Tests that validate those requirements
- Issues that track what's blocking progress
- Traceability showing how everything connects

**Note:** While Engram can also be used as a general knowledge management tool, its core features and workflows are optimized for software project management. Use the `--type alm` flag when initializing for the best ALM experience.

---

## Basic Concepts

### What is a Cortex?

A **Cortex** is your software project's workspace containing all project artifacts. It's a folder on your computer that contains:

- `neuronas/` - Your project files (requirements, test cases, issues, code artifacts, features)
- `cortex.json` - Project configuration settings
- `.activations/` - System-generated indices (you can ignore these)
- `assets/` - For storing diagrams, screenshots, and other project assets

### What is a Neurona?

A **Neurona** (plural: Neuronas) is a single project artifact. In the ALM context, this could be a requirement, test case, issue report, code artifact, or feature. Think of it as a smart item card that can connect to other artifacts through meaningful relationships.

Each Neurona is a simple text file with:
- **ID** - A unique identifier (like `req.auth.login`, `test.login.basic`, `issue.db.001`)
- **Title** - A human-readable name
- **Type** - What kind of artifact it is (requirement, test_case, issue, artifact, feature, etc.)
- **Content** - The actual details (acceptance criteria, test steps, bug description, etc.)
- **Connections** - Links to related artifacts (tests validate requirements, issues block requirements, etc.)

### Types of Neuronas

Engram provides specialized Neurona types designed primarily for Application Lifecycle Management (ALM). These core ALM types enable complete traceability from requirements through testing to implementation.

#### Core ALM Types (Primary Use Case):

- **`requirement`** - What needs to be built (features, user stories, specifications)
- **`test_case`** - How to verify something works (test specifications, validation criteria)
- **`issue`** - Problems or bugs (bug reports, blockers, enhancement requests)
- **`artifact`** - Code files, scripts, or tools that implement requirements
- **`feature`** - Groups of related requirements for organization

#### Supporting Types (Secondary Use Cases):

While Engram's primary focus is ALM, it also supports general knowledge management through these types:

- **`concept`** - General notes or ideas (useful for project documentation)
- **`reference`** - Facts, definitions, API documentation
- **`lesson`** - Educational content or tutorials
- **`state_machine`** - Workflow steps or process states

**Best Practice:** For software projects, use the ALM types (`requirement`, `test_case`, `issue`, `artifact`, `feature`) to get the most out of Engram's traceability, impact analysis, and release management features.

### Connections: The Power of Neuronas

What makes Engram special is that Neuronas can be **connected** to each other. This creates a web of relationships that helps you navigate your knowledge.

**Common connection types:**
- `validates` - A test validates a requirement
- `blocks` - An issue blocks a requirement
- `parent` - Hierarchical relationship (like a folder structure)
- `relates_to` - General relationship
- `implements` - Code implements a requirement

---

## AI/LLM Integration

Engram is built from the ground up to work seamlessly with Large Language Models and AI agents. Every Neurona contains optimized metadata that makes AI integration fast and efficient.

### LLM-Optimized Metadata

Each Neurona includes `_llm` metadata that's specifically designed for AI consumption:

```bash
engram show req.auth --json
```

Output includes:
```json
{
  "_llm": {
    "t": "OAuth 2.0 Login",           // Short title (token efficient)
    "d": 3,                            // Density/difficulty (1-4)
    "k": ["oauth", "login", "auth"],    // Top keywords
    "c": 850,                           // Token count
    "strategy": "summary"                  // full, summary, hierarchical
  }
}
```

### Token Optimization

Engram automatically counts tokens and provides different strategies for AI consumption:

- **Full Strategy**: Send complete Neurona content (all tokens)
- **Summary Strategy**: Use pre-generated summary (fewer tokens)
- **Hierarchical Strategy**: Start with summary, drill down on demand

### LLM Response Caching

Engram automatically caches LLM responses to avoid redundant computations and API calls:

```bash
# Cache is stored in .activations/cache/
# Automatically invalidated when content changes
```

### JSON Output for AI Integration

Every command supports `--json` output for seamless AI agent integration:

```bash
# AI agents can parse this directly
engram query --type issue --json
engram trace req.auth --json
engram release-status --json
engram metrics --json
```

### Structured Data Format

All Engram data follows the Neurona specification, making it predictable and parseable by AI:

```yaml
---
id: req.auth.oauth2
title: Support OAuth 2.0 Authentication
type: requirement
tags: [authentication, security]

connections:
  validates:
    - id: test.auth.oauth2.001
      weight: 100

context:
  status: draft
  priority: 2
  assignee: unassigned

_llm:
  t: "OAuth 2.0"
  d: 3
  k: [oauth, auth, login]
  c: 850
  strategy: summary

updated: "2026-01-21"
language: en
---
```

### AI Use Cases

Engram enables powerful AI-driven workflows:

**Automated Requirements Analysis:**
```bash
# AI agent queries and analyzes requirements
engram query "type:requirement AND state:draft" --json | ai-analyzer
```

**Smart Test Generation:**
```bash
# AI suggests tests based on requirements
engram show req.auth --json | ai-generate-tests
```

**Release Prediction:**
```bash
# AI predicts release readiness
engram release-status --json | ai-predict-date
```

**Impact Analysis Automation:**
```bash
# AI automatically analyzes code changes
engram impact src/auth.zig --json | ai-affected-tests
```

**Natural Language Queries:**
```bash
# Ask questions in plain English
engram query "show me all P1 issues that are blocking authentication"
engram query "what tests are failing for the login feature?"
```

### Semantic Search Powered by AI

Engram's semantic search mode uses embeddings to find related content even when exact words don't match:

```bash
# Finds "user authentication" even if you search for "login process"
engram query --mode vector "user sign in methods"
```

This is powered by vector embeddings that understand semantic meaning.

---

## Getting Started

### Creating a Cortex

```bash
# Basic command
engram init <name>

# Examples:
engram init my_notes
engram init project_alpha --type alm
engram init knowledge_base --type knowledge --language es
```

**Options:**
- `--type, -t` - Choose: `zettelkasten` (default), `alm` (for software projects), or `knowledge`
- `--language, -l` - Default language (default: `en` for English)
- `--force, -f` - Overwrite existing Cortex

**What happens:**
Engram creates a new folder with the structure:
```
my_cortex/
├── cortex.json              # Configuration
├── README.md                # Overview
├── neuronas/                # Your Neuronas go here
├── .activations/            # System files (ignore these)
└── assets/                  # Images, diagrams, etc.
```

### Exploring a Cortex

```bash
# List all Neuronas
engram status

# List only specific types
engram status --type requirement
engram status --type issue

# Filter by status
engram status --filter "state:open AND priority:1"

# Sort results
engram status --sort-by priority
engram status --sort-by created
```

---

## Configuration

Engram uses a YAML configuration file to store user preferences and default settings. This makes it easy to customize your workflow without needing to specify options repeatedly.

### Configuration File Location

The configuration file is located at:
- **Linux/Mac:** `~/.config/engram/engram-config.yaml`
- **Windows:** `%USERPROFILE%\.config\engram\engram-config.yaml`

The configuration file is automatically created with default values the first time you use Engram.

### Opening the Configuration File

The easiest way to edit your configuration is with the `open-config` command:

```bash
# Open config file in your default text editor
engram open-config

# With verbose output to see file location
engram open-config --verbose
```

This will open the configuration file in your configured text editor (helix by default).

### Configuration Options

The configuration file supports the following options:

```yaml
# Engram Configuration File
# This file controls default behavior for Engram CLI

# Default text editor for opening files (e.g., helix, vim, nvim, code)
text-editor: helix

# Default artifact type when creating new neuronas
# Options: feature, requirement, test_case, issue, artifact
default-artifact-type: feature

# Default directory for neuronas storage
neuronas-dir: neuronas

# Enable verbose output by default
verbose-output: false

# Enable JSON output by default (for AI agent integration)
json-output: false
```

#### text-editor

Specifies the default text editor to use when opening files.

**Common values:**
- `helix` - Modern, modal editor (default)
- `vim` - Classic modal editor
- `nvim` - Neovim editor
- `code` - VS Code
- `nano` - Simple terminal editor

**Example:**
```yaml
text-editor: code
```

#### default-artifact-type

Sets the default type when creating new Neuronas. This is useful if you primarily work with one type of artifact.

**Options:**
- `feature` - Group of related requirements
- `requirement` - What needs to be built
- `test_case` - How to verify something works
- `issue` - Problems or bugs
- `artifact` - Code files or scripts

**Example:**
```yaml
# If you mostly write requirements
default-artifact-type: requirement
```

Then you can create requirements more quickly:
```bash
engram new "Support User Login"  # Creates a requirement automatically
```

#### neuronas-dir

Specifies the default directory where Neuronas are stored.

**Default:** `neuronas`

**Example:**
```yaml
# Use a different directory name
neuronas-dir: docs
```

#### verbose-output

Enable verbose output by default for all commands.

**Default:** `false`

**Example:**
```yaml
verbose-output: true
```

#### json-output

Enable JSON output by default. This is particularly useful for AI agents and automated workflows.

**Default:** `false`

**Example:**
```yaml
json-output: true
```

With this enabled, commands like `engram status` will output JSON by default, making it easier to integrate with AI agents and CI/CD pipelines.

### Example Configuration

Here's a complete example configuration for a developer who uses VS Code and primarily works with requirements:

```yaml
# Engram Configuration File

# Use VS Code as my editor
text-editor: code

# I mostly write requirements
default-artifact-type: requirement

# Standard neuronas directory
neuronas-dir: neuronas

# Enable verbose output
verbose-output: true

# Enable JSON for AI integration
json-output: false
```

### Manually Editing the Configuration

You can also edit the configuration file directly with any text editor:

```bash
# Open with your preferred editor
code ~/.config/engram/engram-config.yaml  # Linux/Mac
code %USERPROFILE%\.config\engram\engram-config.yaml  # Windows
```

After editing, the changes take effect immediately for new commands.

### Benefits of Configuration

Using the configuration file provides several benefits:

1. **Consistency**: Set your preferences once and they apply everywhere
2. **Efficiency**: Skip typing common options repeatedly
3. **Team Standardization**: Share configuration files with team members
4. **AI Integration**: Configure JSON output for seamless AI agent workflows
5. **Editor Preference**: Use your favorite editor without specifying it each time

### Configuration for AI Agents

For AI agents and automated workflows, consider this configuration:

```yaml
# AI-Optimized Configuration

text-editor: helix
default-artifact-type: feature
neuronas-dir: neuronas
verbose-output: false

# Enable JSON by default for AI parsing
json-output: true
```

With `json-output: true`, AI agents can automatically parse all command outputs without needing to specify `--json` every time.

---

## Creating Project Artifacts

### Creating a Neurona

The basic command is:

```bash
engram new <type> <title>
```

### Creating Requirements (Primary Use Case)

Requirements define what needs to be built. They are the foundation of your project's traceability.

```bash
# Simple requirement
engram new requirement "Support User Login"

# With tags
engram new requirement "Password Reset" --tag security --tag account

# With priority
engram new requirement "Two-Factor Authentication" --priority 1

# Assign to someone
engram new requirement "OAuth Integration" --assignee alice

# Link to a parent feature
engram new requirement "Login UI" --parent feature.authentication
```

#### Creating Test Cases (ALM Artifact)

Test cases verify that requirements are implemented correctly. They link to requirements for full traceability.

```bash
# Create a test that validates a requirement
engram new test_case "Login Test" --validates req.support-user-login

# Specify test framework
engram new test_case "Auth Tests" --validates req.oauth --framework pytest

# Multiple tests for one requirement
engram new test_case "Login with Valid Credentials" --validates req.user-login
engram new test_case "Login with Invalid Password" --validates req.user-login
engram new test_case "Login Account Lockout" --validates req.user-login
```

#### Creating Issues (ALM Artifact)

Issues track problems, bugs, and blockers. They link to what they block for impact analysis.

```bash
# Report a bug
engram new issue "Login button doesn't work" --priority 1

# Link to what it blocks
engram new issue "Database timeout" --blocks req.user-login

# Assign to someone
engram new issue "API rate limit exceeded" --assignee bob --priority 2

# Link multiple blockers
engram new issue "OAuth library incompatibility" \
  --blocks req.oauth \
  --blocks req.token-refresh
```

#### Creating Features (ALM Artifact)

Features group related requirements together for organization and tracking.

```bash
# Create a feature group
engram new feature "Authentication System"

# Connect requirements to it
engram link req.support-user-login feature.authentication-system parent
engram link req.password-reset feature.authentication-system parent
engram link req.two-factor-auth feature.authentication-system parent

# Check what requirements are in a feature
engram trace feature.authentication-system --down
```

#### Creating Code Artifacts (ALM Artifact)

Artifacts represent actual code files that implement requirements. They enable traceability from requirement to code.

```bash
# Link code to requirements
engram link-artifact req.user-login zig --file src/auth/login.zig

# Link multiple files
engram link-artifact req.oauth python \
  --file src/oauth/client.py \
  --file src/oauth/tokens.py \
  --file src/oauth/refresh.py
```

#### Creating Knowledge Items (Secondary Use Case)

While Engram is optimized for ALM, you can also create general knowledge items:

```bash
# Create a general note
engram new concept "Async Programming in Python"

# Create a reference
engram new reference "Python asyncio API"

# Create a lesson
engram new lesson "Building Your First Async API"
```

**Tip:** For best results, stick to ALM types (`requirement`, `test_case`, `issue`, `artifact`, `feature`) when managing software projects. This gives you access to specialized features like release status, impact analysis, and full traceability.

### Understanding Neurona IDs

When you create a Neurona, Engram automatically generates an ID based on its title:

```
Title: "Support User Login"
→ ID: req.support-user-login

Title: "Password Reset"
→ ID: req.password-reset
```

The ID follows this pattern:
- First part: Type abbreviation (`req`, `test`, `issue`, etc.)
- Second part: Lowercase title with hyphens

You can use either the ID or search by title when referring to Neuronas.

---

## Managing Your Knowledge

### Viewing Neuronas

```bash
# Show a Neurona
engram show <id>

# Examples:
engram show req.support-user-login
engram show test.login-test
engram show issue.login-bug

# Hide connections (cleaner view)
engram show req.auth --no-connections

# Hide content (just show metadata)
engram show req.auth --no-body

# Get JSON output (for scripts/AI)
engram show req.auth --json
```

### Updating Neuronas

The basic command is:

```bash
engram update <id> [options]
```

#### Update Context Fields

```bash
# Update a specific field
engram update <id> --set "field=value"

# Change status
engram update test.001 --set "context.status=passing"
engram update req.001 --set "context.status=implemented"

# Update priority
engram update req.001 --set "context.priority=1"

# Change title
engram update req.001 --set "title=New Title"

# Multiple updates at once
engram update req.001 --set "context.status=implemented" --set "context.assignee=alice"
```

#### Tag Management

```bash
# Add a tag
engram update req.001 --add-tag "security"
engram update req.001 -t "high-priority"

# Add multiple tags
engram update req.001 --add-tag "security" --add-tag "critical"

# Remove a tag
engram update req.001 --remove-tag "draft"

# Combine tag operations
engram update req.001 --add-tag "security" --remove-tag "requirement"
```

#### Common Field Updates

For Requirements:
```bash
engram update req.001 --set "context.status=approved"
engram update req.001 --set "context.status=implemented"
```

For Tests:
```bash
engram update test.001 --set "context.status=passing"
engram update test.001 --set "context.status=failing"
```

For Issues:
```bash
engram update issue.001 --set "context.status=in_progress"
engram update issue.001 --set "context.status=resolved"
```

#### Verbose Mode

```bash
# See what's being updated
engram update req.001 --add-tag "security" --verbose
# Output:   Added tag: security
#         ✓ Updated req.001
```

For Requirements:
```bash
engram update req.001 --set "context.status=approved"
engram update req.001 --set "context.status=implemented"
```

For Tests:
```bash
engram update test.001 --set "context.status=passing"
engram update test.001 --set "context.status=failing"
```

For Issues:
```bash
engram update issue.001 --set "context.status=in_progress"
engram update issue.001 --set "context.status=resolved"
```

### Deleting Neuronas

```bash
# Delete a Neurona
engram delete <id>

# Examples:
engram delete req.obsolete-feature
engram delete issue.001 --verbose
```

**Note:** This permanently deletes the file. Consider linking instead of deleting if the information might still be useful.

---

## Connecting Knowledge

### Creating Connections

Connections are what make Engram powerful. They create relationships between Neuronas.

```bash
engram link <source> <target> <connection_type>
```

#### Common Examples

**Link a test to a requirement:**
```bash
engram link test.login-test req.support-user-login validates
```

**Link an issue to what it blocks:**
```bash
engram link issue.login-bug req.support-user-login blocks
```

**Create a hierarchical relationship:**
```bash
engram link req.oauth feature.auth parent
```

**Connect related items:**
```bash
engram link req.password-reset req.forgot-password relates_to
```

#### Connection Options

```bash
# Set the strength of the connection (0-100, default: 50)
engram link req.a req.b parent --weight 90

# Create a bidirectional link (links both ways)
engram link req.a req.b relates_to --bidirectional
```

### Viewing Connections

When you show a Neurona, you'll see its connections:

```bash
engram show req.auth
```

Output:
```
Requirement: Support User Login
ID: req.auth
Type: requirement

Connections:
  Parent:
    └─ feature.authentication (weight: 90)

  Validated by:
    ├─ test.login-basic (weight: 100)
    └─ test.login-with-2fa (weight: 100)

  Blocked by:
    └─ issue.database-timeout (weight: 100)
```

---

## Searching and Querying

Engram offers **5 powerful search modes** plus **EQL (Engram Query Language)** for advanced filtering.

### Using EQL (Engram Query Language)

For complex filtering and advanced queries, use EQL syntax:

#### EQL Syntax

```
Expression    → Term { OR Term }
Term          → Factor { AND Factor }
Factor        → NOT Factor | ( Expression ) | Condition
Condition     → field ':' [op ':'] value | link(type, target)
```

#### EQL Operators

| Operator | Syntax | Description |
|----------|---------|-------------|
| `AND` | `A AND B` | Both conditions must match |
| `OR` | `A OR B` | Either condition must match |
| `NOT` | `NOT A` | Negates condition |
| `()` | `(A AND B)` | Groups expressions |
| `eq` (default) | `field:value` | Exact match |
| `contains` | `field:contains:value` | Substring match |
| `gte` | `field:gte:value` | Greater than or equal |
| `lte` | `field:lte:value` | Less than or equal |
| `gt` | `field:gt:value` | Greater than |
| `lt` | `field:lt:value` | Less than |
| `link()` | `link(type, target)` | Find connections |

#### EQL Fields

| Field | Description | Example |
|--------|-------------|---------|
| `type` | Neurona type | `type:issue` |
| `tag` | Tag match | `tag:security` |
| `priority` | Priority level | `priority:1` |
| `title` | Title contains | `title:contains:oauth` |
| `context.status` | Status field | `context.status:open` |
| `context.priority` | Context priority | `context.priority:1` |
| `context.assignee` | Assignee field | `context.assignee:alice` |

#### EQL Examples

```bash
# Simple type query
engram query "type:issue"

# Priority filtering
engram query "type:issue AND priority:1"

# State filtering
engram query "type:requirement AND context.status:approved"

# Complex logical expression
engram query "(type:requirement OR type:issue) AND priority:lte:3"

# Negation
engram query "type:requirement AND NOT priority:1"

# Link queries
engram query "link(validates, req.auth.login) AND type:test_case"
engram query "link(blocks, req.feature) AND type:issue"

# Content search
engram query "title:contains:oauth"
engram query "title:contains:authentication OR tag:security"

# Multiple conditions
engram query "type:issue AND priority:1 AND state:open"

# Deep nesting
engram query "((type:requirement OR type:issue) AND priority:3) OR tag:critical"
```

### 1. Filter Mode (Default)

Filter by type, tags, and status.

```bash
# List all issues
engram query --type issue

# Find high-priority items
engram query --type issue --priority 1

# Combine filters
engram query --type requirement --status draft
```

### 2. Text Mode (Full-Text Search)

Search through the content using BM25 ranking (like Google search).

```bash
# Search for anything containing "login"
engram query --mode text "login"

# Search for phrases
engram query --mode text "user authentication"

# Limit results
engram query --mode text "password" --limit 5
```

### 3. Vector Mode (Semantic Search)

Find related concepts using meaning, not just exact words.

```bash
# Find semantically similar items
engram query --mode vector "user sign in"

# Works even if words are different
engram query --mode vector "authentication methods"
```

### 4. Hybrid Mode (Best of Both Worlds)

Combines text and vector search for optimal results.

```bash
# Smart search that uses both keyword matching and semantic meaning
engram query --mode hybrid "login failure"

# Great for finding the most relevant results
engram query --mode hybrid "performance problems" --limit 5
```

### 5. Activation Mode (Neural Propagation)

Propagate search through connected Neuronas - like following thoughts.

```bash
# Start with a concept and follow connections
engram query --mode activation "login"

# Finds related items through the web of connections
engram query --mode activation "critical"
```

### Using EQL (Engram Query Language)

For complex filtering, use EQL syntax:

```bash
# Find all P1 issues
engram query "type:issue AND priority:1"

# Find passing tests
engram query "type:test_case AND state:passing"

# Complex queries
engram query "(type:requirement OR type:issue) AND state:open"

# Search for specific content
engram query "title:contains:authentication OR tag:security"

# Find items linked to something specific
engram query "link(validates, req.auth.oauth2)"
```

### Natural Language Queries

You can also search using plain English:

```bash
# Just type what you're looking for
engram query "show me all open issues"
engram query "find tests that are failing"
engram query "what requirements are blocked by issues"
```

Engram will try to understand your intent and find the right results.

---

## Project Management Features with AI Integration

Engram's ALM features are designed to work seamlessly with both human users and AI agents, enabling automated workflows and intelligent analysis.

### Tracing Dependencies

Visualize how requirements connect to tests, code, and features.

```bash
# Show all downstream connections (tests, code, etc.)
engram trace req.auth

# Show upstream connections (features, parents)
engram trace req.auth --up

# Limit the depth
engram trace req.auth --depth 3

# Different formats
engram trace req.auth --format tree
engram trace req.auth --format list

# JSON output for scripts
engram trace req.auth --json
```

**Example Output:**
```
Requirement: Support User Login (req.auth)
└─ Feature: Authentication (feature.auth)
   └─ Release: v1.0 (release.v1.0)

Validated by Tests:
├─ test.login-basic (PASSING)
└─ test.login-with-2fa (NOT RUN)

Blocked by Issues:
└─ issue.database-timeout (OPEN - P1)
```

### Impact Analysis

See what would be affected by a change.

```bash
# What depends on this requirement?
engram impact req.auth

# What would this code affect?
engram impact src/auth/login.zig --down

# Both directions
engram impact req.auth --depth 5
```

**Use case:** Before changing code, run impact analysis to see which tests might break.

### Linking Code to Requirements

Connect actual source files to requirements.

```bash
# Link a file to a requirement
engram link-artifact req.auth zig --file src/auth/login.zig

# Link multiple files
engram link-artifact req.oauth python \
  --file src/oauth/client.py \
  --file src/oauth/tokens.py

# Mark as safe to execute
engram link-artifact req.test zig --file src/test.zig --safe
```

### Release Status Check

See if your project is ready for release.

```bash
# Check overall readiness
engram release-status

# Detailed breakdown
engram release-status --verbose

# JSON for CI/CD pipelines
engram release-status --json
```

**Example Output:**
```
Release Readiness: 67% ⚠

Requirements:
  Total: 24
  Implemented: 16
  Blocked: 3
  Draft: 5

Tests:
  Passing: 42 (94%)
  Failing: 2
  Not Run: 2

Blocking Issues:
  🔴 P1: issue.database-timeout
  🟡 P2: issue.api-rate-limit
```

### Project Metrics

Get statistics about your project.

```bash
# All metrics
engram metrics

# Metrics for a time period
engram metrics --last 7
engram metrics --since 2026-01-01

# JSON format
engram metrics --json
```

---

## Advanced Features

### Syncing the Graph Index

Engram maintains a fast search index. If you manually edit files, you may need to sync:

```bash
# Rebuild the index
engram sync

# Verbose output
engram sync --verbose

# Rebuild from scratch
engram sync --force-rebuild
```

### Using JSON Output for AI Integration

Most commands support `--json` for programmatic access, making it easy to integrate with AI agents and automated systems:

```bash
engram query --type issue --json
engram show req.auth --json
engram trace req.auth --json
engram status --json
```

This is useful for:
- **AI Agents**: Parse structured data directly for automated analysis and decision-making
- **CI/CD Pipelines**: Automated release checks and status reporting
- **Custom Scripts**: Build custom tooling and integrations
- **Data Analysis**: Export data for analysis and reporting

**Example AI Integration:**
```bash
# AI agent reads project status and makes recommendations
engram release-status --json | ai-analyze --suggest-improvements

# AI agent identifies at-risk requirements
engram query "type:requirement AND state:blocked" --json | ai-prioritize

# AI agent generates test coverage report
engram metrics --json | ai-generate-coverage-report
```

### Working with Different Cortex Types

Engram supports different Cortex types, but it's optimized primarily for ALM (Application Lifecycle Management).

#### ALM (Application Lifecycle Management) - PRIMARY USE CASE

Best for software projects with requirements, tests, issues, and code artifacts. This is Engram's intended use case and provides access to all ALM-specific features like traceability, impact analysis, and release management.

```bash
engram init my_project --type alm
```

**Why choose ALM:**
- Complete requirements-to-code traceability
- Test coverage tracking
- Issue blocking analysis
- Release readiness checks
- Impact analysis for code changes

#### Zettelkasten (Note-taking) - SECONDARY USE CASE

Useful for personal knowledge bases and research notes, but this is a secondary capability of Engram. For best results managing software projects, use the ALM Cortex type.

```bash
engram init my_notes --type zettelkasten
```

#### Knowledge Base - SECONDARY USE CASE

General-purpose knowledge management, but primarily intended to supplement ALM workflows with additional documentation. For dedicated knowledge management, consider specialized tools.

```bash
engram init wiki --type knowledge
```

### Understanding State Transitions

Engram enforces proper state transitions:

**Issues:** `open` → `in_progress` → `resolved` → `closed`

**Tests:** `not_run` → `running` → `passing` → `failing`

**Requirements:** `draft` → `approved` → `implemented`

To update a state:
```bash
engram update issue.001 --set "context.status=in_progress"
```

---

## Practical Examples

These examples demonstrate real-world workflows. The first example showcases Engram's primary strength: complete Application Lifecycle Management for software projects. Later examples show AI/LLM integration capabilities.

### Example 1: Complete Software Development ALM Workflow (Primary Use Case)

```bash
# 1. Initialize project
engram init webapp --type alm
cd webapp

# 2. Define features
engram new feature "User Authentication"
engram new feature "Payment Processing"

# 3. Add requirements
engram new requirement "User Login" --parent feature.user-auth
engram new requirement "Password Reset" --parent feature.user-auth

# 4. Create tests
engram new test_case "Login Tests" --validates req.user-login
engram new test_case "Password Reset Tests" --validates req.password-reset

# 5. Track issues
engram new issue "Login fails on Safari" --blocks req.user-login --priority 1

# 6. Update test results
engram update test.login-tests --set "context.status=passing"

# 7. Check progress
engram status --type requirement
engram status --type issue

# 8. Verify release readiness
engram release-status
```

### Example 2: Research Note-taking (Secondary Use Case)

```bash
# Initialize knowledge base
engram init research --type zettelkasten
cd research

# Add concepts
engram new concept "Machine Learning Basics"
engram new concept "Neural Networks"

# Add references
engram new reference "Python scikit-learn API"
engram new reference "TensorFlow Documentation"

# Create lessons
engram new lesson "Building Your First ML Model"

# Connect concepts
engram link concept.neural-networks concept.machine-learning parent
engram link lesson.first-model concept.neural-networks next

# Search your notes
engram query --mode text "neural network architecture"
engram query --mode vector "deep learning"
```

### Example 3: Managing a Bug Fix

```bash
# Report the bug
engram new issue "API returns 500 on timeout" --priority 1 --assignee alice

# Link to what it blocks
engram link issue.api-timeout req.data-api blocks

# Trace what it affects
engram trace req.data-api --down

# After fixing, update status
engram update issue.api-timeout --set "context.status=resolved"

# Run affected tests
engram query "link(validates, req.data-api) AND type:test_case"

# Update test results
engram update test.data-api --set "context.status=passing"

# Check release impact
engram release-status
```

### Example 4: Learning a New Technology (Secondary Use Case)

```bash
# Create a learning cortex
engram init learn-zig --type zettelkasten
cd learn-zig

# Add concepts
engram new concept "Zig Basics"
engram new concept "Memory Management in Zig"
engram new concept "Error Handling"

# Add code examples as artifacts
engram link-artifact concept.zig-basics zig --file examples/hello.zig --safe

# Document what you learned
engram show concept.zig-basics
# Edit the file in your editor to add notes

# Connect related concepts
engram link concept.memory-management concept.zig-basics parent

# Review your learning
engram trace concept.zig-basics --down
```

### Example 5: AI-Powered Automated Analysis (LLM Integration)

This example shows how Engram's LLM capabilities enable automated, intelligent workflows.

```bash
# Initialize project with LLM integration
engram init my_project --type alm
cd my_project

# ... create requirements, tests, issues ...

# AI Agent: Identify at-risk requirements
engram query "type:requirement AND (state:blocked OR state:draft)" --json \
  | ai-analyzer --identify-risks > risk_report.json

# AI Agent: Generate test coverage report
engram metrics --json | ai-generate-coverage-report > coverage.html

# AI Agent: Suggest tests for new requirements
engram query "type:requirement AND state:approved AND NOT link(validates, type:test_case)" --json \
  | ai-suggest-tests

# AI Agent: Predict release date based on progress
engram release-status --json | ai-predict-date

# AI Agent: Analyze impact of proposed changes
engram impact req.oauth --json | ai-impact-analysis

# CI/CD Integration: Automated release check
# In your CI pipeline:
engram release-status --json | jq '.ready' || exit 1
```

**Key LLM Features Demonstrated:**
- Structured JSON output for AI parsing
- Semantic understanding through vector search
- Automated report generation
- Natural language queries
- CI/CD pipeline integration

**Benefits:**
- Reduce manual analysis time by 80%
- Catch risks automatically
- Generate comprehensive reports without manual work
- Make data-driven decisions with AI insights

### Example 6: Team Collaboration

```bash
# Assign work
engram new requirement "API Documentation" --assignee bob
engram new test_case "API Docs Test" --validates req.api-docs --assignee carol

# Track blockers
engram status --type issue --filter "state:open AND priority:1"

# What's blocking the release?
engram release-status

# Generate status report
engram metrics --json > team_report.json

# Show work by assignee
engram status --sort-by assignee
```

---

## Tips and Tricks

### 1. Use Descriptive Titles

Good titles make searching easier:

```bash
# ❌ Vague
engram new requirement "Fix auth"

# ✅ Descriptive
engram new requirement "Fix OAuth token refresh on mobile devices"
```

### 2. Connect Everything

The power of Engram is in connections. Always link related items:

```bash
# Link tests to requirements
engram link test.login req.login validates

# Link issues to what they block
engram link issue.bug req.feature blocks

# Link requirements to features
engram link req.feature feature.main parent
```

### 3. Use Tags Wisely

Tags make filtering easy:

```bash
# Create with tags
engram new issue "Database timeout" --tag database --tag critical

# Find by tag
engram query --tag database
engram query "tag:critical AND type:issue"
```

### 4. Keep Neuronas Focused

One concept per Neurona:

```bash
# ❌ Too much in one file
engram new requirement "User Auth, Registration, Password Reset, and Profile"

# ✅ Separate focused items
engram new requirement "User Registration"
engram new requirement "User Login"
engram new requirement "Password Reset"
engram new requirement "User Profile"

# Then link them under a feature
engram new feature "User Account System"
engram link req.user-registration feature.user-account-system parent
engram link req.user-login feature.user-account-system parent
```

### 5. Use Trace for Understanding

When you're confused about dependencies, use trace:

```bash
# See what depends on this
engram trace req.auth --down

# See what this depends on
engram trace req.auth --up

# Full picture
engram trace req.auth --depth 5
```

### 6. Regular Sync

If you manually edit files, sync regularly:

```bash
engram sync
```

### 7. Use Different Query Modes

Each mode has its strengths:

```bash
# Filter: When you know what type you want
engram query --type issue

# Text: When you remember words in the content
engram query --mode text "login timeout"

# Vector: When you want related concepts
engram query --mode vector "authentication"

# Hybrid: Best general search
engram query --mode hybrid "password reset"

# Activation: When exploring connections
engram query --mode activation "critical"
```

### 9. Leverage Status and State

Keep status up to date for better tracking:

```bash
# Mark tests as passing/failing
engram update test.001 --set "context.status=passing"

# Track issue progress
engram update issue.001 --set "context.status=in_progress"

# Requirement state
engram update req.001 --set "context.status=implemented"
```

### 10. Use Release Status

Before releasing, always check:

```bash
engram release-status
```

This shows what's blocking and what's not tested.

### 11. Leverage AI/LLM Capabilities

Engram is built for AI integration. Use these features to supercharge your workflows:

```bash
# Use JSON output for AI agents
engram status --json > project_state.json
# AI can now parse and analyze this

# Use semantic search for AI-like understanding
engram query --mode vector "user authentication problems"

# Let AI suggest related requirements
engram show req.auth --json | ai-find-related

# Automated test generation from requirements
engram query "type:requirement AND state:approved" --json | \
  ai-generate-tests

# AI-powered release prediction
engram release-status --json | ai-predict-release-date

# Natural language queries work great
engram query "what's blocking our OAuth feature?"
engram query "show me all critical bugs in authentication"
```

**Benefits:**
- Reduced manual work through AI automation
- Better insights from semantic analysis
- Faster workflows with automated report generation
- Seamless integration with AI-powered tools

### 12. Experiment with Commands

Most commands have help:

```bash
engram --help
engram query --help
engram new --help
```

---

## Troubleshooting

### "Neurona not found" Error

**Problem:** Engram can't find a Neurona you're trying to reference.

**Solution:**
1. Check the ID is correct
2. List all Neuronas: `engram status`
3. Try searching for it: `engram query --mode text "partial title"`

### "Cortex not found" Error

**Problem:** You're not in a Cortex directory.

**Solution:**
1. Navigate to your Cortex directory
2. Check if `cortex.json` exists: `ls cortex.json`
3. Initialize a new Cortex: `engram init my_cortex`

### Search Not Finding Results

**Problem:** Your searches aren't finding expected results.

**Solutions:**
1. **Sync the index:** `engram sync`
2. **Try different modes:**
   ```bash
   engram query --mode text "your search"
   engram query --mode vector "your search"
   engram query --mode hybrid "your search"
   ```
3. **Check your syntax:** Use quotes for phrases
4. **Verify it exists:** `engram status`

### Connections Not Showing

**Problem:** You linked items but connections don't appear.

**Solution:**
1. **Sync the index:** `engram sync`
2. **Check both directions:** Try tracing from both Neuronas
3. **Verify the link was created:** `engram show <id>` and look for Connections section

### Performance Issues

**Problem:** Commands are slow.

**Solutions:**
1. **Sync the index:** `engram sync --force-rebuild`
2. **Check file count:** Engram handles thousands of files, but extremely large collections may be slower
3. **Use filters:** Limit results with `--limit`

### Can't Edit Files Directly

**Problem:** You want to edit Neurona files in your text editor.

**Solution:**
Engram files are just Markdown files. You can:
1. Edit files directly in `neuronas/` directory
2. Use any text editor (VS Code, Notepad++, etc.)
3. After editing, run `engram sync` to update the index

### Lost Neurona Data

**Problem:** Accidentally deleted important data.

**Solution:**
1. **Check Git history** if using version control
2. **Check system backups**
3. **Prevent in future:** Use `--json` output to create backups:
   ```bash
   engram status --json > backup.json
   ```

---

## Reference Guide

### All Commands

| Command | Purpose |
|---------|---------|
| `init` | Create a new Cortex |
| `new` | Create a new Neurona |
| `show` | View a Neurona |
| `link` | Connect two Neuronas |
| `delete` | Delete a Neurona |
| `sync` | Rebuild graph index |
| `trace` | View dependency chains |
| `status` | List Neuronas with filtering |
| `query` | Search and filter Neuronas |
| `update` | Modify Neurona fields |
| `impact` | Analyze change impact |
| `link-artifact` | Link code files to requirements |
| `release-status` | Check release readiness |
| `metrics` | View project statistics |
| `open-config` | Open configuration file |

### All Neurona Types

| Type | Purpose | Example | ALM Type |
|------|---------|---------|-----------|
| `requirement` | What to build | "Support User Login" | ✅ Yes |
| `test_case` | How to test | "Login Integration Test" | ✅ Yes |
| `issue` | Problems/Bugs | "Login button broken" | ✅ Yes |
| `artifact` | Code/Files | "oauth_client.py" | ✅ Yes |
| `feature` | Group requirements | "Authentication System" | ✅ Yes |
| `concept` | Notes/Ideas | "Async Programming" | No |
| `reference` | Documentation/Facts | "Python asyncio API" | No |
| `lesson` | Tutorials | "Building Async APIs" | No |
| `state_machine` | Workflow steps | "User Logged In State" | No |

### All Connection Types

| Type | Direction | Use Case |
|------|----------|----------|
| `parent` | Hierarchical | Requirement → Feature |
| `validates` | Test → Requirement | Test validates requirement |
| `blocks` | Issue → Requirement | Issue blocks progress |
| `implements` | Code → Requirement | Code implements requirement |
| `relates_to` | General | Related but independent items |
| `child_of` | Reverse of parent | Feature contains requirement |

### All Query Modes

| Mode | How it Works | Best For | AI-Powered |
|------|--------------|----------|-------------|
| `filter` | By type, tags, status | Finding specific types | No |
| `text` | Keyword matching (BM25) | Finding by exact words | No |
| `vector` | Semantic similarity (embeddings) | Finding related concepts | ✅ Yes |
| `hybrid` | Text + vector combined | Best general search | ✅ Yes |
| `activation` | Propagate through connections | Exploring related items | ✅ Yes |

### Common Status Values

| Type | Statuses |
|------|----------|
| Issues | `open`, `in_progress`, `resolved`, `closed` |
| Tests | `not_run`, `running`, `passing`, `failing` |
| Requirements | `draft`, `approved`, `implemented` |

---

## Getting Help

### Built-in Help

```bash
# Show all commands
engram --help

# Get help on a specific command
engram init --help
engram query --help
engram trace --help
```

### Community Resources

- **Documentation:** Check `docs/` folder for technical specifications
- **Examples:** See `demo/demo-cortex/` for example project
- **Source Code:** Available on GitHub

### Keyboard Shortcuts

Engram is a CLI tool, but here are some tips for command-line efficiency:

```bash
# Tab completion (if configured)
engram in<TAB>        # Completes to "init"
engram new re<TAB>     # Shows options: requirement, reference

# Command history (up arrow)
# Press ↑ to see previous commands

# Use aliases in your shell
alias e='engram'
alias es='engram status'
alias eq='engram query'
```

---

## Summary

Engram is a powerful Application Lifecycle Management (ALM) tool designed for software teams. Key takeaways:

1. **Primary Focus is ALM**: Engram is optimized for managing requirements, tests, issues, and code artifacts with full traceability
2. **Start Simple**: Create an ALM Cortex with `--type alm`, add requirements and tests, link them together
3. **Connect Everything**: The power is in traceability - link tests to requirements, issues to blockers, code to requirements
4. **Use ALM Workflows**: Leverage specialized features like impact analysis, release status, and dependency tracing
5. **Keep Status Updated**: Accurate status enables release readiness checks and project metrics
6. **Explore Commands**: Most commands have `--help` for more options

**Engram's Core Strength:**
- Complete traceability from requirements through testing to implementation
- Impact analysis before making code changes
- Release readiness checking with blockers identification
- Fast queries across all project artifacts
- **AI/LLM Ready**: Optimized metadata, JSON output, and semantic search enable seamless AI agent integration

**Secondary Capability:**
- General knowledge management for documentation, notes, and references
- Best used alongside ALM workflows, not as a replacement for dedicated note-taking tools

**AI/LLM Features:**
- Structured metadata optimized for AI consumption
- Token counting and summarization strategies
- LLM response caching for efficiency
- Semantic search powered by vector embeddings
- JSON output for seamless AI agent integration
- Natural language query understanding

Whether you're managing a software project, tracking bugs, ensuring test coverage, or organizing project documentation, Engram provides a flexible, fast way to capture, connect, and manage your project's complete lifecycle.

Happy project managing! 🚀

---

*Engram v0.1.0 - High-performance ALM tool with AI/LLM integration implementing the Neurona Knowledge Protocol*
