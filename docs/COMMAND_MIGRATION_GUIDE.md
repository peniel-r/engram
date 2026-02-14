# Command Migration Guide (Phase 3)

This guide documents the pattern for migrating CLI commands to use Phase 3 utilities.

## Migration Pattern

### 1. Add Imports

Add imports for the Phase 3 utilities at the top of the command file:

```zig
// Import Phase 3 CLI utilities
const JsonOutput = @import("output/json.zig").JsonOutput;
const HumanOutput = @import("output/human.zig").HumanOutput;
```

### 2. Replace Local Output Functions

Replace local `outputJson` and `outputList` (or similar) functions with calls to the shared utilities.

#### Before (duplicated code):
```zig
fn outputList(items: []const Item) !void {
    std.debug.print("\n📋 Items\n", .{});
    for (0..40) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});
    for (items) |item| {
        std.debug.print("  {s}: {s}\n", .{item.id, item.title});
    }
}

fn outputJson(items: []const Item) !void {
    std.debug.print("[", .{});
    for (items, 0..) |item, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{{\"id\":\"{s}\",\"title\":\"{s}\"}}", .{item.id, item.title});
    }
    std.debug.print("]\n", .{});
}
```

#### After (using shared utilities):
```zig
fn outputList(items: []const Item) !void {
    try HumanOutput.printHeader("Items", "📋");
    for (items) |item| {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("  {s}: {s}\n", .{item.id, item.title});
        try stdout.flush();
    }
}

fn outputJson(items: []const Item) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try JsonOutput.beginArray(stdout);
    for (items, 0..) |item, i| {
        if (i > 0) try JsonOutput.separator(stdout, true);
        try JsonOutput.beginObject(stdout);
        try JsonOutput.stringField(stdout, "id", item.id);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.stringField(stdout, "title", item.title);
        try JsonOutput.endObject(stdout);
    }
    try JsonOutput.endArray(stdout);
    try stdout.flush();
}
```

### 3. Remove Local Helper Functions

Remove any local helper functions that are now provided by the shared utilities, such as:
- `printJsonString` - replaced by `JsonOutput` field methods
- Local formatting functions - replaced by `HumanOutput` methods

### 4. Update Error Messages

Replace `std.debug.print` error messages with `HumanOutput` methods:

```zig
// Before
std.debug.print("Error: No cortex found\n", .{});
std.process.exit(1);

// After
try HumanOutput.printError("No cortex found");
std.process.exit(1);
```

## Available Utilities

### JsonOutput

```zig
try JsonOutput.beginArray(stdout);
try JsonOutput.endArray(stdout);
try JsonOutput.beginObject(stdout);
try JsonOutput.endObject(stdout);
try JsonOutput.separator(stdout, true);
try JsonOutput.stringField(stdout, "name", "value");
try JsonOutput.enumField(stdout, "type", enum_value);
try JsonOutput.numberField(stdout, "count", 42);
try JsonOutput.boolField(stdout, "active", true);
try JsonOutput.optionalStringField(stdout, "field", optional_value);
```

### HumanOutput

```zig
try HumanOutput.printHeader("Title", "📋");
try HumanOutput.printSubheader("Subtitle", "→");
try HumanOutput.printSeparator('-', 40);
try HumanOutput.printSuccess("Operation completed");
try HumanOutput.printWarning("Warning message");
try HumanOutput.printError("Error message");
try HumanOutput.printInfo("Info message");
```

## Example: Status Command Migration

The `src/cli/status.zig` file demonstrates a complete migration:

1. ✅ Added imports for JsonOutput and HumanOutput
2. ✅ Replaced `outputList` with HumanOutput utilities
3. ✅ Replaced `outputJson` with JsonOutput utilities
4. ✅ Removed `printJsonString` helper function
5. ✅ Updated error messages to use HumanOutput
6. ✅ Tested both JSON and human output modes

## Testing Checklist

After migrating a command:

- [ ] Command runs without errors
- [ ] JSON output produces valid JSON
- [ ] Human output is readable and formatted
- [ ] All flags work correctly
- [ ] Error messages are consistent
- [ ] Build succeeds (`zig build`)

## Next Steps

After migrating all commands (Phase 3D), update `src/main.zig` (Phase 3C) to:
1. Use the CommandRegistry for centralized command management
2. Remove duplicate help functions
3. Simplify command dispatch logic
4. Reduce main.zig from ~1374 lines to ~80 lines
