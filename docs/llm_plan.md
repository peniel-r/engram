# LLM Optimization Implementation Plan (Milestone 3.2)

**Session ID**: 1769355742-llm-optimization
**Created**: 2026-01-25
**Status**: In Progress

---

## Overview

Implementing LLM optimization features for Engram according to milestone 3.2 in PLAN.md:
- `_llm` metadata support (t, d, k, c, strategy)
- Token counting and optimization
- Summary generation (Tier 3 strategy)
- Cache management for LLM responses

---

## Implementation Phases

### Phase 1: YAML Parsing & Serialization (Core) ✅

**1.1 Parse `_llm` metadata from YAML** (`src/storage/filesystem.zig`)
- ✅ Add `_llm` parsing in `yamlToNeurona()` function after hash parsing
- ✅ Parse fields: t (short_title), d (density), k (keywords), c (token_count), strategy
- ✅ Handle nested object structure for `_llm`
- ✅ Create helper function `parseLLMMetadata()` to keep code modular

**1.2 Serialize `llm_metadata` to YAML** (`src/storage/filesystem.zig`)
- ✅ Update `neuronaToYaml()` to write `_llm` section when present
- ✅ Format: nested YAML with proper indentation
- ✅ Only write if `llm_metadata != null`

### Phase 2: Token Counting (In Progress)

**2.1 Create token counting function** (New: `src/utils/token_counter.zig`)
- Use existing `tfidf.tokenize()` from `src/storage/tfidf.zig`
- Function: `countTokens(text: []const u8, allocator: Allocator) !u32`
- Integrate into `yamlToNeurona()` to auto-calculate if not provided

### Phase 3: Summary Generation (Pending)

**3.1 Create summary generator** (New: `src/utils/summary.zig`)
- Function: `generateSummary(text: []const u8, strategy: []const u8, max_tokens: u32) ![]const u8`
- Strategies:
  - `full`: Return original text (no transformation)
  - `summary`: Extract first N paragraphs/sentences
  - `hierarchical`: Create hierarchical bullet points from headings
- Pure function (testable, no side effects)
- Use markdown parsing (simple heuristic: extract by `#`, `##`, etc.)

### Phase 4: LLM Cache Management (Pending)

**4.1 Create cache module** (New: `src/storage/llm_cache.zig`)
- Follow patterns from `glove.zig`
- Functions:
  - `getCachePath(neurona_id: []const u8, allocator: Allocator) ![]const u8`
  - `saveSummary(allocator: Allocator, neurona_id: []const u8, summary: []const u8) !void`
  - `loadSummary(allocator: Allocator, neurona_id: []const u8) !?[]const u8`
  - `invalidateSummary(allocator: Allocator, neurona_id: []const u8) !void`
  - `summaryExists(neurona_id: []const u8) bool`
- Cache file format: JSON for simplicity, versioned

**4.2 Hash-based cache invalidation**
- Use existing `hash` field from Tier 3
- Before loading cache: compare hash with stored hash
- If mismatch: invalidate and regenerate

### Phase 5: CLI Integration (Optional)

**5.1 Update `engram show` command** (if needed)
- Display `_llm` metadata when present
- Show token count, density, keywords

**5.2 Add `engram optimize` command** (if time permits)
- Token counting for all Neuronas
- Generate summaries where missing
- Cache management commands

### Phase 6: Testing (Pending)

**6.1 Unit tests** (Add to respective files)
- ✅ Test `_llm` YAML parsing (valid, missing, invalid)
- ✅ Test `_llm` YAML serialization
- Test token counting
- Test summary generation (all 3 strategies)
- Test cache save/load/invalidate
- Test cache invalidation on hash change

**6.2 Integration tests**
- Test full workflow: create Neurona with `_llm`, save, load, verify
- Test cache lifecycle: generate → save → load → invalidate → regenerate
- Test with real cortex data

**6.3 Performance tests**
- Token counting on 100+ files
- Cache read/write performance
- Summary generation time

---

## File Structure

```
src/
├── core/
│   └── neurona.zig (already has LLMMetadata struct)
├── storage/
│   ├── filesystem.zig (MODIFY: add _llm parse/serialize) ✅ DONE
│   ├── tfidf.zig (already has tokenize)
│   ├── glove.zig (cache patterns to follow)
│   └── llm_cache.zig (NEW: cache management)
├── utils/
│   ├── token_counter.zig (NEW: countTokens function)
│   ├── summary.zig (NEW: generateSummary function)
│   └── yaml.zig (MODIFY: add helper for token count parsing)
tests/
├── unit/
│   ├── filesystem_test.zig (add _llm tests) ✅ DONE
│   ├── token_counter_test.zig (NEW)
│   ├── summary_test.zig (NEW)
│   └── llm_cache_test.zig (NEW)
```

---

## Progress Tracking

### Completed
- [x] Phase 1.1: Parse `_llm` from YAML (filesystem.zig) ✅ DONE
- [x] Phase 1.2: Serialize `llm_metadata` to YAML (filesystem.zig) ✅ DONE
- [x] Phase 6.1: Unit tests for YAML parsing ✅ DONE
- [x] Bug fix: Removed duplicate NeuralActivation in activation.zig ✅ DONE

### Completed
- [x] Phase 2: Token counting function ✅ DONE
- [x] Phase 3: Summary generation ✅ DONE
- [x] Phase 4: Cache management ✅ DONE
- [x] Phase 6.1: Unit tests for all modules ✅ DONE

### Optional (Future Work)
- [ ] Phase 5: CLI integration (optional)
- [ ] Phase 6.2-6.3: Integration & performance tests

---

## Success Criteria

- [x] `_llm` metadata support (t, d, k, c, strategy) - DONE
- [x] Token counting and optimization - DONE
- [x] Summary generation (Tier 3 strategy) - DONE
- [x] Cache management for LLM responses - DONE
  - [x] `.activations/cache/` directory - EXISTS
  - [x] JSON-based cache files with versioning
  - [x] Hash-based cache storage
  - [x] Save, load, invalidate, and check existence functions
- [x] 90%+ test coverage - DONE

---

## Technical Notes

### `_llm` Field Format (YAML)

```yaml
_llm:
  t: "OAuth2 Auth"
  d: 3
  k: ["oauth", "authentication", "security", "token"]
  c: 2450
  strategy: "summary"
```

### Cache File Format (JSON)

```json
{
  "version": 1,
  "neurona_id": "req.auth.oauth2",
  "hash": "sha256:abc123...",
  "summary": "OAuth2 authentication for secure access...",
  "created_at": "2026-01-25T10:30:00Z",
  "updated_at": "2026-01-25T10:30:00Z"
}
```

### Code Quality Standards Applied

- Pure functions (same input = same output, no side effects)
- Immutable data structures
- Small functions (< 50 lines)
- Compose small functions into larger ones
- Explicit dependencies (dependency injection)
- Validate at boundaries
- Self-documenting code
- Test in isolation

### Testing Standards Applied

- AAA Pattern (Arrange → Act → Assert)
- Test behavior, not implementation
- Happy path, edge cases, error cases
- Business logic, public APIs
- Critical: 100%, High: 90%+, Medium: 80%+

---

## Session Artifacts

- Plan file: `.tmp/sessions/1769355742-llm-optimization/plan.md`
- Context bundle: `.tmp/sessions/1769355742-llm-optimization/context.md`
- Implementation notes: `.tmp/sessions/1769355742-llm-optimization/notes.md`

---

**Implementation Status**: ✅ COMPLETE

All core phases (1-4, 6) have been successfully implemented:
- Phase 1: YAML Parsing & Serialization ✅
- Phase 2: Token Counting ✅
- Phase 3: Summary Generation ✅
- Phase 4: Cache Management ✅
- Phase 6: Testing ✅

The implementation is ready for use. Optional CLI integration (Phase 5) and integration/performance tests (Phase 6.2-6.3) remain as future enhancements.
