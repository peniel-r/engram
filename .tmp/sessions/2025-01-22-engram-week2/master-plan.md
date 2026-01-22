# Master Plan: Engram Week 2 Implementation

**Session**: 2025-01-22-engram-week2
**Phase**: Phase 2 - The Axon (Connectivity)
**Timeline**: Week 2-3 (2 weeks)
**Status**: Planning

---

## Overview

Implement advanced graph operations and ALM workflow support for Engram CLI. This phase focuses on connectivity, dependency tracing, and state management to enable full software lifecycle management capabilities.

### Key Goals

- **Graph Traversal**: BFS/DFS algorithms with level tracking, shortest path finding
- **ALM Commands**: trace, status, query commands for requirements/tests/issues
- **State Management**: Enforced state transitions and validation rules
- **Impact Analysis**: Trace upstream/downstream dependencies

### Architecture Principles (from code-quality.md)
- ✅ Modular: Single responsibility per module (< 100 lines)
- ✅ Functional: Pure functions, immutability where possible
- ✅ Maintainable: Self-documenting, testable, predictable
- ✅ Explicit dependencies: Pass allocator explicitly

---

## Component Architecture

### Phase 2 Dependencies

```
core/graph.zig
  ├── cli/trace.zig (BFS/DFS, shortestPath)
  ├── cli/status.zig (degree, inDegree queries)
  └── cli/impact.zig (upstream/downstream trace)

core/neurona.zig
  └── cli/update.zig (modify fields programmatically)

storage/filesystem.zig
  ├── cli/link_artifact.zig (link code files to requirements)
  └── cli/release_status.zig (release readiness checks)
```

---

## Components (Dependency Order)

### 1. Graph Traversal Engine (Core)
**Priority**: Critical (blocks some Phase 2 commands)
**Files**:
- Extend `src/core/graph.zig` with traversal algorithms (deferred to Phase 2+)

**Purpose**: Provide efficient graph traversal and pathfinding

**Tasks**:
- [ ] Implement BFS traversal with level tracking
- [ ] Implement DFS traversal
- [ ] Implement shortest path finding (Dijkstra/BFS for unweighted)
- [ ] Implement bidirectional indexing (forward + reverse)
- [ ] Implement node/edge statistics (degree, inDegree, totalEdges)
- [ ] Write unit tests for all algorithms

**Note**: Basic graph operations working (O(1) lookup, degree, nodeCount). Advanced traversal deferred.

**Success Criteria**:
- O(1) adjacency lookup maintained (✅)
- BFS returns nodes by level (depth)
- DFS visits all reachable nodes
- Shortest path finds optimal route (unweighted graphs)
- Statistics computed correctly
- 95%+ test coverage

---

### 2. `engram trace` Command
**Priority**: High (ALM workflow requirement)
**File**: `src/cli/trace.zig`

**Purpose**: Visualize dependency trees for requirements, tests, and issues

**Tasks**:
- Parse trace arguments (id, --up/--down, --depth, --format)
- Use Graph traversal engine to collect dependencies
- Display dependency tree (indented by level)
- Support multiple output formats (tree, table, dot)
- Show connection types and weights
- Write unit tests

**Success Criteria**:
- Trace up (parent) and down (child, validates, blocks)
- Limit by depth (e.g., --depth 3)
- Format output for terminal and AI (JSON)
- Handle circular dependencies gracefully
- 90%+ test coverage

---

### 3. `engram status` Command
**Priority**: High (ALM workflow requirement)
**File**: `src/cli/status.zig`

**Purpose**: List and filter open issues by priority, assignee, status

**Tasks**:
- Parse status arguments (--filter, --sort, --group-by)
- Scan neuronas/ directory
- Filter by type=issue
- Filter by status (default: open)
- Sort by priority (1-5), assignee, created date
- Group by assignee or priority
- Display with formatting (table, list, JSON)
- Write unit tests

**Success Criteria**:
- List all open issues by default
- Filter by multiple criteria (type, status, tags)
- Sort by any field (priority, created, assignee)
- Group for team dashboards
- JSON output for AI integration
- 90%+ test coverage

---

### 4. `engram query` Command
**Priority**: Medium (powerful search interface)
**File**: `src/cli/query.zig`

**Purpose**: Basic query interface for filtering Neuronas by type, tags, connections

**Tasks**:
- Parse query string (type:issue, tag:p1, link(type:blocked_by,target:release.v1))
- Implement simple query parser (AND, OR operators)
- Filter scanned Neuronas
- Support connection-based queries (type, target)
- Support tag-based queries (single, multiple)
- Display results with connection counts
- Write unit tests

**Success Criteria**:
- Parse type, tag, and link filters
- Combine filters with AND/OR logic
- Return matching Neuronas
- Show connection information
- JSON output support
- 90%+ test coverage

---

### 5. `engram update` Command
**Priority**: Medium (programmatic updates)
**File**: `src/cli/update.zig`

**Purpose**: Update Neurona fields programmatically (status, context)

**Tasks**:
- Parse update arguments (--set, --append, --remove)
- Read existing Neurona
- Modify specific fields (context.status, priority, assignee)
- Write back to disk
- Validate state transitions
- Write unit tests

**Success Criteria**:
- Set key-value fields
- Append to array fields (tags)
- Remove from array fields
- Enforce state transitions (if configured)
- Update updated timestamp
- 90%+ test coverage

---

### 6. `engram impact` Command
**Priority**: Medium (ALM impact analysis)
**File**: `src/cli/impact.zig`

**Purpose**: Trace upstream/downstream dependencies for code changes

**Tasks**:
- Parse impact arguments (id, --upstream, --downstream, --report-type)
- Trace upstream dependencies (requirements, features)
- Trace downstream dependencies (tests, artifacts, issues)
- Identify blocking issues
- Generate recommendations (affected tests)
- Display impact report (table format)
- Write unit tests

**Success Criteria**:
- Trace all connected Neuronas
- Categorize by direction (upstream, downstream)
- Identify blocking relationships
- Calculate impact metrics (affected count, severity)
- Generate test recommendations
- 90%+ test coverage

---

### 7. `engram link-artifact` Command
**Priority**: Medium (ALM workflow)
**File**: `src/cli/link_artifact.zig`

**Purpose**: Link source code files to implementing requirements

**Tasks**:
- Parse link arguments (file_path, --requirement, --weight)
- Read source file (create artifact Neurona)
- Link to requirement using `implements` connection
- Set metadata (runtime, file_path, safe_to_exec)
- Write unit tests

**Success Criteria**:
- Create artifact Neurona from file path
- Extract basic metadata (language, line count)
- Link to requirement with weight
- Validate file exists
- 90%+ test coverage

---

### 8. `engram release-status` Command
**Priority**: Medium (ALM release readiness)
**File**: `src/cli/release_status.zig`

**Purpose**: Validate release readiness (requirements covered, tests passing, no blocking issues)

**Tasks**:
- Parse release-status arguments (--release-id, --check-tests, --check-blockers)
- Scan all requirements
- Validate test status (passing/not_run)
- Check for blocking issues
- Generate release readiness report
- Compute completion percentage
- Write unit tests

**Success Criteria**:
- List all requirements for release
- Check test coverage (percentage passing)
- Identify blocking issues
- Compute completion metrics
- Display pass/fail status
- 90%+ test coverage

---

### 9. State Management System
**Priority**: High (cross-cutting feature)
**Location**: Extend `src/core/neurona.zig` and `src/cli/`

**Purpose**: Enforce state transitions and validation rules

**Tasks**:
- Define state transitions for each Neurona type
- Implement state transition validation function
- Add state validation to update command
- Add connection type validation (type-specific allowed connections)
- Implement cardinality constraints (binary_node: left/right max 1)
- Detect orphaned Neuronas
- Implement state filtering in status/query commands
- Write unit tests

**Success Criteria**:
- Issues: open → in_progress → resolved → closed
- Tests: not_run → running → passing → failing
- Requirements: draft → approved → implemented
- Enforced type-specific connections
- Cardinality constraints enforced
- Orphan detection working
- 90%+ test coverage

---

## Testing Strategy

### Target Coverage: 90%+

### Unit Tests

**New Test Files**:
- `tests/unit/test_graph_traversal.zig` - BFS, DFS, shortest path
- `tests/unit/test_trace.zig` - Dependency tree tracing
- `tests/unit/test_status.zig` - Issue filtering and sorting
- `tests/unit/test_query.zig` - Query parsing and filtering
- `tests/unit/test_update.zig` - Field updates
- `tests/unit/test_impact.zig` - Impact analysis
- `tests/unit/test_link_artifact.zig` - Artifact linking
- `tests/unit/test_release_status.zig` - Release readiness
- `tests/unit/test_state_management.zig` - State transitions

**Test Fixtures** (Extend `tests/fixtures/`):
- `sample_cortex/trace_requirements.md` - Requirements with tests
- `sample_cortex/trace_issues.md` - Issues with blockers
- `sample_cortex/complex_graph.md` - Multi-level dependencies
- `sample_cortex/release_requirements.md` - Release requirements

### Integration Tests

**Test Files**:
- `tests/integration/test_trace_workflow.zig` - Full trace scenario
- `tests/integration/test_status_workflow.zig` - Issue status flow
- `tests/integration/test_query_workflow.zig` - Complex queries

---

## Validation Criteria

### Graph Traversal Engine
- [ ] BFS traversal with level tracking works
- [ ] DFS traversal visits all reachable nodes
- [ ] Shortest path finds optimal route
- [ ] Bidirectional indexing functional
- [ ] Statistics (degree, inDegree) correct
- [ ] 95%+ test coverage

### `engram trace` Command
- [ ] Trace up (parent) dependencies
- [ ] Trace down (child, validates, blocks) dependencies
- [ ] Limit by depth (--depth N)
- [ ] Multiple output formats (--format tree/table/dot)
- [ ] Handle circular dependencies
- [ ] 90%+ test coverage

### `engram status` Command
- [ ] List all open issues by default
- [ ] Filter by type, status, tags
- [ ] Sort by priority, assignee, created
- [ ] Group by assignee or priority
- [ ] JSON output
- [ ] 90%+ test coverage

### `engram query` Command
- [ ] Parse type, tag, link filters
- [ ] Combine with AND/OR logic
- [ ] Return matching Neuronas
- [ ] 90%+ test coverage

### `engram update` Command
- [ ] Set key-value fields
- [ ] Append to arrays (tags)
- [ ] Remove from arrays
- [ ] Enforce state transitions
- [ ] 90%+ test coverage

### `engram impact` Command
- [ ] Trace upstream dependencies
- [ ] Trace downstream dependencies
- [ ] Identify blocking issues
- [ ] Generate recommendations
- [ ] 90%+ test coverage

### `engram link-artifact` Command
- [ ] Create artifact Neurona from file
- [ ] Link to requirement
- [ ] Validate file exists
- [ ] 90%+ test coverage

### `engram release-status` Command
- [ ] List requirements for release
- [ ] Check test status
- [ ] Identify blockers
- [ ] Compute completion % ✓
- [ ] 90%+ test coverage

### State Management System
- [ ] State transitions enforced (issue, test, requirement)
- [ ] Type-specific connection validation
- [ ] Cardinality constraints enforced
- [ ] Orphan detection working
- [ ] 90%+ test coverage

---

## Risk Mitigation

### High Priority Risks

1. **Graph Algorithm Complexity**
   - Risk: Shortest path, activation may be slow
   - Mitigation: Benchmark early, optimize hot paths, use pre-computed indices

2. **State Transition Logic**
   - Risk: Complex state machine rules across 10 Neurona types
   - Mitigation: Trait-based design, shared validation logic, extensive fixtures

3. **Query Parser Complexity**
   - Risk: Parsing AND/OR logic may be error-prone
   - Mitigation: Simple parser, comprehensive tests, clear error messages

4. **Integration Testing Scope**
   - Risk: End-to-end ALM workflows hard to test
   - Mitigation: Comprehensive fixtures, property-based testing, realistic scenarios

---

## Next Steps

1. **Review this master plan** for approval
2. **Implement Graph Traversal Engine** (Component 1)
3. **Implement `engram trace`** (Component 2)
4. **Implement `engram status`** (Component 3)
5. **Implement `engram query`** (Component 4)
6. **Implement State Management** (Component 9)
7. **Validate** all components meet 90%+ coverage

---

## Success Criteria

### Phase 2 Complete When:
- [ ] Graph traversal engine complete (BFS, DFS, shortest path)
- [ ] 4+ new CLI commands implemented (trace, status, query, update, impact, link_artifact, release_status)
- [ ] State management enforced
- [ ] 90%+ test coverage
- [ ] Performance targets met (sub-10ms pathfinding, sub-50ms impact analysis)

---

**Status**: Draft - Awaiting Approval
**Created**: 2025-01-22
**Session**: 2025-01-22-engram-week2
