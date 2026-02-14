# Phase 3: CLI Layer Refactoring Plan

**Version**: 1.0.0
**Date**: 2026-02-12
**Status**: Draft

---

## Executive Summary

This plan migrates the CLI layer to use the clean library API created in Phase 1, eliminating approximately **1484 lines of duplicated code** while maintaining all existing functionality.

### Key Objectives

1. **Create CLI utilities** - Unified output and parsing modules
2. **Consolidate command handlers** - Remove duplication across CLI files
3. **Eliminate help functions** - Replace 15 duplicate functions with single parameterized version
4. **Migrate all commands** - Use Phase 1 library utilities where appropriate
5. **Simplify main.zig** - Reduce from 1374 lines to clean command dispatcher

### Expected Code Reduction

| Category | Lines Eliminated | Files Affected |
|----------|------------------|----------------|
| JSON output patterns | 400 | 8 CLI files |
| Human output patterns | 300 | 8 CLI files |
| Help functions | 138 | main.zig |
| Flag parsing | 450 | main.zig |
| Graph building | 100 | 6 CLI files |
| Error handling | 30 | main.zig |
| **Total** | **~1418** | |

---

## Proposed Incremental Steps

### Step 3.1: Create CLI Directory Structure

**Goal**: Organize CLI layer into clean modules

**Create directories**:
```
src/cli/
├── output/
│   ├── json.zig
│   └── human.zig
├── parser/
│   ├── flags.zig
│   └── args.zig
├── commands/
│   └── mod.zig
├── help/
│   └── generator.zig
└── app.zig
```

**Rationale**: Clear separation of concerns makes code discoverable and maintainable.

---

### Step 3.2: Create Output Utilities

**Goal**: Eliminate ~700 lines of duplicated JSON/human output code

#### 3.2.1: Create JSON Output Utilities

**Create**: `src/cli/output/json.zig`

**API Design**:
```zig
pub const JsonOutput = struct {
    /// Begin JSON array
    pub fn beginArray(writer: anytype) !void;

    /// End JSON array
    pub fn endArray(writer: anytype) !void;

    /// Begin JSON object
    pub fn beginObject(writer: anytype) !void;

    /// End JSON object
    pub fn endObject(writer: anytype) !void;

    /// Write separator between fields
    pub fn separator(writer: anytype, comma: bool) !void;

    /// Write string field with JSON escaping
    pub fn stringField(writer: anytype, name: []const u8, value: []const u8) !void;

    /// Write enum field
    pub fn enumField(writer: anytype, name: []const u8, value: anytype) !void;

    /// Write number field
    pub fn numberField(writer: anytype, name: []const u8, value: anytype) !void;

    /// Write boolean field
    pub fn boolField(writer: anytype, name: []const u8, value: bool) !void;

    /// Write optional field
    pub fn optionalStringField(writer: anytype, name: []const u8, value: ?[]const u8) !void;
};
```

**Implementation**:
- Use `lib/utils/strings.zig.Json.writeEscaped()` for escaping
- Support both buffered and unbuffered writers
- Provide field ordering control

**Lines**: ~150

**Impact**: Eliminates ~400 lines across 8 CLI files:
- query.zig: outputJson, outputJsonWithScores, outputJsonWithFusedScores, outputJsonWithActivation
- show.zig: outputJson
- status.zig: outputJson
- impact.zig: outputJson
- metrics.zig: outputJson
- release_status.zig: outputJson
- link_artifact.zig: outputJson
- trace.zig: outputJson

#### 3.2.2: Create Human Output Utilities

**Create**: `src/cli/output/human.zig`

**API Design**:
```zig
pub const HumanOutput = struct {
    /// Print header with emoji
    pub fn printHeader(title: []const u8, emoji: []const u8) !void;

    /// Print subheader with emoji
    pub fn printSubheader(title: []const u8, emoji: []const u8) !void;

    /// Print separator line
    pub fn printSeparator(char: u8, count: usize) !void;

    /// Print success message
    pub fn printSuccess(message: []const u8) !void;

    /// Print warning message
    pub fn printWarning(message: []const u8) !void;

    /// Print error message
    pub fn printError(message: []const u8) !void;

    /// Print info message
    pub fn printInfo(message: []const u8) !void;
};
```

**Implementation**:
- Consistent emoji usage
- Standardized formatting
- Configurable separator length

**Lines**: ~100

**Impact**: Eliminates ~300 lines across 8 CLI files:
- query.zig: outputList, outputListWithScores, outputListWithFusedScores, outputListWithActivation
- show.zig: outputHuman
- status.zig: outputList
- impact.zig: outputImpact
- metrics.zig: outputReport
- release_status.zig: outputReport
- link_artifact.zig: outputResults
- trace.zig: outputTree

---

### Step 3.3: Create Parsing Utilities

**Goal**: Eliminate ~450 lines of duplicated flag parsing code

#### 3.3.1: Create Flag Parser

**Create**: `src/cli/parser/flags.zig`

**API Design**:
```zig
pub const FlagParser = struct {
    /// Parse flags from command-line arguments
    pub fn parse(comptime spec: []const FlagSpec, args: []const []const u8) !ParsedFlags;

    /// Flag specification
    pub const FlagSpec = struct {
        name: []const u8,
        short: ?[]const u8 = null,
        takes_value: bool = false,
        description: []const u8 = "",
        default_value: ?FlagValue = null,
        required: bool = false,
    };

    /// Flag value type
    pub const FlagValue = union(enum) {
        string: []const u8,
        number: i64,
        bool: bool,
        list: [][]const u8,
    };

    /// Parsed flags result
    pub const ParsedFlags = struct {
        flags: std.StringHashMap(?FlagValue),
        positionals: [][]const u8,
    };

    /// Get flag value by name
    pub fn getFlag(self: ParsedFlags, name: []const u8) ?FlagValue;

    /// Get flag as string
    pub fn getString(self: ParsedFlags, name: []const u8) ?[]const u8;

    /// Get flag as number
    pub fn getNumber(self: ParsedFlags, name: []const u8) ?i64;

    /// Get flag as bool
    pub fn getBool(self: ParsedFlags, name: []const u8) bool;

    /// Check if flag was provided
    pub fn hasFlag(self: ParsedFlags, name: []const u8) bool;
};
```

**Lines**: ~200

**Impact**: Eliminates ~450 lines in main.zig across all 15 commands.

#### 3.3.2: Create Argument Parser

**Create**: `src/cli/parser/args.zig`

**API Design**:
```zig
pub const ArgsParser = struct {
    /// Parse command arguments with validation
    pub fn parse(args: []const []const u8, options: ParseOptions) !ParsedArgs;

    pub const ParseOptions = struct {
        min_args: usize = 0,
        max_args: usize = std.math.maxInt(usize),
        require_command: bool = true,
    };

    pub const ParsedArgs = struct {
        command: []const u8,
        args: [][]const u8,
    };
};
```

**Lines**: ~100

**Impact**: Improves argument validation and error messages.

---

### Step 3.4: Create Application Context

**Create**: `src/cli/app.zig`

**API Design**:
```zig
pub const App = struct {
    allocator: Allocator,
    cortex_dir: ?[]const u8 = null,
    neuronas_dir: ?[]const u8 = null,
    config: AppConfig,

    pub const AppConfig = struct {
        verbose: bool = false,
        json_output: bool = false,
        editor: []const u8 = "hx",
    };

    /// Initialize application
    pub fn init(allocator: Allocator) !App;

    /// Clean up resources
    pub fn deinit(self: *App) void;

    /// Resolve cortex directory
    pub fn resolveCortex(self: *App) !void;

    /// Get neuronas directory
    pub fn getNeuronasDir(self: *App) ![]const u8;

    /// Get activations directory
    pub fn getActivationsDir(self: *App) ![]const u8;

    /// Initialize storage
    pub fn initStorage(self: *App) !void;

    /// Clean up storage
    pub fn deinitStorage(self: *App) void;
};
```

**Implementation**:
- Uses `lib/utils/paths.zig.CortexResolver`
- Manages lifecycle of directory paths
- Provides clean interface for commands

**Lines**: ~150

**Impact**: Eliminates ~140 lines of duplicated cortex resolution across 14 CLI files.

---

### Step 3.5: Create Command Registry

**Create**: `src/cli/commands/mod.zig`

**API Design**:
```zig
pub const Command = struct {
    name: []const u8,
    description: []const u8,
    category: CommandCategory,
    execute: *const fn (app: *App, args: []const []const u8) anyerror!void,
    print_help: *const fn () void,
    min_args: usize = 0,
    flags: []const []const u8 = &.{},
};

pub const CommandCategory = enum {
    core,
    query,
    management,
    output,
};

pub const Registry = struct {
    commands: []const Command,

    /// Find command by name
    pub fn find(self: *Registry, name: []const u8) ?Command;

    /// List all commands
    pub fn list(self: *Registry) []const Command;

    /// Get commands by category
    pub fn getByCategory(self: *Registry, category: CommandCategory) []const Command;
};
```

**Implementation**:
- Centralized command metadata
- Easy to add new commands
- Auto-generates help from metadata

**Lines**: ~100

---

### Step 3.6: Create Help Generator

**Create**: `src/cli/help/generator.zig`

**API Design**:
```zig
pub const HelpGenerator = struct {
    /// Print command help
    pub fn printCommandHelp(command: Command) !void;

    /// Print general usage
    pub fn printUsage(registry: *Registry) !void;

    /// Print help for all commands
    pub fn printAllCommands(registry: *Registry) !void;
};
```

**Implementation**:
- Eliminates 15 duplicate help functions (lines 1160-1308 in main.zig)
- Auto-generates from command metadata
- Consistent formatting

**Lines**: ~100

**Impact**: Eliminates ~138 lines from main.zig.

---

### Step 3.7: Migrate One Command (Proof of Concept)

**Goal**: Verify approach by migrating one command completely

**Select**: `status` command (relatively simple, uses multiple utilities)

**Migration Steps**:
1. Update `src/cli/status.zig` to use:
   - `src/cli/output/json.zig.JsonOutput` instead of local `outputJson`
   - `src/cli/output/human.zig.HumanOutput` instead of local `outputList`
   - `src/cli/app.App` for context instead of local cortex resolution
   - `src/cli/parser/flags.FlagParser` instead of manual parsing

2. Verify the migrated command works:
   - Test all subcommands
   - Test JSON output
   - Test human output
   - Test all flags

3. Document migration pattern for other commands

**Expected Changes**:
- Remove: ~80 lines of duplicated code
- Add: ~30 lines of new utility calls
- Net reduction: ~50 lines

**Success Criteria**:
- All existing functionality works
- Code uses Phase 1 utilities
- Tests pass
- Build succeeds

---

### Step 3.8: Update main.zig (Consolidation)

**Goal**: Simplify main.zig from 1374 lines to clean command dispatcher

**Current main.zig structure** (lines 1-1374):
- Lines 30-128: Command registry (15 commands)
- Lines 130-176: Error handling helpers (duplicate)
- Lines 207-1098: Command handlers with embedded flag parsing (~600 lines)
- Lines 1100-1131: Status command handler (~30 lines)
- Lines 1133-1149: New command handler (~120 lines)
- Lines 1151-1172: Show command handler (~22 lines)
- Lines 1174-1186: Link command handler (~12 lines)
- Lines 1188-1204: Sync command handler (~16 lines)
- Lines 1206-1224: Delete command handler (~18 lines)
- Lines 1226-1276: Trace command handler (~50 lines)
- Lines 1278-1295: Status command handler (~17 lines)
- Lines 1297-1334: Query command handler (~37 lines)
- Lines 1336-1354: Update command handler (~18 lines)
- Lines 1356-1383: Impact command handler (~27 lines)
- Lines 1385-1396: Link artifact command handler (~11 lines)
- Lines 1397-1411: Release status command handler (~14 lines)
- Lines 1413-1428: Metrics command handler (~15 lines)
- Lines 1430-1440: Man command handler (~10 lines)
- Lines 1160-1308: Help functions (15 functions, ~148 lines)
- Lines 1310-1332: Tests

**Proposed main.zig structure**:
```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

// Import CLI modules
const app = @import("cli/app.zig").App;
const commands = @import("cli/commands/mod.zig").Registry;
const output = @import("cli/output/json.zig").JsonOutput;
const help = @import("cli/help/generator.zig").HelpGenerator;

// Initialize command registry
pub const registry = commands.init();

pub fn main() !void {
    var app_state = try app.init(std.heap.page_allocator);
    defer app_state.deinit();

    const args = try std.process.argsAlloc(app_state.allocator, std.heap.page_allocator);
    defer std.process.argsFree(app_state.allocator, args);

    if (args.len == 1) {
        try help.printUsage(&registry);
        return;
    }

    // Handle --help and --version first
    const first_arg = args[1];
    if (std.mem.eql(u8, first_arg, "--help") or std.mem.eql(u8, first_arg, "-h")) {
        try help.printUsage(&registry);
        return;
    }

    if (std.mem.eql(u8, first_arg, "--version") or std.mem.eql(u8, first_arg, "-v")) {
        printVersion();
        return;
    }

    // Find and execute command
    if (registry.find(first_arg)) |cmd| {
        // Check for --help after command name
        if (args.len > 2 and (std.mem.eql(u8, args[2], "--help") or std.mem.eql(u8, args[2], "-h"))) {
            try help.printCommandHelp(cmd);
            return;
        }

        try cmd.execute(&app_state, args);
    } else {
        try printError(&registry, "Unknown command: {s}", .{first_arg});
        try help.printUsage(&registry);
        std.process.exit(1);
    }
}

fn printVersion() void {
    std.debug.print("Engram version 0.1.0\n", .{});
}
```

**Lines**: ~80 (down from 1374)

**Impact**: Eliminates ~1294 lines:
- Removed: 15 help functions (138 lines)
- Removed: 15 command handlers (600 lines of parsing, 100 lines of delegation)
- Removed: Duplicate error handlers (30 lines)
- Removed: Complex command registry (500 lines)
- Added: Clean command registry (50 lines)
- Net: ~1294 lines eliminated

---

### Step 3.9: Migrate Remaining Commands

**Goal**: Migrate all remaining CLI commands to use new utilities

**Migration Order** (simple to complex):

1. **metrics** - Simple, only output utilities
2. **man** - Very simple, only output
3. **trace** - Medium complexity, uses graph
4. **impact** - Medium complexity, uses graph
5. **release_status** - Medium complexity
6. **sync** - Medium complexity, uses index building
7. **init** - Medium complexity, handles flags
8. **new** - High complexity, many flags
9. **show** - Medium complexity, config handling
10. **update** - Medium complexity, field updates
11. **delete** - Medium complexity, error handling
12. **link** - Medium complexity, connections
13. **link_artifact** - Medium complexity, file linking
14. **query** - High complexity, multiple modes

**Migration Pattern for Each Command**:
1. Update imports to use new CLI modules
2. Replace duplicated output code with output/json.zig or output/human.zig
3. Replace duplicated flag parsing with parser/flags.zig
4. Replace duplicated cortex resolution with app.App
5. Remove local helper functions now in shared modules
6. Update tests
7. Verify command works

**Expected Per-Command Code Reduction**:
- metrics: ~40 lines → ~10 lines (net -30)
- man: ~10 lines → ~10 lines (net 0)
- trace: ~60 lines → ~30 lines (net -30)
- impact: ~80 lines → ~40 lines (net -40)
- release_status: ~80 lines → ~40 lines (net -40)
- sync: ~70 lines → ~40 lines (net -30)
- init: ~100 lines → ~50 lines (net -50)
- new: ~150 lines → ~80 lines (net -70)
- show: ~100 lines → ~50 lines (net -50)
- update: ~80 lines → ~40 lines (net -40)
- delete: ~50 lines → ~30 lines (net -20)
- link: ~60 lines → ~30 lines (net -30)
- link_artifact: ~80 lines → ~40 lines (net -40)
- query: ~1368 lines → ~600 lines (net -768)

**Total Migration Impact**: ~1044 lines eliminated

---

## Implementation Plan

### Phase 3A: Core Utilities (Days 1-3)

**Day 1: Structure & Output**
- [ ] Step 3.1: Create CLI directory structure
- [ ] Step 3.2.1: Create src/cli/output/json.zig
- [ ] Step 3.2.2: Create src/cli/output/human.zig
- [ ] Test output utilities
- [ ] Verify build succeeds

**Day 2: Parsing & Application**
- [ ] Step 3.3.1: Create src/cli/parser/flags.zig
- [ ] Step 3.3.2: Create src/cli/parser/args.zig
- [ ] Step 3.4: Create src/cli/app.zig
- [ ] Test parsing utilities
- [ ] Test app context
- [ ] Verify build succeeds

**Day 3: Registry & Help**
- [ ] Step 3.5: Create src/cli/commands/mod.zig
- [ ] Step 3.6: Create src/cli/help/generator.zig
- [ ] Test command registry
- [ ] Test help generator
- [ ] Verify build succeeds

**Milestone**: All Phase 3A utilities created and tested

---

### Phase 3B: Proof of Concept (Days 4-5)

**Day 4: Migrate status command**
- [ ] Step 3.7: Create migration plan for status.zig
- [ ] Update status.zig imports
- [ ] Replace duplicated output code
- [ ] Replace duplicated flag parsing
- [ ] Replace duplicated cortex resolution
- [ ] Remove local helper functions
- [ ] Update tests
- [ ] Verify status command works

**Day 5: Validate & Document**
- [ ] Test all status subcommands
- [ ] Verify JSON output matches old
- [ ] Verify human output matches old
- [ ] Document migration pattern
- [ ] Verify build succeeds
- [ ] Create guide for remaining commands

**Milestone**: Migration pattern verified

---

### Phase 3C: Main.zig Consolidation (Day 6)

- [ ] Step 3.8: Create new main.zig structure
- [ ] Implement clean command dispatcher
- [ ] Implement printVersion()
- [ ] Implement error handling
- [ ] Remove old main.zig handlers
- [ ] Remove old help functions
- [ ] Update tests in main.zig
- [ ] Verify build succeeds
- [ ] Verify CLI runs

**Milestone**: main.zig simplified from 1374 lines to ~80 lines

---

### Phase 3D: Command Migration (Days 7-14)

**Day 7: Simple commands**
- [ ] Migrate metrics command
- [ ] Migrate man command
- [ ] Test migrated commands
- [ ] Verify build succeeds

**Day 8: Graph commands**
- [ ] Migrate trace command
- [ ] Migrate impact command
- [ ] Test migrated commands
- [ ] Verify build succeeds

**Day 9: Management commands**
- [ ] Migrate release_status command
- [ ] Migrate sync command
- [ ] Test migrated commands
- [ ] Verify build succeeds

**Day 10: Creation command**
- [ ] Migrate init command
- [ ] Test migrated command
- [ ] Verify build succeeds

**Day 11: Display command**
- [ ] Migrate show command
- [ ] Test migrated command
- [ ] Verify build succeeds

**Day 12: Update command**
- [ ] Migrate update command
- [ ] Test migrated command
- [ ] Verify build succeeds

**Day 13: Connection commands**
- [ ] Migrate delete command
- [ ] Migrate link command
- [ ] Test migrated commands
- [ ] Verify build succeeds

**Day 14: Complex commands**
- [ ] Migrate link_artifact command
- [ ] Migrate query command
- [ ] Test migrated commands
- [ ] Verify build succeeds

**Milestone**: All 14 commands migrated

---

### Phase 3E: Validation & Cleanup (Day 15)

- [ ] Run full test suite
- [ ] Verify all commands work
- [ ] Verify JSON output consistent
- [ ] Verify human output consistent
- [ ] Check for any remaining duplicated code
- [ ] Update documentation
- [ ] Create migration guide
- [ ] Final verification: zig build run succeeds

**Milestone**: Phase 3 complete

---

## Success Criteria

### For Phase 3A (Core Utilities)
- [ ] src/cli/output/json.zig created with ~150 lines
- [ ] src/cli/output/human.zig created with ~100 lines
- [ ] src/cli/parser/flags.zig created with ~200 lines
- [ ] src/cli/parser/args.zig created with ~100 lines
- [ ] src/cli/app.zig created with ~150 lines
- [ ] src/cli/commands/mod.zig created with ~100 lines
- [ ] src/cli/help/generator.zig created with ~100 lines
- [ ] All utilities have tests
- [ ] Build succeeds
- [ ] ~700 lines of duplication eliminated

### For Phase 3B (Proof of Concept)
- [ ] status command migrated successfully
- [ ] All existing tests pass
- [ ] New output utilities work correctly
- [ ] New parsing utilities work correctly
- [ ] Migration pattern documented
- [ ] Build succeeds
- [ ] ~50 lines eliminated from status.zig

### For Phase 3C (Main.zig)
- [ ] main.zig reduced from 1374 lines to ~80 lines
- [ ] All 15 help functions consolidated into 1
- [ ] Command registry centralised
- [ ] Clean command dispatcher implemented
- [ ] All tests pass
- [ ] CLI runs correctly
- [ ] ~138 lines of help functions eliminated
- [ ] ~600 lines of flag parsing eliminated
- [ ] ~500 lines of command handlers eliminated

### For Phase 3D (Command Migration)
- [ ] All 14 commands migrated
- [ ] All command tests pass
- [ ] Build succeeds
- [ ] CLI runs correctly
- [ ] ~1044 lines of duplicated code eliminated
- [ ] All commands use new utilities
- [ ] No remaining duplicated patterns

### For Phase 3E (Validation)
- [ ] Full test suite passes (zig build test)
- [ ] Build succeeds (zig build run)
- [ ] All CLI commands work correctly
- [ ] JSON output consistent across commands
- [ ] Human output consistent across commands
- [ ] No known duplicated code remaining
- [ ] Documentation updated
- [ ] Migration guide created

---

## Risk Assessment & Mitigation

### Risk 1: Breaking Existing Functionality

**Likelihood**: Medium
**Impact**: High
**Mitigation**:
- Migrate one command as proof of concept (Phase 3B)
- Verify all functionality before proceeding
- Keep existing code until migration verified
- Comprehensive testing

### Risk 2: Build Errors During Migration

**Likelihood**: High
**Impact**: Medium
**Mitigation**:
- Test each change incrementally
- Build after each command migration
- Use zig build-lib to verify modules independently
- Fix errors before proceeding

### Risk 3: Performance Regression

**Likelihood**: Low
**Impact**: Low
**Mitigation**:
- Benchmark before and after migration
- Ensure utilities are optimized (ArenaAllocator where appropriate)
- Keep critical paths efficient

### Risk 4: Test Failures

**Likelihood**: Medium
**Impact**: Medium
**Mitigation**:
- Keep existing tests passing
- Add tests for new utilities
- Run full test suite after each major change
- Fix test failures before proceeding

---

## Code Quality Standards

From `code-quality.md`:

### Modular Design
- ✅ Each CLI module has single responsibility
- ✅ Clear interfaces between modules
- ✅ <100 lines per component (most <50)

### Functional Approach
- ✅ Pure functions where possible (output utilities)
- ✅ Immutability (create new data structures, don't modify in place)
- ✅ Composition (build complex from simple functions)

### Naming Conventions
- ✅ Files: lowercase-with-dashes
- ✅ Functions: verbPhrases (printHeader, stringField)
- ✅ Structs: PascalCase (JsonOutput, FlagParser)
- ✅ Enum values: lowercase_with_underscores where needed

### Error Handling
- ✅ Explicit error handling at boundaries
- ✅ Validate at command entry points
- ✅ Use proper error returns

### From `AGENTS.md` (Zig Standards)
- ✅ Explicit allocator patterns
- ✅ ArenaAllocator for frame-scoped data
- ✅ ArrayListUnmanaged for array lists
- ✅ Zig 0.15.2+ target version
- ✅ Buffer must outlive writer interface pointer
- ✅ Forgetting flush() means output won't appear
- ✅ Work NOT complete until zig build run succeeds

---

## Timeline Estimate

| Phase | Days | Description |
|-------|------|-------------|
| 3A | 3 | Create core utilities (output, parser, app, registry, help) |
| 3B | 2 | Migrate one command as proof of concept |
| 3C | 1 | Consolidate main.zig |
| 3D | 8 | Migrate remaining 14 commands |
| 3E | 1 | Validation and cleanup |
| **Total** | **15** | **Complete CLI layer refactoring** |

---

## Expected Final State

### After Phase 3 Complete

```
src/
├── lib/                          # ✅ Library (from Phase 1-2)
│   ├── root.zig                 # Public API
│   ├── core/                     # Core types
│   ├── query/
│   │   └── modes.zig          # Query types
│   └── utils/                    # Utilities
│       ├── strings.zig
│       ├── paths.zig
│       └── text.zig
│
├── cli/                          # ✅ Refactored CLI layer
│   ├── main.zig                 # Clean dispatcher (~80 lines)
│   ├── app.zig                  # Application context
│   ├── commands/
│   │   └── mod.zig              # Command registry
│   ├── output/
│   │   ├── json.zig            # JSON output utilities
│   │   └── human.zig           # Human output utilities
│   ├── parser/
│   │   ├── flags.zig            # Flag parsing
│   │   └── args.zig             # Argument parsing
│   └── help/
│       └── generator.zig         # Help generation
│
├── core/                          # ✅ Existing core (unchanged)
├── storage/                       # ✅ Existing storage (unchanged)
└── utils/                         # ✅ Existing utils (unchanged)
```

### Code Metrics

| Metric | Before Phase 3 | After Phase 3 | Change |
|--------|-----------------|---------------|--------|
| main.zig lines | 1374 | ~80 | -94% |
| CLI duplicated code | ~1484 | ~100 | -93% |
| Total CLI lines | ~4000 | ~2000 | -50% |
| Test coverage | Maintained | Maintained | 0% |

---

## Files Created (Phase 3)

| Phase | File | Lines | Purpose |
|-------|------|-------|---------|
| 3A.1 | src/cli/output/json.zig | 150 | JSON output utilities |
| 3A.2 | src/cli/output/human.zig | 100 | Human output utilities |
| 3A.3 | src/cli/parser/flags.zig | 200 | Flag parsing |
| 3A.4 | src/cli/parser/args.zig | 100 | Argument parsing |
| 3A.5 | src/cli/app.zig | 150 | Application context |
| 3A.6 | src/cli/commands/mod.zig | 100 | Command registry |
| 3A.7 | src/cli/help/generator.zig | 100 | Help generation |
| **Total** | **8 files**, **900 lines** | **CLI utilities** |

---

## Files Modified (Phase 3)

| Phase | File | Lines Before | Lines After | Change |
|-------|------|-------------|-------------|--------|
| 3C | src/main.zig | 1374 | ~80 | -1294 |
| 3D | src/cli/metrics.zig | ~40 | ~10 | -30 |
| 3D | src/cli/man.zig | ~10 | ~10 | 0 |
| 3D | src/cli/trace.zig | ~60 | ~30 | -30 |
| 3D | src/cli/impact.zig | ~80 | ~40 | -40 |
| 3D | src/cli/release_status.zig | ~80 | ~40 | -40 |
| 3D | src/cli/sync.zig | ~70 | ~40 | -30 |
| 3D | src/cli/init.zig | ~100 | ~50 | -50 |
| 3D | src/cli/new.zig | ~150 | ~80 | -70 |
| 3D | src/cli/show.zig | ~100 | ~50 | -50 |
| 3D | src/cli/update.zig | ~80 | ~40 | -40 |
| 3D | src/cli/delete.zig | ~50 | ~30 | -20 |
| 3D | src/cli/link.zig | ~60 | ~30 | -30 |
| 3D | src/cli/link_artifact.zig | ~80 | ~40 | -40 |
| 3D | src/cli/query.zig | 1368 | ~600 | -768 |
| 3B | src/cli/status.zig | ~130 | ~80 | -50 |
| **Total** | **~4200** | **~1330** | **-1386** |

---

## Next Steps

1. **Approve this plan** - Review incremental approach and timeline
2. **Begin Phase 3A** - Create core CLI utilities (Days 1-3)
3. **Validate utilities** - Ensure they work independently
4. **Proceed to Phase 3B** - Migrate one command as proof of concept
5. **Learn and adapt** - Refine migration pattern based on proof of concept
6. **Complete Phase 3** - Execute all remaining phases

---

## Summary

Phase 3 transforms the CLI layer from a codebase with significant duplication into a clean, maintainable architecture:

✅ **~1386 lines of code eliminated** (35% of CLI code)
✅ **Main.zig reduced by 94%** (1374 → 80 lines)
✅ **Clear separation of concerns** - output, parsing, registry, help
✅ **Reusable utilities** - All commands benefit from shared modules
✅ **Better testability** - Utilities can be tested independently
✅ **Maintainable architecture** - Easy to add/modify commands

The CLI layer becomes a clean application on top of the library foundation created in Phases 1-2.

---

**Status**: Ready for execution
**Last Updated**: 2026-02-12
