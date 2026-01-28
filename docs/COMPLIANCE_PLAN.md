# Engram Compliance Improvement Plan

## Executive Summary

**Current Overall Compliance: 63.2% (NEEDS WORK)**

This document outlines a detailed plan to address all critical, medium, and low priority compliance issues identified by the validator. The plan is organized by priority and provides estimated effort for each task.

---

## Phase 1: HIGH PRIORITY (Critical Issues) - Week 1

**Goal**: Achieve 90%+ overall compliance by addressing critical persistence and performance issues.

### Issue 1.1: Persist Graph Index to `.activations/graph.idx`

**Status**: ❌ Not Implemented  
**Impact**: O(1) traversal unavailable between runs; graph rebuilt every `engram sync`  
**Effort**: 4-6 hours  
**Priority**: CRITICAL

#### Implementation Steps:

1. **Create `src/storage/index.zig`** - New persistence module
   - `GraphIndex` struct to hold serialized graph data
   - `saveGraph(allocator, graph, path)` - Serialize adjacency list to binary
   - `loadGraph(allocator, path)` - Deserialize and reconstruct graph

2. **Binary Format Design**:
   ```
   [header: 8 bytes magic "ENGI" + 4 bytes version + 8 bytes node_count]
   [nodes: node_count * (id_len: u16 + out_degree: u16 + edge_data)]
   [edges: for each node, (target_id_len: u16 + weight: u8)]
   ```

3. **Add serialization to `src/core/graph.zig`**:
   - `fn serialize(self: *Graph, allocator: Allocator) ![]u8`
   - `fn deserialize(data: []const u8, allocator: Allocator) !Graph`

4. **Update `src/cli/sync.zig`**:
   - After building graph, call `index.saveGraph()`
   - On load, check if `.activations/graph.idx` exists
   - If exists, load instead of rebuilding
   - Add `--force-rebuild` flag to ignore cache

5. **Integration Test**:
   - Create test Cortex
   - Run `engram sync` to build graph
   - Run `engram sync` again to load from cache
   - Verify same results

**Success Criteria**:
- ✅ `.activations/graph.idx` created after `engram sync`
- ✅ `engram sync` loads from cache on second run
- ✅ Graph traversal < 1ms (depth 1)

---

### Issue 1.2: Persist Vector Index to `.activations/vectors.bin`

**Status**: ❌ Not Implemented  
**Impact**: Semantic search unavailable between runs; vectors recomputed every sync  
**Effort**: 6-8 hours  
**Priority**: CRITICAL

#### Implementation Steps:

1. **Extend `src/storage/vectors.zig`**:
   - `saveVectors(allocator, index, path)` - Binary serialization
   - `loadVectors(allocator, path)` - Binary deserialization

2. **Binary Format Design**:
   ```
   [header: 8 bytes magic "VECT" + 4 bytes version + 8 bytes dim + 8 bytes count]
   [vectors: count * dim * f32]
   [index_map: for each vector, (id_len: u16 + offset: u64)]
   ```

3. **Add Metadata**:
   - Timestamp for cache validation
   - CRC32 checksum for integrity
   - Dimension count and vector count

4. **Update `src/cli/sync.zig`**:
   - After building vectors, save to `.activations/vectors.bin`
   - Check timestamp for staleness
   - Load from cache if available and not stale

5. **Cache Validation**:
   - Compare file modification times
   - Rebuild if `.activations/vectors.bin` older than any Neurona file
   - Verify CRC checksum on load

**Success Criteria**:
- ✅ `.activations/vectors.bin` created with embeddings
- ✅ Vector search loads from cache
- ✅ Cache invalidated when Neuronas modified
- ✅ Semantic search < 10ms for 1000 Neuronas

---

### Issue 1.3: Implement LLM Cache to `.activations/cache/`

**Status**: ❌ Not Implemented  
**Impact**: Repeated LLM calls waste resources and time; summaries not cached  
**Effort**: 4-5 hours  
**Priority**: CRITICAL

#### Implementation Steps:

1. **Complete `src/storage/llm_cache.zig`**:
   - `LLMCache` struct with HashMap for summaries
   - `get(key)` - Retrieve cached summary
   - `set(key, summary)` - Store summary
   - `saveToDisk(path)` - Persist cache
   - `loadFromDisk(path)` - Restore cache

2. **Cache Key Design**:
   - Hash of: `neurona_id + strategy + content_hash`
   - Content hash of Neurona body to detect changes
   - Includes timestamp for TTL expiration

3. **Cache Storage Format**:
   ```
   .activations/cache/
   ├── summaries.cache  (JSON: {key: summary})
   ├── tokens.cache   (JSON: {key: token_count})
   └── .gitignore    (Ignore all cache files)
   ```

4. **Integrate with `src/utils/summary.zig`**:
   - Before calling LLM, check cache
   - After LLM response, store in cache
   - Use 24-hour TTL (configurable)

5. **Integrate with `src/utils/token_counter.zig`**:
   - Cache token counts per Neurona
   - Recount only if file modified

6. **Cache Cleanup**:
   - On `engram sync`, remove entries older than TTL
   - Remove entries for deleted Neuronas

**Success Criteria**:
- ✅ `.activations/cache/` directory created
- ✅ Summaries cached for 24 hours
- ✅ Token counts cached
- ✅ Cache cleanup on `engram sync`
- ✅ Reduced LLM API calls

---

### Issue 1.4: Performance Benchmarking (10ms Rule Validation)

**Status**: ❌ Not Implemented  
**Impact**: Cannot validate spec's performance constraints; no timing reports  
**Effort**: 6-8 hours  
**Priority**: CRITICAL

#### Implementation Steps:

1. **Create `src/benchmark.zig`** - New benchmark module:
   ```zig
   pub const Timer = struct {
       start_time: i64,
       fn start() Timer,
       fn end(self: Timer) f64,  // Returns milliseconds
   };

   pub const Benchmark = struct {
       name: []const u8,
       ops: []BenchmarkOp,
       fn run(self: Benchmark) !BenchmarkReport,
   };

   pub const BenchmarkReport = struct {
       operation: []const u8,
       iterations: usize,
       total_ms: f64,
       avg_ms: f64,
       min_ms: f64,
       max_ms: f64,
       passes_10ms_rule: bool,
   };
   ```

2. **Add Performance Monitoring to `src/cli/sync.zig`**:
   - Measure cold start (parse `cortex.json`) - target: < 50ms
   - Measure graph build time - target: < 1000ms for 10K files
   - Measure traversal time (depth 1, 3, 5) - target: < 10ms
   - Print performance summary with ✓/✗ indicators

3. **Extend `tests/benchmarks.zig`**:
   ```zig
   pub fn benchmarkGraphTraversal() !void {
       // Test O(1) adjacency lookup
   }

   pub fn benchmarkPathfinding() !void {
       // Test shortest path (depth 5) - target: < 10ms
   }

   pub fn benchmarkIndexBuild() !void {
       // Test 10K file indexing - target: < 1000ms
   }
   ```

4. **Performance Thresholds (from spec)**:
   - Cold start: < 50ms
   - Depth 1 traversal: < 1ms
   - Depth 3 traversal: < 5ms
   - Depth 5 traversal: < 10ms
   - Index build (10K files): < 1000ms

5. **CI Integration**:
   - Run benchmarks on every build
   - Fail build if performance degrades > 20%
   - Store baseline metrics in `.activations/benchmarks.json`

**Success Criteria**:
- ✅ All benchmarks implemented
- ✅ Performance thresholds validated
- ✅ Timing reports on `engram sync`
- ✅ CI fails on performance regression

---

## Phase 2: MEDIUM PRIORITY - Week 2

**Goal**: Improve compliance from 63% to 85%+ by addressing medium priority issues.

### Issue 2.1: Fix YAML Frontmatter Structure

**Status**: ⚠️ Partially Compliant  
**Impact**: Files may not parse with standard YAML parsers; connections in body not spec-compliant  
**Effort**: 3-4 hours  
**Priority**: MEDIUM

#### Implementation Steps:

1. **Update `src/utils/yaml.zig`**:
   - Ensure connections are parsed from frontmatter, not body
   - Add validation: connections must be in frontmatter
   - Reject files with connections in body

2. **Update `src/storage/filesystem.zig`**:
   - Ensure `writeNeurona()` writes connections in frontmatter
   - Format:
     ```yaml
     ---
     id: req.auth.001
     title: User Authentication
     type: requirement
     tags: [auth, security]
     updated: 2025-01-24
     language: en
     
     connections:
       validated_by:
         - target_id: test.auth.001
           weight: 90
       blocked_by:
         - target_id: issue.001
           weight: 100
     ---
     
     Body content here...
     ```

3. **Migration Script** (`src/tools/migrate_frontmatter.zig`):
   ```zig
   pub fn migrateNeuronas(allocator: Allocator, dir: []const u8) !void {
       // Scan existing Neuronas
       // Detect connections in body
       // Move to frontmatter
       // Rewrite files
   }
   ```

4. **Validation Test**:
   - Create test files with connections in body
   - Ensure validator rejects them
   - Ensure migrated files are accepted

**Success Criteria**:
- ✅ All new Neuronas have connections in frontmatter
- ✅ Existing Neuronas migrated
- ✅ YAML parser validates frontmatter-only connections
- ✅ Integration tests pass

---

### Issue 2.2: Implement EQL Query Language

**Status**: ❌ Not Implemented  
**Impact**: Cannot use spec's query syntax (`engram query "type:issue AND tag:p1"`); limited to flag-based queries  
**Effort**: 8-10 hours  
**Priority**: MEDIUM

#### Implementation Steps:

1. **Create `src/utils/eql_parser.zig`**:
   ```zig
   pub const EQLParser = struct {
       query: []const u8,
       
       pub fn parse(self: EQLParser) !EQLQuery,
   };

   pub const EQLQuery = struct {
       conditions: []EQLCondition,
       logic_op: LogicOp,
   };

   pub const EQLCondition = struct {
       field: []const u8,
       op: ConditionOp,
       value: []const u8,
       
       // For link conditions
       link_type: ?[]const u8,
       link_target: ?[]const u8,
   };

   pub const LogicOp = enum { AND, OR };
   pub const ConditionOp = enum { eq, neq, gt, lt, gte, lte, contains, not_contains };
   ```

2. **Grammar to Implement**:
   ```
   EQL := Condition (LogicOp Condition)*
   Condition := FieldCondition | LinkCondition
   FieldCondition := field ':' op ':' value
   LinkCondition := 'link(' type ',' target ')'
   ```

3. **Supported Examples**:
   ```bash
   # Field conditions
   engram query "type:issue"
   engram query "type:issue AND tag:p1"
   engram query "context.status:open AND context.priority:1"
   engram query "priority:gte:3 AND priority:lte:5"
   engram query "title:contains:authentication OR tag:security"

   # Link conditions
   engram query "link(validates, req.auth.001) AND type:test_case"
   engram query "link(blocked_by, issue.001) AND type:issue"

   # Complex queries
   engram query "(type:issue OR type:requirement) AND state:open"
   ```

4. **Update `src/cli/query.zig`**:
   - Detect if query string is EQL format (contains `:` or `link(`)
   - If EQL, parse with `eql_parser`
   - Convert EQL to existing filter structure
   - Fallback to flag-based if parsing fails
   - Support both: `engram query "type:issue"` and `engram query --mode text "authentication"`

5. **EQL Operators**:
   - Equality: `:`, `:eq:`, `:neq:`
   - Comparison: `:gt:`, `:lt:`, `:gte:`, `:lte:`
   - String: `:contains:`, `:not_contains:`
   - Link: `link(type,target)`

**Success Criteria**:
- ✅ EQL parser implemented
- ✅ All operators supported
- ✅ Complex queries (AND, OR) working
- ✅ Integration with existing filter system
- ✅ Fallback to flag-based queries
- ✅ Documentation and examples

---

### Issue 2.3: Add `.activations/` to `.gitignore`

**Status**: ⚠️ Partially Compliant  
**Impact**: `.activations/` files may be committed; should be ignored  
**Effort**: 10 minutes  
**Priority**: MEDIUM

#### Implementation Steps:

1. **Update `.gitignore`** (root directory):
   ```gitignore
   # System Memory (Neurona Spec)
   .activations/

   # OS metadata
   .DS_Store
   Thumbs.db

   # Zig build artifacts
   zig-cache/
   zig-out/
   ```

2. **Update `src/cli/init.zig`** - Template generator:
   - Ensure generated `.gitignore` includes `.activations/`
   - Template already has it (line 369)

3. **Verification**:
   - Run `git status` to ensure `.activations/` ignored
   - Create test Cortex and verify `.gitignore` works

**Success Criteria**:
- ✅ `.gitignore` updated in root
- ✅ `.gitignore` includes `.activations/`
- ✅ Init command generates correct `.gitignore`
- ✅ Git ignores `.activations/` files

---

## Phase 3: LOW PRIORITY - Week 3

**Goal**: Reach 95%+ compliance by implementing Phase 3 features.

### Issue 3.1: Implement `engram run` Command

**Status**: ❌ Not Implemented  
**Impact**: Cannot execute code artifacts (Phase 3 feature)  
**Effort**: 8-10 hours  
**Priority**: LOW

#### Implementation Steps:

1. **Create `src/cli/run.zig`** - New command module:
   ```zig
   pub const RunConfig = struct {
       neurona_id: []const u8,
       trigger: ?[]const u8,
       sandbox: bool = false,
       timeout_seconds: u32 = 30,
   };

   pub fn execute(allocator: Allocator, config: RunConfig) !void {
       // Load Neurona by ID
       // Check type == artifact or type == state_machine
       // Verify context.safe_to_exec == true
       // Execute code or run state machine
   };
   ```

2. **For Artifacts**:
   - Read file from `context.file_path`
   - Use runtime specified in `context.runtime`
   - Support: `zig`, `python`, `node`, `bash`
   - Capture and display output
   - Handle execution errors

3. **For State Machines**:
   - Load state machine definition from `context`
   - Execute `entry_action`
   - Process triggers
   - Execute `exit_action`
   - Validate allowed roles

4. **Safety Features**:
   - Sandbox execution (chroot, namespaces) - optional but recommended
   - Timeout enforcement (default 30s, configurable)
   - Resource limits (memory, CPU)
   - User confirmation before executing (optional)

5. **Register Command**:
   - Update `src/main.zig` to add `engram run` to command registry
   - Add help text: `engram run <neurona_id> [options]`

6. **CLI Interface**:
   ```bash
   engram run artifact.build.backend --runtime node
   engram run sm.auth.logged_in --trigger logout
   engram run artifact.test.api --sandbox --timeout 60
   ```

**Success Criteria**:
- ✅ `engram run` command implemented
- ✅ Artifact execution working
- ✅ State machine execution working
- ✅ Safety features (sandbox, timeout, confirmation)
- ✅ Support for multiple runtimes
- ✅ Registered in CLI and documented

---

### Issue 3.2: Add URI Scheme Support

**Status**: ❌ Not Implemented  
**Impact**: Cannot reference Neuronas by URI (`neurona://<cortex-id>/<neurona-id>`); limited to direct IDs  
**Effort**: 4-5 hours  
**Priority**: LOW

#### Implementation Steps:

1. **Create `src/utils/uri_parser.zig`**:
   ```zig
   pub const URI = struct {
       scheme: []const u8,
       cortex_id: []const u8,
       neurona_id: []const u8,
       
       pub fn parse(uri: []const u8) !URI,
       pub fn resolve(self: URI) ![]const u8,  // Returns file path
   };
   ```

2. **Supported Format**:
   ```
   neurona://<cortex-id>/<neurona-id>
   ```

3. **Resolution Logic**:
   - Parse URI components
   - Locate Cortex directory (check current dir, then parent)
   - Load `.activations/graph.idx`
   - Look up Neurona ID in index
   - Resolve to file path in `neuronas/`

4. **Update Commands to Accept URIs**:
   - `engram show neurona://my_cortex/req.auth.001`
   - `engram trace neurona://my_cortex/req.auth.001`
   - `engram link neurona://ctx1/note.1 neurona://ctx1/note.2 relates_to`
   - Fall back to direct ID if URI parse fails

5. **Cortex Discovery**:
   - Check current directory for `cortex.json`
   - If not found, search parent directories
   - Support relative resolution from any directory

6. **Error Handling**:
   - Invalid scheme (must be `neurona://`)
   - Malformed URI
   - Cortex not found
   - Neurona not found in Cortex

**Success Criteria**:
- ✅ URI parser implemented
- ✅ Resolution logic working
- ✅ Commands accept URI format
- ✅ Cortex discovery working
- ✅ Error handling robust
- ✅ Documentation with examples

---

## Implementation Timeline

### Week 1: HIGH PRIORITY
- Day 1-2: Issue 1.1 - Graph Persistence
- Day 3-4: Issue 1.2 - Vector Persistence
- Day 5: Issue 1.3 - LLM Cache
- Day 6-7: Issue 1.4 - Performance Benchmarking
- **Deliverable**: All persistence and critical features working

### Week 2: MEDIUM PRIORITY
- Day 1-2: Issue 2.1 - YAML Frontmatter Fix
- Day 3-5: Issue 2.2 - EQL Query Language
- Day 6: Issue 2.3 - Update .gitignore
- **Deliverable**: Query system and file structure compliance at 85%+

### Week 3: LOW PRIORITY
- Day 1-4: Issue 3.1 - `engram run` Command
- Day 5: Issue 3.2 - URI Scheme Support
- **Deliverable**: Phase 3 features complete, 95%+ compliance

---

## Success Criteria

### Phase 1 Complete When:
- ✅ `.activations/graph.idx` persisted and loaded
- ✅ `.activations/vectors.bin` persisted and loaded
- ✅ `.activations/cache/` populated with LLM data
- ✅ Performance benchmarking with < 10ms rule validation
- ✅ All benchmarks passing thresholds
- ✅ CI integration for performance testing

### Phase 2 Complete When:
- ✅ All Neuronas have connections in frontmatter only
- ✅ EQL parser implemented and integrated
- ✅ All EQL operators supported
- ✅ `.gitignore` includes `.activations/`
- ✅ No YAML parsing errors

### Phase 3 Complete When:
- ✅ `engram run` command working
- ✅ Artifact and state machine execution
- ✅ Safety features (sandbox, timeout) implemented
- ✅ URI scheme parsing and resolution
- ✅ Commands accept URI format
- ✅ Documentation complete

### Full Compliance Achieved When:
- ✅ Overall compliance ≥ 95%
- ✅ All HIGH PRIORITY issues resolved
- ✅ All MEDIUM PRIORITY issues resolved
- ✅ LOW PRIORITY features implemented
- ✅ Integration tests passing
- ✅ Documentation complete

---

## Estimated Effort Summary

| Phase | Issues | Total Hours |
|--------|---------|-------------|
| Phase 1 (HIGH) | 4 | 20-28 hours |
| Phase 2 (MEDIUM) | 3 | 13-17 hours |
| Phase 3 (LOW) | 2 | 12-15 hours |
| **Total** | **9** | **45-60 hours** (~6-8 days focused work) |

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| API compatibility issues (Zig 0.15.2) | Medium | Medium | Test on multiple Zig versions |
| Performance targets too aggressive | Low | High | Adjust thresholds after initial benchmarks |
| Breaking changes during migration | Low | Medium | Backup before running migration scripts |
| Cache corruption | Low | Low | Add checksums, implement validation |

---

## Next Steps

1. **Review and Approve**: Get approval for this plan before starting implementation
2. **Setup Task Tracking**: Use TaskManager to create atomic subtasks under `.tmp/tasks/compliance/`
3. **Start Phase 1**: Begin with Issue 1.1 (Graph Persistence)
4. **Weekly Reviews**: Assess progress and adjust plan as needed
5. **Documentation Updates**: Keep this plan in sync with actual implementation

---

## Notes

- All tasks should be implemented incrementally with tests
- Each issue resolution should pass existing integration tests
- Performance targets based on spec: < 50ms cold start, < 10ms traversal
- Consider creating dedicated benchmark suite for continuous monitoring
- EQL implementation should be backwards compatible with flag-based queries
