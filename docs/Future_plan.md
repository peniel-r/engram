# Implementation Plan: GloVe Compliance & Neural Activation Engine Fixes

## Overview

This plan implements full compliance with NEURONA_OPEN_SPEC.md v0.1.0 by:

1. **Relocating GloVe cache** to `.activations/vectors.bin` (spec-compliant location)
2. **Implementing `engram index` command** to import and cache GloVe vectors
3. **Implementing graph.idx serialization** for O(1) traversal performance
4. **Persisting document vectors** with configurable caching strategies
5. **Fixing Neural Activation Engine** spec violations (decay formula, thresholds, summation cap)
6. **Removing duplicate code** in activation.zig

---

## Architecture Changes

### Directory Structure (Target)

```
Cortex Root/
├── neuronas/              # User-created Neuronas (Git-tracked)
├── .activations/          # System-generated indices (Git-ignored)
│   ├── graph.idx          # NEW: Serialized graph adjacency list
│   ├── vectors.bin        # NEW: Combined GloVe + document vectors
│   └── cache/           # NEW: LLM summaries, activation states
├── assets/               # Static binary files (Git-tracked)
└── data/                 # NEW: External data files (optional, Git-tracked)
    └── glove.6B.300d.txt  # Pre-trained GloVe vectors
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| GloVe auto-detection in `data/` | Users can download vectors to known location, easy migration |
| No backward compatibility with `glove_cache.bin` | Simplifies codebase, encourages spec compliance |
| Configurable persistence via `cortex.json` | Flexibility for different use cases (lazy/eager/on_save) |
| Single `vectors.bin` for GloVe + documents | Simplifies I/O, one file for all embeddings |

---

## Implementation Phases

### Phase 1: Core Infrastructure (Priority 1)

**Objective**: Create foundational structures for persistence layer

#### 1.1 Create Graph Serialization Module
**File**: `src/storage/graph_index.zig` (NEW)

```zig
// Binary format for graph.idx
const GRAPH_HEADER = "ENGRAM_GRAPH";
const VERSION: u8 = 1;

pub const GraphIndex = struct {
    // Header
    header: []const u8 = GRAPH_HEADER,
    version: u8 = VERSION,

    // Data
    node_count: u32,
    edge_count: u32,

    // Serialization methods
    pub fn save(graph: *Graph, path: []const u8) !void;
    pub fn load(allocator: Allocator, path: []const u8) !Graph;
};
```

**Tasks**:
- [ ] Define binary format (header + node table + edge table)
- [ ] Implement `save()` method
- [ ] Implement `load()` method
- [ ] Add tests for roundtrip serialization
- [ ] Handle alignment for 32-bit/64-bit compatibility

#### 1.2 Update GloVe Cache Format
**File**: `src/storage/glove.zig` (MODIFY)

**Changes**:
- Add document vectors section to binary format
- Implement incremental save (append new documents)
- Add auto-detection for GloVe source files

```zig
// Enhanced binary format
const HEADER = "ENGRAM_VEC";
const VERSION: u8 = 2;  // Bump version

pub const VectorIndex = struct {
    // GloVe vectors (word → vector)
    word_vectors: std.StringHashMapUnmanaged([]const f32),

    // Document vectors (neurona_id → vector)
    doc_vectors: std.StringHashMapUnmanaged([]const f32),

    // Metadata
    glove_dimension: usize,
    doc_dimension: usize,
    glove_count: usize,
    doc_count: usize,

    pub fn save(self: *const VectorIndex, path: []const u8) !void;
    pub fn load(allocator: Allocator, path: []const u8) !VectorIndex;
    pub fn saveDocVector(self: *VectorIndex, neurona_id: []const u8, vec: []const f32) !void;
};
```

**Tasks**:
- [ ] Define combined binary format (GloVe section + Documents section)
- [ ] Update `saveCache()` to include document vectors
- [ ] Update `loadCache()` to load both sections
- [ ] Add `saveDocVector()` for incremental updates
- [ ] Implement auto-detection: Check `data/glove*.txt` paths

---

### Phase 2: CLI Commands (Priority 2)

**Objective**: Create user-facing commands for managing indices

#### 2.1 Implement `engram index` Command
**File**: `src/cli/index.zig` (NEW)

```zig
pub const IndexConfig = struct {
    mode: IndexMode,
    glove_path: ?[]const u8,      // Path to GloVe vectors
    force_rebuild: bool,
    verbose: bool,
};

pub const IndexMode = enum {
    glove,      // Import GloVe vectors
    documents,  // Build document vectors
    all,        // Both GloVe + documents
};

pub fn execute(allocator: Allocator, config: IndexConfig) !void;
```

**Tasks**:
- [ ] Create command handler in `main.zig`
- [ ] Implement GloVe vector import from standard paths
- [ ] Add progress bar for large file parsing
- [ ] Implement document vector computation
- [ ] Save to `.activations/vectors.bin`
- [ ] Add help text and examples

**GloVe Auto-detection Logic**:
```
1. Check command-line argument (--glove-path)
2. Check ./data/glove.6B.300d.txt
3. Check ./data/glove.42B.300d.txt
4. Check ./data/glove.840B.300d.txt
5. If not found: prompt user for path
```

#### 2.2 Update `engram sync` Command
**File**: `src/cli/sync.zig` (MODIFY)

**Changes**:
- Call `GraphIndex.save()` after building graph
- Load cached graph if `--rebuild-index` is false

```zig
pub const SyncConfig = struct {
    directory: []const u8 = "neuronas",
    verbose: bool = false,
    rebuild_index: bool = true,
    // NEW:
    skip_vectors: bool = false,  // Don't rebuild vectors.bin
};
```

**Tasks**:
- [ ] Import `GraphIndex` module
- [ ] Add graph serialization to `buildGraphIndex()`
- [ ] Implement graph loading from cache
- [ ] Check `cortex.json` for index strategy
- [ ] Respect `skip_vectors` flag

#### 2.3 Update `engram query` Command
**File**: `src/cli/query.zig` (MODIFY)

**Changes**:
- Load vectors from `.activations/vectors.bin`
- Respect persistence strategy from `cortex.json`

```zig
// Load vectors
const vectors_path = ".activations/vectors.bin";
if (VectorIndex.cacheExists(vectors_path)) {
    try vector_index.load(allocator, vectors_path);
} else {
    // Fallback: compute on-the-fly (slow)
    try computeVectorsOnTheFly(allocator, &vector_index, neuronas, &glove_index);
}
```

**Tasks**:
- [ ] Update path from `glove_cache.bin` to `.activations/vectors.bin`
- [ ] Implement `load()` method in VectorIndex
- [ ] Handle missing vectors gracefully
- [ ] Log cache hit/miss for debugging

---

### Phase 3: Neural Activation Engine Fixes (Priority 1)

**Objective**: Fix critical spec violations in activation.zig

#### 3.1 Remove Duplicate Code
**File**: `src/core/activation.zig` (MODIFY)

**Issue**: Lines 29-233 and 237-409 contain duplicate `NeuralActivation` structs.

**Solution**: Remove second duplicate (lines 237-409), keep first implementation.

**Tasks**:
- [ ] Delete lines 237-409
- [ ] Verify code compiles
- [ ] Run existing tests

#### 3.2 Fix Decay Formula
**File**: `src/core/activation.zig` (MODIFY)

**Spec** (line 182): `Incoming_Signal = Current_Signal * (Link_Weight / 100)`

**Current** (line 384): `propagated = activation * edge_weight * decay_factor`

**Fix**:
```zig
// BEFORE (incorrect)
const edge_weight = @as(f32, @floatFromInt(edge.weight)) / 100.0;
const propagated = activation * edge_weight * self.decay_factor;

// AFTER (correct)
const edge_weight = @as(f32, @floatFromInt(edge.weight)) / 100.0;
const propagated = activation * edge_weight;  // Remove decay_factor
```

**Tasks**:
- [ ] Update line 384 to remove extra `decay_factor`
- [ ] Add comment explaining spec compliance
- [ ] Add unit test for decay formula

#### 3.3 Add Default Weight for Tier 1/2 Links
**File**: `src/core/activation.zig` (MODIFY)

**Spec** (line 182): "If no weight exists (Tier 1/2 link), default to 0.5"

**Implementation**: In `propagateSignal()`, check if edge weight is 0 (unset) and default to 50.

```zig
const edge_weight_val = if (edge.weight == 0) 50 else edge.weight;
const edge_weight = @as(f32, @floatFromInt(edge_weight_val)) / 100.0;
```

**Tasks**:
- [ ] Add default weight logic in `propagateSignal()`
- [ ] Add unit test for default weight
- [ ] Update graph.zig to initialize weights as 0 (optional)

#### 3.4 Add Summation Cap (1.0)
**File**: `src/core/activation.zig` (MODIFY)

**Spec** (line 184): "Summation: If a Neurona receives signals from multiple sources, sum their strengths (capped at 1.0)"

**Implementation**:
```zig
// BEFORE (line 214-219)
const existing = new_activations.getPtr(edge.target_id);
if (existing) |val| {
    val.* += propagated;
} else {
    const key = try allocator.dupe(u8, edge.target_id);
    try new_activations.put(key, propagated);
}

// AFTER
const existing = new_activations.getPtr(edge.target_id);
if (existing) |val| {
    val.* += propagated;
    if (val.* > 1.0) val.* = 1.0;  // Cap at 1.0
} else {
    const key = try allocator.dupe(u8, edge.target_id);
    var value = propagated;
    if (value > 1.0) value = 1.0;  // Cap initial signal
    try new_activations.put(key, value);
}
```

**Tasks**:
- [ ] Add 1.0 cap in both existing and new signal cases
- [ ] Add unit test for summation cap
- [ ] Document spec compliance in comments

#### 3.5 Add 0.2 Threshold
**File**: `src/core/activation.zig` (MODIFY)

**Spec** (line 185): "Stop propagation when signal strength drops below 0.2"

**Implementation**: Add early exit in `propagateSignal()`.

```zig
// BEFORE (line 203)
if (activation <= 0.0) continue;

// AFTER
if (activation < 0.2) continue;  // Threshold: stop weak signals
```

**Tasks**:
- [ ] Change threshold from 0.0 to 0.2
- [ ] Add unit test for threshold
- [ ] Add configuration option for threshold (optional)

#### 3.6 Add 0.1 Noise Filter
**File**: `src/core/activation.zig` (MODIFY)

**Spec** (line 189): "Filter out Neuronas with score < 0.1 (Noise)"

**Implementation**: Update filter in `activate()` method.

```zig
// BEFORE (line 134)
if (activation_score > 0.0) {

// AFTER
if (activation_score >= 0.1) {  // Filter noise: >= 0.1
```

**Tasks**:
- [ ] Update filter threshold from 0.0 to 0.1
- [ ] Add unit test for noise filter
- [ ] Update help text to mention noise filter

#### 3.7 Implement Lazy Loading
**File**: `src/core/activation.zig` (MODIFY)

**Spec** (line 191): "Retrieve full content from `neuronas/` only for top N results (Lazy Loading)"

**Implementation**: Only load Neurona content for top N results.

```zig
// BEFORE (lines 145-152): Returns all results
return results.toOwnedSlice(allocator);

// AFTER: Implement lazy loading
pub fn activate(self: *const NeuralActivation, allocator: Allocator, query: []const u8, query_vec: ?[]const f32, top_n: usize) ![]ActivationResult {
    // ... existing activation logic ...

    // Only return top N results
    if (results.items.len > top_n) {
        results.items.len = top_n;
    }

    return results.toOwnedSlice(allocator);
}
```

**Tasks**:
- [ ] Add `top_n` parameter to `activate()` signature
- [ ] Truncate results to top N
- [ ] Update query.zig to pass `limit` as `top_n`
- [ ] Add unit test for lazy loading

---

### Phase 4: Cortex Integration (Priority 2)

**Objective**: Integrate new features with cortex.json configuration

#### 4.1 Update cortex.json Schema
**File**: `docs/NEURONA_OPEN_SPEC.md` (MODIFY)

**Add to cortex.json indices section**:
```json
{
  "indices": {
    "strategy": "lazy",            // [lazy, eager, on_save]
    "embedding_model": "all-MiniLM-L6-v2",
    "threshold": 0.2,              // NEW: Activation threshold
    "summation_cap": 1.0,         // NEW: Summation cap
    "noise_filter": 0.1,           // NEW: Noise filter
    "top_n": 50                    // NEW: Lazy loading limit
  }
}
```

**Tasks**:
- [ ] Update spec with new index configuration options
- [ ] Document strategies (lazy/eager/on_save)
- [ ] Provide examples

#### 4.2 Implement Strategy Logic
**File**: `src/cli/sync.zig` (MODIFY)

**Implement persistence strategies**:
- **lazy**: Only persist on `engram index` command
- **eager**: Always persist after query
- **on_save**: Persist when Neurona is modified

```zig
pub fn syncStrategy(allocator: Allocator, config: SyncConfig, strategy: []const u8) !void {
    if (std.mem.eql(u8, strategy, "lazy")) {
        // Do nothing: vectors persist only on 'engram index'
    } else if (std.mem.eql(u8, strategy, "eager")) {
        // Always persist document vectors
        try persistAllVectors(allocator, config);
    } else if (std.mem.eql(u8, strategy, "on_save")) {
        // Check for modified Neuronas and persist
        try persistModifiedVectors(allocator, config);
    }
}
```

**Tasks**:
- [ ] Read strategy from cortex.json
- [ ] Implement lazy strategy (no-op)
- [ ] Implement eager strategy (always save)
- [ ] Implement on_save strategy (check timestamps)
- [ ] Add tests for each strategy

---

### Phase 5: Testing & Validation (Priority 1)

**Objective**: Comprehensive test coverage for all changes

#### 5.1 Unit Tests

**New test files**:
- `src/storage/graph_index.zig`: 10 tests
- `src/cli/index.zig`: 8 tests
- `src/core/activation.zig`: 15 tests (additional)

**Test coverage goals**:
- [ ] Graph serialization roundtrip
- [ ] GloVe import from file
- [ ] Document vector persistence
- [ ] Decay formula correctness
- [ ] Threshold behavior
- [ ] Summation cap behavior
- [ ] Noise filter behavior
- [ ] Lazy loading truncation

#### 5.2 Integration Tests

**End-to-end scenarios**:
1. **Fresh installation**:
   - Create cortex
   - Download GloVe vectors
   - Run `engram index`
   - Verify `.activations/vectors.bin` exists
   - Run query, verify cache hit

2. **Incremental updates**:
   - Create new Neurona
   - Run query (lazy: no persistence)
   - Run `engram index` (force persistence)
   - Verify vector added to cache

3. **Migration scenario**:
   - Delete `.activations/`
   - Verify system still works (falls back to recompute)
   - Run `engram index` to rebuild

#### 5.3 Performance Tests

**Benchmarks**:
- [ ] Graph serialization for 10K nodes
- [ ] GloVe loading time (6B vectors)
- [ ] Document vector computation time
- [ ] Query performance with cache vs. without

---

## File-by-File Changes

### Files to Create

| File | Lines | Purpose |
|------|--------|---------|
| `src/storage/graph_index.zig` | ~300 | Graph serialization/deserialization |
| `src/cli/index.zig` | ~200 | `engram index` command |

### Files to Modify

| File | Changes | Impact |
|------|----------|--------|
| `src/core/activation.zig` | Remove duplicate, fix 6 spec violations | Critical |
| `src/storage/glove.zig` | Add document vectors, update binary format | High |
| `src/cli/sync.zig` | Add graph serialization, strategy support | High |
| `src/cli/query.zig` | Update vectors path, lazy loading | Medium |
| `src/main.zig` | Add `index` command | Low |
| `.gitignore` | No changes (already correct) | N/A |
| `docs/NEURONA_OPEN_SPEC.md` | Document new config options | Documentation |

### Files to Delete

| File | Reason |
|------|--------|
| `src/core/activation.zig` (lines 237-409) | Duplicate code |

---

## Implementation Order

### Week 1: Core Infrastructure
- Day 1-2: Create `graph_index.zig` module
- Day 3-4: Update `glove.zig` with document vectors
- Day 5: Create `index.zig` CLI command

### Week 2: Activation Fixes
- Day 1: Remove duplicate code, fix decay formula
- Day 2: Add default weights, summation cap
- Day 3: Add threshold, noise filter
- Day 4: Implement lazy loading
- Day 5: Testing activation fixes

### Week 3: Integration & Testing
- Day 1-2: Update `sync.zig` and `query.zig`
- Day 3: Update cortex.json schema
- Day 4-5: Integration and performance testing

---

## Risk Assessment

### High Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Binary format incompatibility** | Existing caches break | Version field, migration path |
| **Large GloVe files memory** | Out of memory errors | Stream parsing, progress monitoring |
| **Performance regression** | Slower queries than before | Benchmark before/after, optimize |

### Medium Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **User confusion with new command** | Users don't know to run `engram index` | Clear error messages, add to init help |
| **Delete .activations/ breaks system** | Loss of cached data | Graceful fallback to recompute, add warning |

### Low Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Breaking backward compatibility** | Old users lose cache | Document in changelog, provide migration guide |

---

## Rollback Plan

### If Implementation Fails

1. **Revert code changes**:
   ```bash
   git reset --hard HEAD~5
   git clean -fd
   ```

2. **Restore user data**:
   - Delete `.activations/` directory
   - Users must re-run `engram index` (old command won't exist)

3. **Communicate**:
   - Issue GitHub issue documenting failure
   - Provide manual workaround (keep using old cache location)

### If Only Partial Success

| Scenario | Action |
|----------|--------|
| Graph serialization fails | Keep in-memory graph, document TODO |
| GloVe import fails | Fall back to manual copy, document in README |
| Activation fixes fail | Prioritize decay formula and threshold, defer lazy loading |

---

## Success Criteria

### Must Have (MVP)

- [ ] `.activations/graph.idx` created and persisted by `engram sync`
- [ ] `.activations/vectors.bin` created and persisted by `engram index`
- [ ] `engram index` command works with GloVe auto-detection
- [ ] Decay formula matches spec (no extra decay_factor)
- [ ] Threshold of 0.2 implemented
- [ ] Summation cap of 1.0 implemented
- [ ] Noise filter of 0.1 implemented
- [ ] All unit tests pass

### Should Have (v1.0)

- [ ] Lazy loading implemented
- [ ] Configurable persistence strategies (lazy/eager/on_save)
- [ ] Integration tests pass
- [ ] Performance benchmarks within 10% of baseline

### Nice to Have (v1.1)

- [ ] Progress bars for long operations
- [ ] Incremental vector updates (saveDocVector)
- [ ] Multiple GloVe model support

---

## Dependencies

### External Tools
- **GloVe vectors**: Users download from Stanford NLP (https://nlp.stanford.edu/projects/glove/)
- **No additional dependencies**: Pure Zig implementation

### Internal Dependencies
- `src/storage/filesystem.zig`: For Neurona I/O
- `src/core/graph.zig`: For graph structure
- `src/core/neurona.zig`: For Neurona data structures
- `src/utils/yaml.zig`: For cortex.json parsing

---

## Documentation Requirements

### User Documentation

1. **README.md updates**:
   - Add `.activations/` architecture diagram
   - Document `engram index` command
   - Add troubleshooting section

2. **Spec updates**:
   - Document new cortex.json options
   - Update index strategy examples
   - Add migration guide from old format

### Developer Documentation

1. **Code comments**:
   - Binary format headers
   - Spec compliance references
   - Algorithm explanations

2. **Architecture docs** (if exists):
   - Update architecture diagram
   - Document persistence layer

---

## Post-Implementation Checklist

- [ ] All code compiles: `zig build`
- [ ] All tests pass: `zig test`
- [ ] No memory leaks: run with valgrind or equivalent
- [ ] Documentation updated
- [ ] Changelog updated
- [ ] Git commit ready
- [ ] PR description includes:
  - Overview of changes
  - Breaking changes noted
  - Migration guide
  - Performance benchmarks
- [ ] Code review completed
- [ ] CI/CD pipeline passes

---

## Open Questions

1. **GloVe auto-detection**: Which specific paths should we check? (proposed: `data/glove.6B.300d.txt`, `data/glove.42B.300d.txt`, `data/glove.840B.300d.txt`)

2. **Error handling**: What should happen if `engram index` is run but no GloVe file is found? (proposed: Prompt user with URL to download)

3. **Cache invalidation**: When should cached document vectors be invalidated? (proposed: Check file modification timestamp, recompute if changed)

4. **Performance targets**: What's the acceptable query latency with vs. without cache? (proposed: 50ms threshold for 10K Neuronas per spec)

5. **Testing data**: Should we include sample GloVe vectors in tests or mock them? (proposed: Mock with small test vocabulary)

---

## Estimated Effort

| Phase | Tasks | Estimated Time |
|-------|--------|----------------|
| Phase 1: Core Infrastructure | 3 files | 3-4 days |
| Phase 2: CLI Commands | 3 files | 2-3 days |
| Phase 3: Activation Fixes | 1 file, 6 changes | 2-3 days |
| Phase 4: Cortex Integration | 2 files | 1-2 days |
| Phase 5: Testing | Unit + integration | 3-4 days |
| **Total** | **9 files** | **11-16 days** |

---

**Ready to proceed?** Let me know if you'd like any clarifications or modifications to this plan before implementation begins.
