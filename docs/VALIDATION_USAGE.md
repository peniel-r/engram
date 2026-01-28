# Engram Compliance Validator

## Overview

The Engram Compliance Validator is a command-line tool that checks your Engram implementation against the official specifications (`NEURONA_OPEN_SPEC.md` and `spec.md`). It generates a detailed report with scores for each category and identifies critical issues that need to be addressed.

## Building

```bash
zig build validate
```

This creates the `validate_compliance` executable in `zig-out/bin/`.

## Usage

### Basic Usage

Run validation from the project root directory (where `neuronas/` and other Cortex files should exist):

```bash
./zig-out/bin/validate_compliance
```

### Options

| Option | Short | Description |
|---------|--------|-------------|
| `--verbose` | `-v` | Show detailed check output with individual check results |
| `--strict` | `-s` | Exit with error code 1 if compliance score is below 100% |

### Examples

```bash
# Basic validation
./zig-out/bin/validate_compliance

# Detailed output
./zig-out/bin/validate_compliance --verbose

# Strict mode (for CI/CD)
./zig-out/bin/validate_compliance --strict
```

## Understanding the Report

### Overall Compliance Score

| Range | Status | Emoji |
|--------|---------|--------|
| 90%+ | Excellent | 🟢 |
| 70-89% | Good | 🟡 |
| < 70% | Needs Work | 🔴 |

### Category Breakdown

The validator checks 7 major categories:

1. **Core Architecture** (100%)
   - Technology Stack: Zig implementation
   - Storage: Plain text (Markdown + YAML)
   - Static Linking: Single binary, no dependencies

2. **File Structure** (75% - current)
   - `cortex.json` (DNA) - Configuration file
   - `neuronas/` (Soma) - Neurona files
   - `.activations/` (Memory) - System indices
   - `assets/` (Matter) - Static files (optional)
   - `README.md` - Documentation

3. **Data Model** (100%)
   - Tier 1: Essential fields (id, title, tags)
   - Tier 2: Standard fields (type, connections, language)
   - Tier 3: Advanced fields (hash, _llm, context)
   - Neurona Flavors: 9 types (concept, reference, artifact, state_machine, lesson, requirement, test_case, issue, feature)

4. **CLI Commands** (92.3% - current)
   - Core: init, new, show, link, sync, delete, trace, status, query
   - Engineering: update, impact, link-artifact, release-status
   - Phase 3: run (optional)

5. **Persistence** (0% - CRITICAL)
   - `.activations/graph.idx` - Persistent graph adjacency list
   - `.activations/vectors.bin` - Persistent vector embeddings
   - `.activations/cache/` - LLM summaries and token counts

6. **Query System** (75% - current)
   - BM25 text search (`src/storage/tfidf.zig`)
   - Vector search (`src/storage/vectors.zig`)
   - Neural Activation (`src/core/activation.zig`)
   - EQL Query Language (`src/utils/eql_parser.zig`)

7. **Performance** (0% - CRITICAL)
   - Benchmark module (`src/benchmark.zig` or `tests/benchmarks.zig`)
   - Performance threshold validation (10ms rule)

### Critical Issues

Critical issues are displayed separately and indicate:

- **Persistence Issues**: O(1) traversal unavailable between runs, semantic search unavailable, LLM cache not working
- **Performance Issues**: No benchmarking, cannot verify 10ms rule compliance

### Recommendations

The validator provides actionable recommendations based on identified gaps. These typically include:

- Implementing missing features
- Adding persistence layers
- Creating benchmark tests
- Improving compliance with specifications

## Current Status

As of the last validation run:

| Category | Score | Status |
|----------|-------|--------|
| Core Architecture | 100.0% | 🟢 Excellent |
| File Structure | 75.0% | 🟡 Good |
| Data Model | 100.0% | 🟢 Excellent |
| CLI Commands | 92.3% | 🟡 Good |
| Persistence | 0.0% | 🔴 CRITICAL |
| Query System | 75.0% | 🟡 Good |
| Performance | 0.0% | 🔴 CRITICAL |

**Overall Compliance: 63.2% (🔴 Needs Work)**

## Integration with Development Workflow

### Continuous Validation

For CI/CD pipelines:

```yaml
# Example: GitHub Actions
- name: Validate Compliance
  run: zig build validate && ./zig-out/bin/validate_compliance --strict
```

### Local Development

```bash
# Run before committing
./zig-out/bin/validate_compliance --verbose

# Check compliance after major changes
zig build validate && ./zig-out/bin/validate_compliance
```

## Notes

- The validator runs from the current directory
- Ensure you're running from a Cortex directory root (where `neuronas/` and `.activations/` should exist)
- The `.activations/` directory should be gitignored (see `.gitignore`)
- Missing optional files (like `assets/`) don't heavily impact the score

## See Also

- [COMPLIANCE_PLAN.md](./COMPLIANCE_PLAN.md) - Detailed plan to improve compliance
- [NEURONA_OPEN_SPEC.md](./docs/NEURONA_OPEN_SPEC.md) - Official specifications
- [spec.md](./docs/spec.md) - Neurona System specification
