# Configuration Enhancement Plan for Engram

**Version**: 0.1.0  
**Date**: 2026-01-31  
**Status**: Draft  

---

## Overview

This document outlines potential configuration options that could be added to Engram's `config.yaml` file. Currently, the configuration only supports two basic settings (`editor` and `default-artifact-type`). This plan proposes comprehensive configuration categories to enhance Engram's functionality, usability, and customization.

---

## Current Configuration

The existing `config.yaml` structure:

```yaml
# Engram Configuration File
# Configuration settings for the Engram application

editor: hx
default-artifact-type: feature
```

---

## Proposed Configuration Categories

### 1. Search & Query Configuration

Controls how search and query operations behave.

```yaml
search:
  default-mode: hybrid        # Options: filter, text, vector, hybrid, activation
  max-results: 20             # Maximum number of results to return
  include-context: true       # Include surrounding context in results
  context-depth: 2            # Depth of context to include (lines/nodes)
```

**Rationale**: Essential for user experience, allows users to customize search behavior based on their needs and project size.

### 2. Indexing & Performance

Controls how indices are built and managed.

```yaml
indexing:
  strategy: lazy               # Options: lazy, eager, on-demand
  auto-sync: true             # Automatically sync indices after changes
  rebuild-on-startup: false   # Rebuild all indices on startup
  thread-count: 0             # Number of threads for indexing (0 = auto-detect)
  cache-size: 100             # Index cache size in MB
```

**Rationale**: Critical for performance in large projects, allows tuning based on system resources.

### 3. LLM & Embedding Settings

Configures AI/ML integration features.

```yaml
llm:
  enabled: true
  model: text-embedding-ada-002
  endpoint: https://api.openai.com/v1
  cache-embeddings: true
  cache-ttl: 86400            # Cache time-to-live in seconds (24 hours)
  timeout: 30                 # Request timeout in seconds
  max-retries: 3              # Maximum retry attempts for failed requests
```

**Rationale**: Enables customization of AI features, supports alternative endpoints and models.

### 4. Display & Output

Controls how information is presented to users.

```yaml
display:
  color-output: true          # Enable ANSI color codes
  output-format: human        # Options: human, json, markdown
  show-ids: true              # Display artifact IDs
  show-timestamps: false      # Show timestamps in output
  truncate-length: 100        # Maximum line length before truncation
  pager: less                 # Pager for long output (e.g., less, more)
```

**Rationale**: Improves user experience, supports different workflows (human vs programmatic).

### 5. Git Integration

Controls integration with version control.

```yaml
git:
  auto-commit: false          # Automatically commit after changes
  commit-template: "engram: {action} {artifact_type} '{title}'"
  require-commit-message: true
  track-neuronas: true        # Track all neuronas in git
```

**Rationale**: Streamlines workflow, ensures proper version control practices.

### 6. Validation & State Management

Enforces data integrity and state transitions.

```yaml
validation:
  enforce-state-transitions: true    # Prevent invalid state changes
  require-mandatory-links: true      # Enforce required link types
  validate-frontmatter: true         # Validate YAML frontmatter
  strict-mode: false                 # Fail on any validation errors
```

**Rationale**: Ensures data integrity, prevents invalid states that could break functionality.

### 7. CLI Behavior

Controls command-line interface behavior.

```yaml
cli:
  confirm-destructive: true   # Confirm before destructive operations
  auto-save: false            # Automatically save changes
  save-interval: 300          # Auto-save interval in seconds
  show-progress: true         # Show progress bars for long operations
  verbose: false              # Enable verbose output
  debug: false                # Enable debug logging
```

**Rationale**: Enhances user control, supports different workflow preferences.

### 8. Artifact Type Defaults

Sets default values for different artifact types.

```yaml
artifact-defaults:
  requirement:
    priority: 2
    verification-method: test
  issue:
    status: open
    priority: 3
  test_case:
    status: not_run
  feature:
    status: planned
```

**Rationale**: Improves consistency, reduces repetitive input.

### 9. Workspace Settings

Configures project workspace structure.

```yaml
workspace:
  cortex-path: .              # Relative path to cortex.json
  neuronas-path: project/neuronas
  activations-path: .activations
  auto-init: false            # Initialize cortex automatically if missing
```

**Rationale**: Supports custom project structures, improves flexibility.

### 10. Notifications & Alerts

Configures alerts and notifications.

```yaml
notifications:
  alert-on-blocked: true      # Alert when items are blocked
  alert-on-overdue: true      # Alert for overdue items
  alert-on-state-change: false
  show-summary-on-sync: true  # Show summary after sync operation
```

**Rationale**: Keeps users informed about important events.

### 11. Query Language (EQL) Settings

Configures the Engram Query Language behavior.

```yaml
eql:
  case-sensitive: false
  wildcards-enabled: true
  regex-support: true
  max-query-time: 5000        # Maximum query time in milliseconds
```

**Rationale**: Controls query behavior, prevents runaway queries.

### 12. Performance Tuning

Fine-tunes performance parameters.

```yaml
performance:
  cold-start-timeout: 50      # Target cold start time in ms
  traversal-timeout: 10       # Target graph traversal time in ms
  index-build-timeout: 1000   # Target index build time in ms
  enable-metrics: false       # Enable performance metrics collection
```

**Rationale**: Allows optimization for different use cases and system capabilities.

### 13. Templates

Configures template system.

```yaml
templates:
  enable: true
  custom-path: templates/
  default-template: minimal   # Default template to use
```

**Rationale**: Supports customization, improves consistency across artifacts.

### 14. Network Settings

Configures network-related operations.

```yaml
network:
  timeout: 30                 # Default timeout in seconds
  proxy:                      # Optional proxy server
  max-connections: 10         # Maximum concurrent connections
  retry-delay: 1000           # Delay between retries in ms
```

**Rationale**: Essential for remote services and API integrations.

### 15. Advanced/Experimental

Controls experimental features.

```yaml
experimental:
  features: []                # List of enabled experimental features
  enable-activation-propagation: false
  enable-neural-search-optimization: false
```

**Rationale**: Allows testing new features without affecting stability.

---

## Implementation Priority

### Phase 1: Core Functionality (High Priority)

1. **Display & Output** - Essential for user experience
2. **CLI Behavior** - Controls basic workflow
3. **Workspace Settings** - Critical for project organization
4. **Search & Query Configuration** - Improves usability

**Estimated Effort**: 2-3 days

### Phase 2: Enhanced Features (Medium Priority)

5. **Indexing & Performance** - Important for large projects
6. **Validation & State Management** - Ensures data integrity
7. **Artifact Type Defaults** - Improves consistency
8. **Git Integration** - Streamlines workflow
9. **Notifications & Alerts** - Enhances user awareness

**Estimated Effort**: 3-4 days

### Phase 3: Advanced Features (Low Priority)

10. **LLM & Embedding Settings** - For AI features
11. **Templates** - For customization
12. **EQL Settings** - For advanced querying
13. **Performance Tuning** - For optimization
14. **Network Settings** - For remote services
15. **Advanced/Experimental** - For testing new features

**Estimated Effort**: 4-5 days

---

## Implementation Considerations

### Backward Compatibility

- All new configuration options should have sensible defaults
- Existing configurations should continue to work without modification
- Provide migration guide if breaking changes are necessary

### Validation

- Validate configuration on load
- Provide clear error messages for invalid values
- Support configuration validation command

### Documentation

- Document each configuration option with examples
- Provide sample configuration files
- Include configuration reference in user manual

### Testing

- Unit tests for configuration parsing
- Integration tests for configuration effects
- Edge case testing (missing config, invalid values, etc.)

---

## Example Complete Configuration

```yaml
# Engram Configuration File

# Editor settings
editor: hx
default-artifact-type: feature

# Search configuration
search:
  default-mode: hybrid
  max-results: 20
  include-context: true
  context-depth: 2

# Display settings
display:
  color-output: true
  output-format: human
  show-ids: true
  show-timestamps: false
  truncate-length: 100
  pager: less

# CLI behavior
cli:
  confirm-destructive: true
  auto-save: false
  save-interval: 300
  show-progress: true
  verbose: false
  debug: false

# Workspace settings
workspace:
  cortex-path: .
  neuronas-path: project/neuronas
  activations-path: .activations
  auto-init: false

# Validation
validation:
  enforce-state-transitions: true
  require-mandatory-links: true
  validate-frontmatter: true
  strict-mode: false

# Artifact defaults
artifact-defaults:
  requirement:
    priority: 2
    verification-method: test
  issue:
    status: open
    priority: 3

# Git integration
git:
  auto-commit: false
  commit-template: "engram: {action} {artifact_type} '{title}'"
  require-commit-message: true
  track-neuronas: true

# Indexing (optional - for large projects)
indexing:
  strategy: lazy
  auto-sync: true
  rebuild-on-startup: false
  thread-count: 0
  cache-size: 100

# LLM settings (optional - for AI features)
llm:
  enabled: true
  model: text-embedding-ada-002
  endpoint: https://api.openai.com/v1
  cache-embeddings: true
  cache-ttl: 86400
  timeout: 30
  max-retries: 3
```

---

## Next Steps

1. Review and approve proposed configuration categories
2. Prioritize which categories to implement first
3. Update Config struct in `src/utils/config.zig` to include new fields
4. Implement configuration parsing for new options
5. Add configuration validation
6. Update documentation and examples
7. Add tests for new configuration options

---

**Status**: Ready for review and implementation planning