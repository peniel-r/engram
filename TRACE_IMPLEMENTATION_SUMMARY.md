# Trace Command Implementation Summary

## Overview
Implemented the `engram trace` command for visualizing dependency trees in the Engraph knowledge graph system.

## Task: `br show bd-13l`
This was a branch/issue request to implement a trace command for tracking dependencies between Neuronas.

## Implementation Details

### Files Modified/Created

#### 1. `src/cli/trace.zig` (NEW)
- **Purpose**: Main trace command implementation
- **Features**:
  - Bidirectional tracing: upstream (dependencies) and downstream (implementations)
  - Configurable depth limit
  - Tree and list output formats
  - JSON output for AI integration
  - BFS for downstream, DFS for upstream traversal

- **Key Functions**:
  - `execute()`: Main command handler
  - `trace()`: Core tracing logic
  - `buildDownstreamTree()`: BFS traversal for children
  - `buildUpstreamTree()`: DFS traversal for parents
  - `outputTree()`: Human-readable tree format
  - `outputJson()`: JSON format for AI parsing
  - `findNeuronaPath()`: File lookup by ID

- **Data Structures**:
  - `TraceConfig`: Configuration (id, direction, max_depth, format, json_output)
  - `TraceNode`: Result node with id, level, connections, node_type

#### 2. `src/main.zig` (MODIFIED)
- Added `handleTrace()` function
- Added `printTraceHelp()` function
- Integrated trace command into CLI routing
- Added command-line argument parsing for trace options

#### 3. `src/core/graph.zig` (MODIFIED)
- Fixed duplicate `dfsRecursive()` function (removed duplicate)
- Fixed typos in variable names (neurona_id → node_id)
- Improved graph structure for trace operations

#### 4. Test Fixtures (NEW)
Created 4 test files in `tests/fixtures/trace/`:
- `req.auth.md`: Root requirement
- `test.auth.login.md`: Test case for auth
- `impl.auth.oauth2.md`: OAuth2 implementation
- `issue.auth.bug.md`: Bug blocking auth

#### 5. Unit Tests (ADDED)
Added comprehensive tests in `src/cli/trace.zig`:
- Test loading neuronas and building graph
- Test downstream tracing from req.auth
- Test upstream tracing from test.auth.login
- Test file path finding
- Test output generation (tree and JSON)

## Technical Challenges & Solutions

### 1. ArrayListUnmanaged Pattern
**Issue**: Zig 0.15.2 requires explicit allocator management
**Solution**: Converted all `ArrayList` to `ArrayListUnmanaged` and passed allocator explicitly

### 2. Memory Management
**Issue**: Complex ownership with pointers in TraceNode
**Solution**: Used pointer-to-value conversion pattern with proper deinit

### 3. stdout API Compatibility
**Issue**: Zig 0.15.2 changed stdout API
**Solution**: Used `std.fs.File.stdout().writer(&buffer)` with `.interface` field

### 4. Graph Edge Direction
**Issue**: Confusion between incoming/outgoing edges
**Solution**: Clarified `getIncoming()` returns edges pointing TO the node, `getAdjacent()` returns edges FROM the node

## Command Usage

### Basic Usage
```bash
# Trace downstream dependencies (default)
engram trace req.auth

# Trace upstream dependencies
engram trace req.auth --up

# Limit trace depth
engram trace req.auth --depth 3

# Output as JSON for AI
engram trace req.auth --json

# List format instead of tree
engram trace req.auth --format list
```

### Output Examples

#### Tree Format
```
🌲 Dependency Tree
========================================
req.auth (3)
  test.auth.login, impl.auth.oauth2, issue.auth.bug

test.auth.login (0)

impl.auth.oauth2 (0)

issue.auth.bug (0)
```

#### JSON Format
```json
[
  {"id":"req.auth","level":0,"type":"root","connections":["test.auth.login","impl.auth.oauth2","issue.auth.bug"]},
  {"id":"test.auth.login","level":1,"type":"downstream","connections":[]},
  {"id":"impl.auth.oauth2","level":1,"type":"downstream","connections":[]},
  {"id":"issue.auth.bug","level":1,"type":"downstream","connections":[]}
]
```

## Build Status
✅ Project builds successfully
✅ All unit tests pass
✅ Command integrated into CLI

## Testing
- 6 unit tests created and passing
- Test fixtures cover real-world scenarios (requirement → test → implementation → issue)
- Both upstream and downstream tracing tested
- Output formats (tree and JSON) tested

## Next Steps
1. User acceptance testing with real datasets
2. Performance optimization for large graphs
3. Additional output formats (DOT, Mermaid)
4. Caching layer for repeated traces
5. Visual diff between trace snapshots

## Files Summary
- **New**: `src/cli/trace.zig` (340 lines)
- **Modified**: `src/main.zig` (added trace handler)
- **Modified**: `src/core/graph.zig` (fixed typos and duplicate)
- **New**: `tests/fixtures/trace/*.md` (4 test files)
- **Documentation**: `TRACE_IMPLEMENTATION_SUMMARY.md`