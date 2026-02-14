# Engram Library API Reference

**Version**: 1.0.0
**Date**: 2026-02-13

---

## Overview

The Engram library provides core primitives for the Neurona Knowledge Protocol. It enables applications to create, manage, and query knowledge graphs with structured connections.

## Installation

Add Engram as a dependency to your `build.zig.zon`:

```zig
.{
    .name = "my_project",
    .dependencies = .{
        .engram = .{
            .url = "https://github.com/peniel-r/engram/archive/{version}.tar.gz",
            .hash = "{hash}",
        },
    },
}
```

Or use the local source:

```zig
const engram = b.dependency("engram", .{
    .target = target,
});

const exe = b.addExecutable(.{
    // ...
    .imports = &.{
        .{ .name = "Engram", .module = engram.module("Engram") },
    },
});
```

## Core Types

### Neurona

The main data structure representing a knowledge node.

```zig
const Engram = @import("Engram");

var neurona = try Engram.Neurona.init(allocator);
defer neurona.deinit(allocator);

neurona.id = "concept.001";
neurona.title = "My Concept";
neurona.type = .concept;
```

**Fields**:
- `id: []const u8` - Unique identifier
- `title: []const u8` - Display title
- `tags: std.ArrayListUnmanaged([]const u8)` - Category tags
- `type: NeuronaType` - Node type (concept, requirement, test_case, issue, etc.)
- `connections: std.StringHashMapUnmanaged(ConnectionGroup)` - Linked neuronas
- `updated: []const u8` - Last modification timestamp
- `language: []const u8` - Language code (default: "en")
- `hash: ?[]const u8` - Content hash (Tier 3)
- `llm_metadata: ?LLMMetadata` - AI optimization metadata (Tier 3)
- `context: Context` - Type-specific context (Tier 3)

**Methods**:
- `init(allocator) !Neurona` - Create with defaults
- `deinit(allocator) void` - Free all memory
- `addConnection(allocator, connection) !void` - Add a connection
- `getConnections(conn_type) []const Connection` - Get connections by type
- `isTier2() bool` - Has Tier 2 features
- `isTier3() bool` - Has Tier 3 features

### NeuronaType

Enumeration of node types:

```zig
pub const NeuronaType = enum {
    concept,      // General purpose
    reference,   // Docs, definitions
    artifact,     // Code snippets
    state_machine,
    lesson,       // Educational content
    requirement, // ALM: Requirement
    test_case,   // ALM: Test case
    issue,       // ALM: Issue/bug
    feature,      // ALM: Feature
};
```

### Connection

Represents a directed link between neuronas:

```zig
const conn = Engram.Connection{
    .target_id = "concept.002",
    .connection_type = .parent,
    .weight = 90, // 0-100
};
```

### ConnectionType

15 semantic connection types:

```zig
// Hierarchical
.parent, .child

// Validation
.validates, .validated_by

// Blocking
.blocks, .blocked_by

// Implementation
.implements, .implemented_by

// Testing
.tested_by, .tests

// Relationships
.relates_to, .prerequisite, .next, .related, .opposes
```

**Parser**: `ConnectionType.fromString("parent") ?ConnectionType`

### Context

Type-specific metadata (Tier 3). Use `switch` to access:

```zig
switch (neurona.context) {
    .requirement => |ctx| {
        std.debug.print("Status: {s}\n", .{ctx.status});
    },
    .test_case => |ctx| {
        std.debug.print("Framework: {s}\n", .{ctx.framework});
    },
    .issue => |ctx| {
        std.debug.print("Priority: {d}\n", .{ctx.priority});
    },
    else => {},
}
```

**Context Types**:
- `requirement`: status, verification_method, priority, assignee, effort_points, sprint
- `test_case`: framework, test_file, status, priority, assignee, duration, last_run
- `issue`: status, priority, assignee, created, resolved, closed, blocked_by, related_to
- `artifact`: runtime, file_path, safe_to_exec, language_version, last_modified
- `state_machine`: triggers, entry_action, exit_action, allowed_roles
- `custom`: std.StringHashMap for arbitrary key-value pairs

## Utilities

### Json

JSON string escaping for output:

```zig
const escaped = try Engram.Json.formatEscaped("Hello \"World\"", allocator);
defer allocator.free(escaped);
// Output: "Hello \"World\""
```

### TextProcessor

Text processing utilities:

```zig
// Tokenize text into words
const words = try Engram.TextProcessor.tokenizeToWords(allocator, "Hello World");
defer {
    for (words) |w| allocator.free(w);
    allocator.free(words);
}

// Convert to lowercase
const lower = try Engram.TextProcessor.toLower(allocator, "HELLO");
defer allocator.free(lower);

// Combine title and tags
const combined = try Engram.TextProcessor.combineTitleAndTags(
    allocator, 
    "My Title", 
    &[_][]const u8{"tag1", "tag2"}
);
defer allocator.free(combined);
```

### CortexResolver

Find and resolve cortex directories:

```zig
// Find cortex in current directory or parent
const cortex_dir = try Engram.CortexResolver.find(allocator, null);

// Find cortex at specific path
const cortex_dir = try Engram.CortexResolver.find(allocator, "/path/to/project");
```

## Query Patterns

### Filter by Type

```zig
for (neuronas.items) |n| {
    if (n.type == .requirement) {
        // Process requirement
    }
}
```

### Filter by Tag

```zig
for (neuronas.items) |n| {
    for (n.tags.items) |tag| {
        if (std.mem.eql(u8, tag, "security")) {
            // Process tagged neurona
        }
    }
}
```

### Filter by Connection

```zig
const parent_conns = neurona.getConnections(.parent);
for (parent_conns) |conn| {
    std.debug.print("Parent: {s}\n", .{conn.target_id});
}
```

### Neural Activation Traversal

```zig
// BFS with decay
var queue = std.ArrayListUnmanaged(struct { id: []const u8, weight: f64 }){};
try queue.append(allocator, .{ .id = seed_id, .weight = 1.0 });

while (queue.pop()) |item| {
    // Process with activation weight
    const new_weight = item.weight * decay_rate;
    // Queue neighbors...
}
```

## Examples

See the `examples/` directory:

- `basic_usage.zig` - Creating neuronas, connections, using utilities
- `alm_integration.zig` - ALM workflows with requirements, tests, issues
- `custom_query.zig` - Advanced filtering and graph traversal

Run with:
```bash
zig build example-basic
zig build example-alm
zig build example-query
```

## Notes

- All string fields are heap-allocated; use `deinit()` to free
- The library uses `std.ArrayListUnmanaged` and `std.StringHashMapUnmanaged` internally
- Context variants use managed types (`std.StringHashMap`) for compatibility

---

*Part of the Neurona Knowledge Protocol ecosystem.*
