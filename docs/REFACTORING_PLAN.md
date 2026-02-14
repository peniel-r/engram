# Code Deduplication & Library Refactoring Plan

**Version**: 1.0.0
**Date**: 2026-02-12
**Status**: Draft

---

## Executive Summary

This plan transforms Engram from a CLI-centric tool into a **clean, reusable Zig library** that other applications can import to leverage the Neurona Open Specification features. The refactoring eliminates ~2000 lines of code duplication while creating a clear separation between library concerns and CLI implementation.

### Key Objectives

1. **Create a clean library API** - Expose core functionality through well-structured public interfaces
2. **Eliminate code duplication** - Remove ~2000 lines of duplicated code across the codebase
3. **Separate concerns** - Decouple library logic from CLI-specific code
4. **Enable reuse** - Allow other applications to leverage Engram as a Zig library

---

## Current Architecture Analysis

### Module Structure

```
src/
├── root.zig              # Library entry point (re-exports)
├── main.zig              # CLI entry point (1374 lines, heavily duplicated)
├── neurona.zig           # Library module organizer (58 lines)
├── core/
│   ├── neurona.zig       # Core data structures (506 lines)
│   ├── cortex.zig
│   ├── graph.zig
│   ├── activation.zig
│   ├── state_machine.zig
│   ├── validator.zig
│   ├── query_engine.zig
│   ├── index_engine.zig
│   └── neurona_factory.zig
├── storage/
│   ├── filesystem.zig
│   ├── vectors.zig
│   ├── tfidf.zig
│   ├── glove.zig
│   ├── llm_cache.zig
│   └── index.zig
├── utils/
│   ├── frontmatter.zig
│   ├── yaml.zig
│   ├── timestamp.zig
│   ├── state_filters.zig
│   ├── token_counter.zig
│   ├── summary.zig
│   ├── file_ops.zig
│   ├── cli_parser.zig
│   ├── command_metadata.zig
│   ├── help_generator.zig
│   └── error_reporter.zig
└── cli/
    ├── init.zig
    ├── new.zig
    ├── show.zig
    ├── link.zig
    ├── sync.zig
    ├── delete.zig
    ├── trace.zig
    ├── status.zig
    ├── query.zig
    ├── update.zig
    ├── impact.zig
    ├── link_artifact.zig
    ├── release_status.zig
    ├── metrics.zig
    └── query_helpers.zig
```

### Problems Identified

1. **main.zig is massive (1374 lines)** - Contains command dispatch, flag parsing, and duplicated help functions
2. **CLI files duplicate library logic** - 14 CLI files have similar patterns for cortex resolution, JSON output, error handling
3. **Library code is mixed with CLI concerns** - Many utils are CLI-specific
4. **No clear public API** - root.zig re-exports but doesn't provide a cohesive interface
5. **~2000 lines of duplicated code** across CLI files and main.zig

---

## Target Architecture

```
src/
├── lib/                          # LIBRARY LAYER (clean, reusable)
│   ├── root.zig                  # Public API entry point
│   ├── neurona.zig               # Main library module (re-exports)
│   ├── core/
│   │   ├── types.zig             # Core types (Neurona, NeuronaType, etc.)
│   │   ├── connections.zig       # Connection types and logic
│   │   ├── context.zig           # Context extensions
│   │   ├── cortex.zig            # Cortex management
│   │   ├── graph.zig             # Graph operations
│   │   ├── activation.zig        # Neural activation algorithm
│   │   ├── state_machine.zig     # State machine support
│   │   └── validator.zig         # Validation logic
│   ├── storage/
│   │   ├── interface.zig         # Storage interface/traits
│   │   ├── filesystem.zig        # Filesystem implementation
│   │   ├── vectors.zig           # Vector index
│   │   ├── search.zig            # BM25, TF-IDF, GloVe
│   │   └── cache.zig             # LLM cache
│   ├── query/
│   │   ├── engine.zig            # Query engine
│   │   ├── eql.zig               # EQL parser
│   │   └── modes.zig             # Query modes (filter, text, vector, hybrid, activation)
│   └── utils/
│       ├── allocators.zig        # Allocator helpers
│       ├── strings.zig           # String utilities (json escape, etc.)
│       ├── text.zig              # Text processing/tokenization
│       ├── paths.zig              # Path resolution (cortex detection)
│       ├── error.zig              # Error types and handling
│       └── timestamp.zig         # Timestamp utilities
│
├── cli/                          # CLI LAYER (application-specific)
│   ├── main.zig                  # CLI entry point
│   ├── app.zig                   # Application orchestration
│   ├── commands/
│   │   ├── mod.zig               # Command registry and dispatcher
│   │   ├── init.zig
│   │   ├── new.zig
│   │   ├── show.zig
│   │   └── ...
│   ├── output/
│   │   ├── json.zig              # JSON output formatting
│   │   └── human.zig             # Human-readable output
│   ├── parser/
│   │   ├── flags.zig             # Flag parsing utilities
│   │   └── args.zig              # Argument parsing
│   └── help/
│       └── generator.zig         # Help generation
│
└── examples/                     # EXAMPLE APPLICATIONS
    ├── basic_usage.zig
    ├── alm_integration.zig
    └── custom_query.zig
```

### Key Principles

1. **Clear separation**: Library code in `src/lib/`, CLI code in `src/cli/`
2. **No CLI in library**: Library should have no knowledge of CLI concerns
3. **Public API**: Well-documented public interfaces in `src/lib/root.zig`
4. **Utility extraction**: Common patterns extracted to library utils
5. **Examples**: Showcase library usage patterns

---

## Refactoring Phases

### Phase 1: Library Foundation (Week 1-2)

**Goal**: Create clean library structure and core utilities

#### 1.1 Create Library Directory Structure

```
Create:
- src/lib/root.zig              # Public API
- src/lib/neurona.zig           # Module organizer
- src/lib/core/types.zig         # Extract from core/neurona.zig
- src/lib/core/connections.zig   # Extract from core/neurona.zig
- src/lib/core/context.zig       # Extract from core/neurona.zig
- src/lib/utils/strings.zig      # Extract JSON escape, string utils
- src/lib/utils/paths.zig        # Extract cortex resolution
- src/lib/utils/text.zig         # Extract tokenization
```

#### 1.2 Extract Core Types

**From**: `src/core/neurona.zig` (506 lines)
**To**: `src/lib/core/types.zig`, `src/lib/core/connections.zig`, `src/lib/core/context.zig`

**Actions**:
- Split `Neurona` struct into its own file
- Split `Connection` and `ConnectionType` into `connections.zig`
- Split `Context` union into `context.zig`
- Maintain backward compatibility with existing imports during transition

#### 1.3 Create String Utilities

**From**: Duplicated across `show.zig`, `status.zig`, `query.zig` (56 lines)
**To**: `src/lib/utils/strings.zig`

**New API**:
```zig
pub const Json = struct {
    pub fn printEscapedString(writer: anytype, s: []const u8) !void;
    pub fn formatString(s: []const u8, allocator: Allocator) ![]const u8;
};
```

**Impact**: Removes 56+ lines of duplication

#### 1.4 Create Path Resolution Utilities

**From**: Duplicated across 14 CLI files (140 lines)
**To**: `src/lib/utils/paths.zig`

**New API**:
```zig
pub const CortexResolver = struct {
    pub fn find(allocator: Allocator, path: ?[]const u8) !Cortex;
    pub fn getNeuronasPath(allocator: Allocator, cortex: []const u8) ![]const u8;
    pub fn getActivationsPath(allocator: Allocator, cortex: []const u8) ![]const u8;
};

pub const Cortex = struct {
    dir: []const u8,
    neuronas_path: []const u8,
    activations_path: []const u8,
};
```

**Impact**: Removes 140+ lines of duplication

#### 1.5 Create Text Processing Utilities

**From**: Duplicated in `query.zig` (200 lines)
**To**: `src/lib/utils/text.zig`

**New API**:
```zig
pub const TextProcessor = struct {
    pub fn tokenizeToWords(allocator: Allocator, text: []const u8) ![][]const u8;
    pub fn combineTitleAndTags(allocator: Allocator, title: []const u8, tags: []const []const u8) ![]const u8;
    pub fn toLower(allocator: Allocator, text: []const u8) ![]const u8;
};
```

**Impact**: Removes 200+ lines of duplication

#### 1.6 Update Build Configuration

**Modify**: `build.zig`

```zig
// Add library module
const lib = b.addModule("Engram", .{
    .root_source_file = b.path("src/lib/root.zig"),
    .target = target,
});

// Update executable to use library
const exe = b.addExecutable(.{
    .name = "engram",
    .root_source_file = b.path("src/cli/main.zig"),
    .imports = &.{
        .{ .name = "Engram", .module = lib },
    },
});
```

---

### Phase 2: Library Query & Storage Layer (Week 3-4)

**Goal**: Consolidate query and storage logic into library

#### 2.1 Create Query Interface

**From**: `src/cli/query.zig` (1368 lines), `src/core/query_engine.zig`
**To**: `src/lib/query/engine.zig`, `src/lib/query/eql.zig`, `src/lib/query/modes.zig`

**New API**:
```zig
pub const QueryEngine = struct {
    pub fn init(allocator: Allocator, cortex: *Cortex) QueryEngine;

    pub fn query(self: *QueryEngine, q: Query) ![]Result;

    pub const Query = union(enum) {
        filter: FilterQuery,
        text: TextQuery,
        vector: VectorQuery,
        hybrid: HybridQuery,
        activation: ActivationQuery,
    };

    pub const Result = struct {
        id: []const u8,
        score: f64,
        neurona: *Neurona,
    };
};
```

#### 2.2 Create Storage Interface

**From**: `src/storage/*.zig`
**To**: `src/lib/storage/interface.zig`, `src/lib/storage/filesystem.zig`

**New API**:
```zig
pub const Storage = struct {
    pub const Interface = struct {
        pub const VTable = struct {
            readNeurona: *const fn (ctx: *anyopaque, id: []const u8) anyerror!*Neurona,
            writeNeurona: *const fn (ctx: *anyopaque, neurona: *Neurona) anyerror!void,
            deleteNeurona: *const fn (ctx: *anyopaque, id: []const u8) anyerror!void,
            listNeuronas: *const fn (ctx: *anyopaque) anyerror![][]const u8,
            // ...
        };
    };

    pub fn filesystem(allocator: Allocator, cortex_path: []const u8) !Storage;
    pub fn memory(allocator: Allocator) !Storage;
};
```

#### 2.3 Create Graph Builder Utility

**From**: Duplicated across 6 CLI files (100 lines)
**To**: `src/lib/core/graph.zig` (add helper)

**New API**:
```zig
pub const Graph = struct {
    pub fn buildFromNeuronas(allocator: Allocator, neuronas: []const Neurona) !Graph;
    // ... existing methods
};
```

**Impact**: Removes 100+ lines of duplication

---

### Phase 3: CLI Layer Refactoring (Week 5-6)

**Goal**: Rebuild CLI layer using clean library API

#### 3.1 Restructure CLI Directory

```
Create:
- src/cli/main.zig              # Simplified entry point
- src/cli/app.zig               # Application context
- src/cli/commands/mod.zig      # Command registry
- src/cli/output/json.zig       # JSON output utilities
- src/cli/output/human.zig      # Human output utilities
- src/cli/parser/flags.zig      # Flag parsing
```

#### 3.2 Create Unified Output System

**From**: Duplicated across 8 CLI files (400 lines JSON, 300 lines human)
**To**: `src/cli/output/json.zig`, `src/cli/output/human.zig`

**New API**:
```zig
// src/cli/output/json.zig
pub const JsonOutput = struct {
    pub fn beginArray(writer: anytype) !void;
    pub fn endArray(writer: anytype) !void;
    pub fn beginObject(writer: anytype) !void;
    pub fn endObject(writer: anytype) !void;
    pub fn stringField(writer: anytype, name: []const u8, value: []const u8) !void;
    pub fn enumField(writer: anytype, name: []const u8, value: anytype) !void;
};

// src/cli/output/human.zig
pub const HumanOutput = struct {
    pub fn printHeader(title: []const u8, emoji: []const u8) !void;
    pub fn printSubheader(title: []const u8, emoji: []const u8) !void;
    pub fn printSeparator(char: u8, count: usize) !void;
};
```

**Impact**: Removes 700+ lines of duplication

#### 3.3 Create Command Registry

**From**: `src/main.zig` (lines 30-128)
**To**: `src/cli/commands/mod.zig`

**New API**:
```zig
pub const Command = struct {
    name: []const u8,
    description: []const u8,
    execute: *const fn (app: *App, args: []const []const u8) anyerror!void,
    print_help: *const fn () void,
};

pub const Registry = struct {
    commands: []const Command,

    pub fn find(self: *Registry, name: []const u8) ?Command;
    pub fn list(self: *Registry) []const Command;
};
```

#### 3.4 Simplify Flag Parsing

**From**: `src/main.zig` (600+ lines), `src/utils/cli_parser.zig`
**To**: `src/cli/parser/flags.zig`

**New API**:
```zig
pub const FlagParser = struct {
    pub fn parse(comptime spec: []const FlagSpec, args: []const []const u8) !ParsedFlags;

    pub const FlagSpec = struct {
        name: []const u8,
        short: ?[]const u8 = null,
        takes_value: bool = false,
        description: []const u8 = "",
    };

    pub const ParsedFlags = struct {
        flags: std.StringHashMap(?[]const u8),
        positionals: [][]const u8,
    };
};
```

#### 3.5 Consolidate Help Functions

**From**: `src/main.zig` (lines 1160-1308, 148 lines)
**To**: `src/cli/help/generator.zig`

**Simplify to single function**:
```zig
pub const HelpGenerator = struct {
    pub fn printCommandHelp(command_index: usize) !void;
};
```

**Impact**: Removes 148 lines of duplication

#### 3.6 Create Application Context

**New file**: `src/cli/app.zig`

```zig
pub const App = struct {
    allocator: Allocator,
    cortex: ?*lib.Cortex,
    storage: lib.Storage,
    query_engine: lib.QueryEngine,
    config: AppConfig,

    pub fn init(allocator: Allocator, cortex_path: ?[]const u8) !App;
    pub fn deinit(self: *App) void;

    pub fn ensureCortex(self: *App, path: ?[]const u8) !void;
};
```

---

### Phase 4: Migration & Cleanup (Week 7-8)

**Goal**: Migrate all commands to new structure and remove old code

#### 4.1 Migrate Commands One-by-One

For each command in `src/cli/`:
1. Replace with new implementation using library API
2. Remove duplicated utility code
3. Update tests
4. Verify functionality

**Order of migration**:
1. Simple commands first (status, init, metrics)
2. Complex commands (query, trace, impact)
3. Commands with side effects (new, update, delete)

#### 4.2 Remove Deprecated Files

Delete old files after migration:
- `src/main.zig` (old)
- `src/core/neurona.zig` (split into library core files)
- Duplicated utility code in CLI files
- `src/utils/cli_parser.zig` (replaced by `src/cli/parser/flags.zig`)

#### 4.3 Update root.zig

**New simplified public API**:
```zig
//! Engram - Neurona Knowledge Protocol Library

// Core types
pub const Neurona = lib.core.types.Neurona;
pub const NeuronaType = lib.core.types.NeuronaType;
pub const Connection = lib.core.connections.Connection;
pub const ConnectionType = lib.core.connections.ConnectionType;
pub const Context = lib.core.context.Context;

// Main components
pub const Cortex = lib.core.cortex.Cortex;
pub const Graph = lib.core.graph.Graph;
pub const QueryEngine = lib.query.engine.QueryEngine;

// Storage
pub const Storage = lib.storage;

// Query types
pub const Query = lib.query;

// Utils
pub const Json = lib.utils.strings.Json;
pub const TextProcessor = lib.utils.text.TextProcessor;
pub const CortexResolver = lib.utils.paths.CortexResolver;
```

#### 4.4 Update Tests

- Ensure all tests use new library API
- Remove tests for deprecated functions
- Add tests for new library utilities
- Verify `zig build test` passes

---

### Phase 5: Examples & Documentation (Week 9)

**Goal**: Create examples demonstrating library usage

#### 5.1 Create Example Applications

**`examples/basic_usage.zig`**:
```zig
const Engram = @import("Engram");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize cortex
    var cortex = try Engram.Cortex.load(allocator, "./my_cortex");
    defer cortex.deinit();

    // Create a neurona
    var neurona = try Engram.Neurona.init(allocator);
    defer neurona.deinit(allocator);
    neurona.title = "My Concept";
    neurona.id = "concept.001";

    // Save neurona
    try cortex.save(neurona);

    // Query neuronas
    var query_engine = try Engram.QueryEngine.init(allocator, &cortex);
    const results = try query_engine.query(.{
        .text = .{ .query = "my" }
    });
    defer allocator.free(results);

    std.debug.print("Found {d} results\n", .{results.len});
}
```

**`examples/alm_integration.zig`**:
```zig
const Engram = @import("Engram");

pub fn main() !void {
    const allocator = std.testing.allocator;

    // Load ALM cortex
    var cortex = try Engram.Cortex.load(allocator, "./project");
    defer cortex.deinit();

    // Query for requirements without tests
    const results = try cortex.query(.{
        .filter = .{
            .type = .requirement,
            .custom = "NOT link(validates, type:test_case)",
        },
    });

    // Generate test cases...
}
```

**`examples/custom_query.zig`**:
```zig
const Engram = @import("Engram");

pub fn main() !void {
    const allocator = std.testing.allocator;

    var cortex = try Engram.Cortex.load(allocator, "./cortex");
    defer cortex.deinit();

    // Custom neural activation query
    var engine = try Engram.QueryEngine.init(allocator, &cortex);

    const activation_query = Engram.Query{
        .activation = .{
            .seed_ids = &[_][]const u8{"concept.001"},
            .decay_rate = 0.5,
            .threshold = 0.1,
        },
    };

    const results = try engine.query(activation_query);
}
```

#### 5.2 Update Documentation

- Update `README.md` with library usage examples
- Create `LIBRARY_API.md` documenting public API
- Update `AGENTS.md` with new library interfaces for AI agents
- Add migration guide for CLI users

---

## Impact Summary

### Code Reduction

| Category | Current Lines | After Refactoring | Removed |
|----------|--------------|------------------|---------|
| Help Functions | 148 | 10 | 138 |
| JSON String Escape | 56 | 20 | 36 |
| Cortex Resolution | 140 | 40 | 100 |
| JSON Output Patterns | 400 | 100 | 300 |
| Flag Parsing | 600 | 150 | 450 |
| Graph Building | 100 | 30 | 70 |
| Error Handling | 50 | 20 | 30 |
| Output Formatting | 300 | 80 | 220 |
| Embedding Creation | 200 | 60 | 140 |
| **TOTAL** | **~1994** | **~510** | **~1484** |

**Result**: ~74% reduction in duplicated code

### New Capabilities

1. **Clean library API** - Well-organized public interface
2. **Reusable components** - Query engine, storage, graph can be used independently
3. **Extensible architecture** - Easy to add new storage backends, query modes
4. **Example applications** - Clear patterns for library usage
5. **Better testability** - Library logic separated from CLI concerns

### Breaking Changes

Since CLI compatibility can be broken:

1. **CLI commands may change** - Some flags may have different names
2. **Output format may change** - More consistent formatting
3. **Error messages may change** - Unified error handling

**Mitigation**: Provide migration guide and example migrations

---

## Implementation Checklist

### Phase 1: Library Foundation
- [ ] Create src/lib directory structure
- [ ] Extract core types from core/neurona.zig
- [ ] Create src/lib/utils/strings.zig
- [ ] Create src/lib/utils/paths.zig
- [ ] Create src/lib/utils/text.zig
- [ ] Update build.zig for library module
- [ ] Update root.zig to re-export from lib/
- [ ] Run `zig build test` - all tests pass

### Phase 2: Query & Storage Layer
- [ ] Create src/lib/query/engine.zig
- [ ] Create src/lib/query/eql.zig
- [ ] Create src/lib/query/modes.zig
- [ ] Create src/lib/storage/interface.zig
- [ ] Add graph builder to src/lib/core/graph.zig
- [ ] Migrate core storage to lib/
- [ ] Run `zig build test` - all tests pass

### Phase 3: CLI Layer Refactoring
- [ ] Create src/cli directory structure
- [ ] Create src/cli/output/json.zig
- [ ] Create src/cli/output/human.zig
- [ ] Create src/cli/parser/flags.zig
- [ ] Create src/cli/commands/mod.zig
- [ ] Create src/cli/help/generator.zig
- [ ] Create src/cli/app.zig
- [ ] Create new src/cli/main.zig
- [ ] Run `zig build run` - basic functionality works

### Phase 4: Migration & Cleanup
- [ ] Migrate init command
- [ ] Migrate status command
- [ ] Migrate metrics command
- [ ] Migrate show command
- [ ] Migrate query command
- [ ] Migrate trace command
- [ ] Migrate impact command
- [ ] Migrate new command
- [ ] Migrate update command
- [ ] Migrate delete command
- [ ] Migrate link command
- [ ] Migrate sync command
- [ ] Remove deprecated files
- [ ] Update root.zig public API
- [ ] Run `zig build test` - all tests pass
- [ ] Run `zig build run` - all commands work

### Phase 5: Examples & Documentation
- [ ] Create examples/basic_usage.zig
- [ ] Create examples/alm_integration.zig
- [ ] Create examples/custom_query.zig
- [ ] Update README.md
- [ ] Create LIBRARY_API.md
- [ ] Update AGENTS.md
- [ ] Create MIGRATION.md
- [ ] Verify examples compile and run

---

## Risks & Mitigations

### Risk 1: Breaking existing workflows

**Mitigation**:
- Provide comprehensive migration guide
- Keep old CLI behavior where possible
- Clear documentation of changes

### Risk 2: Testing complexity

**Mitigation**:
- Incremental migration with tests at each step
- Keep existing tests passing during transition
- Add integration tests for library API

### Risk 3: Performance regression

**Mitigation**:
- Benchmark before and after refactoring
- Ensure no performance degradation
- Optimize hot paths after refactoring

### Risk 4: Scope creep

**Mitigation**:
- Strict adherence to phases
- Resist adding new features during refactoring
- Focus on deduplication and library separation

---

## Success Criteria

1. **All tests pass**: `zig build test` with zero failures
2. **Build succeeds**: `zig build run` works
3. **Examples compile**: All example applications build and run
4. **Code reduction**: ~1500 lines of duplicated code removed
5. **Public API documented**: LIBRARY_API.md with complete reference
6. **CLI functional**: All commands work with new architecture
7. **Library usable**: Examples demonstrate clean library usage

---

## Timeline Estimate

- **Phase 1**: 2 weeks
- **Phase 2**: 2 weeks
- **Phase 3**: 2 weeks
- **Phase 4**: 2 weeks
- **Phase 5**: 1 week

**Total**: ~9 weeks for complete refactoring

---

## Next Steps

1. Review and approve this plan
2. Decide if phases should be executed sequentially or in parallel
3. Begin Phase 1: Library Foundation
4. Set up CI/CD for continuous testing during refactoring

---

**Status**: Ready for execution
**Last Updated**: 2026-02-12
