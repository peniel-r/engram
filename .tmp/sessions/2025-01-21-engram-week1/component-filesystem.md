# Component Plan: Storage Layer (Filesystem Module)

**Session**: 2025-01-21-engram-week1
**Component**: Step 4 - Storage Layer
**Status**: Planning - Awaiting Approval
**Created**: 2025-01-22

---

## Overview

Implement the storage layer filesystem module that provides high-level file operations for working with Neurona files. This module bridges the gap between the raw filesystem and the core Neurona data structure.

### Purpose

- Read Neurona Markdown files from disk and convert to Neurona structs
- Write Neurona structs to disk as properly formatted Markdown files
- Scan directories for Neurona files
- List and filter Neurona files

### Dependencies

**Incoming (uses)**:
- `src/core/neurona.zig` - Neurona data model
- `src/utils/frontmatter.zig` - Frontmatter extraction
- `src/utils/yaml.zig` - YAML parsing
- `src/utils/timestamp.zig` - Timestamp generation

**Outgoing (used by)**:
- `src/cli/show.zig` - Display Neuronas
- `src/cli/sync.zig` - Rebuild indices
- `src/cli/new.zig` - Refactored to use storage layer

---

## Architecture

### Module: `src/storage/filesystem.zig`

**Responsibilities**:
1. File I/O operations for Neurona files
2. Conversion between Markdown + YAML and Neurona struct
3. Directory scanning and file listing
4. Path management for Neurona files

**Design Principles** (from code-quality.md, adapted for Zig):
- ✅ Pure functions (no side effects except explicit I/O)
- ✅ Explicit dependencies (allocator parameter)
- ✅ Small functions (< 50 lines)
- ✅ Memory-safe with proper deinit()

---

## Interface Specification

### Public API

```zig
// Read a Neurona file and return a Neurona struct
pub fn readNeurona(allocator: Allocator, filepath: []const u8) !Neurona

// Write a Neurona struct to a Markdown file
pub fn writeNeurona(allocator: Allocator, neurona: Neurona, filepath: []const u8) !void

// Scan directory and load all Neurona files
pub fn scanNeuronas(allocator: Allocator, directory: []const u8) ![]Neurona

// List all Neurona file paths in a directory
pub fn listNeuronaFiles(allocator: Allocator, directory: []const u8) ![][]const u8

// Check if a file is a valid Neurona file
pub fn isNeuronaFile(filename: []const u8) bool
```

### Internal Functions

```zig
// Convert parsed YAML frontmatter to Neurona struct
fn yamlToNeurona(allocator: Allocator, yaml: StringHashMap(yaml.Value), body: []const u8) !Neurona

// Convert Neurona struct to YAML frontmatter string
fn neuronaToYaml(allocator: Allocator, neurona: Neurona) ![]u8

// Generate complete Markdown file content from Neurona
fn generateMarkdown(allocator: Allocator, neurona: Neurona, body: []const u8) ![]u8

// Validate Neurona ID format
fn validateId(id: []const u8) bool
```

---

## Implementation Plan

### Task 1: File Reading Functions
**Priority**: High (blocks all CLI commands)

**Functions**:
- `isNeuronaFile(filename: []const u8) bool`
- `readNeurona(allocator: Allocator, filepath: []const u8) !Neurona`

**Steps**:
1. Implement `isNeuronaFile` - checks if file ends with `.md`
2. Implement `readNeurona`:
   - Read file content from disk
   - Extract frontmatter using `frontmatter.parse()`
   - Parse YAML using `yaml.Parser.parse()`
   - Convert YAML to Neurona struct using helper
   - Handle errors gracefully (invalid format, missing fields)

**Validation**:
- Test with valid Neurona file
- Test with missing frontmatter
- Test with invalid YAML
- Test with missing required fields (id, title)

---

### Task 2: File Writing Functions
**Priority**: High (blocks new.zig integration)

**Functions**:
- `neuronaToYaml(allocator: Allocator, neurona: Neurona) ![]u8`
- `generateMarkdown(allocator:Allocator, neurona: Neurona, body: []const u8) ![]u8`
- `writeNeurona(allocator: Allocator, neurona: Neurona, filepath: []const u8) !void`

**Steps**:
1. Implement `neuronaToYaml`:
   - Convert Neurona fields to YAML format
   - Handle Tier 1, 2, and 3 fields
   - Format connections as nested YAML
   - Format context extensions
2. Implement `generateMarkdown`:
   - Combine YAML frontmatter with body content
   - Add `---` delimiters
   - Preserve formatting
3. Implement `writeNeurona`:
   - Create/open file
   - Write content
   - Handle errors (permission denied, disk full)

**Validation**:
- Test write and read roundtrip
- Test with Tier 1 Neurona
- Test with Tier 2 Neurona (connections, type)
- Test with Tier 3 Neurona (hash, llm_metadata, context)

---

### Task 3: Directory Scanning Functions
**Priority**: Medium (blocks sync command)

**Functions**:
- `listNeuronaFiles(allocator: Allocator, directory: []const u8) ![][]const u8`
- `scanNeuronas(allocator: Allocator, directory: []const u8) ![]Neurona`

**Steps**:
1. Implement `listNeuronaFiles`:
   - Open directory
   - Iterate over entries
   - Filter for `.md` files
   - Return list of file paths
2. Implement `scanNeuronas`:
   - Use `listNeuronaFiles` to get all files
   - Call `readNeurona` for each file
   - Handle partial failures (skip invalid files)
   - Return array of valid Neuronas

**Validation**:
- Test with empty directory
- Test with valid Neuronas
- Test with mixed valid/invalid files
- Test with non-existent directory

---

## Testing Strategy

### Unit Tests (Target: 95% coverage)

**File**: `tests/unit/test_filesystem.zig`

#### Test: isNeuronaFile
```zig
test "isNeuronaFile identifies .md files" { ... }
test "isNeuronaFile rejects non-.md files" { ... }
test "isNeuronaFile handles empty strings" { ... }
```

#### Test: readNeurona
```zig
test "readNeurona parses valid Tier 1 file" { ... }
test "readNeurona parses valid Tier 2 file with connections" { ... }
test "readNeurona parses valid Tier 3 file with LLM metadata" { ... }
test "readNeurona returns error for missing frontmatter" { ... }
test "readNeurona returns error for invalid YAML" { ... }
test "readNeurona returns error for missing required fields" { ... }
```

#### Test: writeNeurona
```zig
test "writeNeurona writes valid Tier 1 file" { ... }
test "writeNeurona write and read roundtrip Tier 2" { ... }
test "writeNeurona write and read roundtrip Tier 3" { ... }
test "writeNeurona preserves connections correctly" { ... }
test "writeNeurona preserves context extensions" { ... }
```

#### Test: scanNeuronas
```zig
test "scanNeuronas returns empty for empty directory" { ... }
test "scanNeuronas loads all valid Neuronas" { ... }
test "scanNeuronas skips invalid files" { ... }
test "scanNeuronas handles partial failures" { ... }
```

### Integration Tests

**File**: `tests/integration/test_storage_integration.zig`

```zig
test "end-to-end: create, save, load Neurona" { ... }
test "end-to-end: scan directory and rebuild graph" { ... }
test "end-to-end: modify Neurona and persist changes" { ... }
```

### Fixtures

**Directory**: `tests/fixtures/sample_neuronas/`

```
sample_neuronas/
├── tier1_simple.md
├── tier2_with_connections.md
├── tier2_requirement.md
├── tier3_with_llm.md
├── tier3_state_machine.md
└── invalid_no_frontmatter.md
```

---

## Error Handling

### Error Types

```zig
pub const StorageError = error{
    FileNotFound,
    InvalidNeuronaFormat,
    MissingRequiredField,
    InvalidYaml,
    IoError,
    OutOfMemory,
};
```

### Validation Rules

1. **Required Fields**: `id`, `title` must be present
2. **ID Format**: Must be valid kebab-case (use id_generator validation)
3. **File Extension**: Must be `.md`
4. **Frontmatter**: Must be present and well-formed
5. **YAML**: Must be valid YAML syntax
6. **Connections**: Target IDs must reference valid neuronas (optional validation)

---

## Memory Management

### Allocation Strategy

- All functions take explicit `allocator` parameter
- Caller responsible for freeing returned memory
- Use `deinit()` methods for complex structures

### Memory Cleanup

```zig
// Example usage pattern
const neurona = try readNeurona(allocator, "neuronas/test.md");
defer neurona.deinit(allocator);

const neuronas = try scanNeuronas(allocator, "neuronas");
defer {
    for (neuronas) |*n| n.deinit(allocator);
    allocator.free(neuronas);
}
```

---

## Performance Targets

### From spec.md

- **Cold Start**: Loading a cortex should be < 200ms
- **File Read**: Single Neurona file < 10ms
- **Directory Scan**: 100 files < 100ms (leveraging async I/O if needed)

### Optimization Notes

- Use buffered I/O where possible
- Avoid unnecessary memory allocations
- Consider lazy loading for body content

---

## Integration Notes

### With `src/cli/new.zig`

**Current State**: Uses its own `writeNeuronaFile()` function

**After Integration**:
```zig
// Before
try writeNeuronaFile(filename, content);

// After
const neurona = try buildNeuronaFromConfig(config);
defer neurona.deinit(allocator);
try filesystem.writeNeurona(allocator, neurona, filename);
```

### With `src/cli/show.zig`

**Current State**: Not implemented

**After Integration**:
```zig
const neurona = try filesystem.readNeurona(allocator, filepath);
defer neurona.deinit(allocator);
try displayNeurona(neurona);
```

### With `src/cli/sync.zig`

**Current State**: Not implemented

**After Integration**:
```zig
const neuronas = try filesystem.scanNeuronas(allocator, "neuronas");
defer {
    for (neuronas) |*n| n.deinit(allocator);
    allocator.free(neuronas);
}
try rebuildGraph(neuronas);
```

---

## Success Criteria

- ✅ All unit tests pass (95%+ coverage)
- ✅ All integration tests pass
- ✅ Neurona write/read roundtrip works for all tiers
- ✅ Directory scanning handles edge cases
- ✅ Error handling is comprehensive
- ✅ Memory leaks are avoided (Zig's leak detection passes)
- ✅ Performance targets met

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| YAML parsing complexity | Medium | Use existing yaml.zig parser |
| Memory leaks in complex structures | High | Extensive testing with leak detection |
| Tier 3 context union complexity | Medium | Implement extensions incrementally |
| Filesystem errors (permissions, disk full) | Low | Proper error handling |
| Path handling on Windows vs Unix | Low | Use Zig's std.fs.Path abstraction |

---

## Next Steps

1. **Approve this component plan** ✋
2. **Create storage directory**: `mkdir src/storage`
3. **Implement Task 1**: File reading functions
4. **Implement Task 2**: File writing functions
5. **Implement Task 3**: Directory scanning functions
6. **Write comprehensive tests**
7. **Validate integration with core modules**
8. **Update master-plan.md**

---

**Status**: Awaiting Approval
**Created**: 2025-01-22
**Estimated Effort**: 4-6 hours
