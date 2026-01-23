// File: src/cli/query.zig
// The `engram query` command for searching Neuronas
// Supports type, tag, and connection filters

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const storage = @import("../root.zig").storage;

/// Query configuration
pub const QueryConfig = struct {
    filters: []QueryFilter,
    limit: ?usize = null,
    json_output: bool = false,
};

/// Query filter types
pub const QueryFilter = union(enum) {
    /// Filter by Neurona type (issue, requirement, test_case, etc.)
    type_filter: TypeFilter,

    /// Filter by tags
    tag_filter: TagFilter,

    /// Filter by connection
    connection_filter: ConnectionFilter,

    /// Filter by metadata field
    field_filter: FieldFilter,
};

pub const TypeFilter = struct {
    types: std.ArrayList([]const u8),
    include: bool = true,

    pub fn deinit(self: *TypeFilter, allocator: Allocator) void {
        for (self.types.items) |t| {
            allocator.free(t);
        }
        self.types.deinit(allocator);
    }
};

pub const TagFilter = struct {
    tags: std.ArrayList([]const u8),
    include: bool = true,

    pub fn deinit(self: *TagFilter, allocator: Allocator) void {
        for (self.tags.items) |t| {
            allocator.free(t);
        }
        self.tags.deinit(allocator);
    }
};

pub const ConnectionOperator = enum {
    @"and",
    @"or",
    not,
};

pub const ConnectionFilter = struct {
    connection_type: ?[]const u8 = null,
    target_id: ?[]const u8 = null,
    operator: ConnectionOperator = .@"and",
};

pub const FieldFilter = struct {
    field: []const u8,
    value: ?[]const u8 = null,
    operator: FieldOperator = .equal,

    pub const FieldOperator = enum {
        equal,
        not_equal,
        contains,
        not_contains,
    };
};

/// Main command handler
pub fn execute(allocator: Allocator, config: QueryConfig) !void {
    // Step 1: Scan all Neuronas
    const neuronas = try storage.scanNeuronas(allocator, "neuronas");
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    if (config.filters.len == 0 and config.limit == null) {
        // No filters, show all
        if (config.json_output) {
            try outputJson(allocator, neuronas);
        } else {
            try outputList(allocator, neuronas);
        }
        return;
    }

    // Step 2: Apply filters
    var results = std.ArrayListUnmanaged(*const Neurona){};
    defer results.deinit(allocator);

    var count: usize = 0;

    for (neuronas) |*neurona| {
        if (matchesFilters(neurona, config.filters)) {
            try results.append(allocator, neurona);
            count += 1;

            if (config.limit) |limit| {
                if (count >= limit) break;
            }
        }
    }

    // Step 3: Sort results (by id for now)
    const sorted = try results.toOwnedSlice(allocator);
    defer allocator.free(sorted);

    // Step 4: Output - Dereference pointers for output
    var output_neuronas = std.ArrayListUnmanaged(Neurona){};
    defer output_neuronas.deinit(allocator);
    
    for (sorted) |n| {
        try output_neuronas.append(allocator, n.*);
    }
    
    if (config.json_output) {
        try outputJson(allocator, output_neuronas.items);
    } else {
        try outputList(allocator, output_neuronas.items);
    }
}

/// Check if Neurona matches all filters
fn matchesFilters(neurona: *const Neurona, filters: []const QueryFilter) bool {
    if (filters.len == 0) return true;

    for (filters) |filter| {
        if (!matchesFilter(neurona, filter)) return false;
    }
    return true;
}

/// Match a single filter
fn matchesFilter(neurona: *const Neurona, filter: QueryFilter) bool {
    return switch (filter) {
        .type_filter => |tf| matchesTypeFilter(neurona, tf),
        .tag_filter => |tf| matchesTagFilter(neurona, tf),
        .connection_filter => |cf| matchesConnectionFilter(neurona, cf),
        .field_filter => |ff| matchesFieldFilter(neurona, ff),
    };
}

/// Match type filter
fn matchesTypeFilter(neurona: *const Neurona, filter: TypeFilter) bool {
    const type_str = @tagName(neurona.type);
    for (filter.types.items) |t| {
        if (filter.include) {
            if (std.mem.eql(u8, type_str, t)) return true;
        } else {
            if (std.mem.eql(u8, type_str, t)) return false;
        }
    }
    return !filter.include;
}

/// Match tag filter
fn matchesTagFilter(neurona: *const Neurona, filter: TagFilter) bool {
    for (filter.tags.items) |tag| {
        for (neurona.tags.items) |neurona_tag| {
            if (std.mem.eql(u8, neurona_tag, tag)) {
                return filter.include;
            }
        }
    }
    return !filter.include;
}

/// Match connection filter
fn matchesConnectionFilter(neurona: *const Neurona, filter: ConnectionFilter) bool {
    var conn_it = neurona.connections.iterator();
    var has_match = false;

    while (conn_it.next()) |entry| {
        for (entry.value_ptr.connections.items) |*conn| {
            const conn_matches = matchesSingleConnection(conn, filter);

            if (conn_matches and filter.operator == .@"and") {
                has_match = true;
                break; // At least one match required
            }

            if (conn_matches and filter.operator == .not) {
                return false; // Found a match when we should NOT match
            }
            
            if (conn_matches) has_match = true;
        }
    }

    return switch (filter.operator) {
        .@"or" => has_match, // Found at least one match
        .not => !has_match,
        .@"and" => has_match,
    };
}

/// Match a single connection
fn matchesSingleConnection(conn: *const @import("../core/neurona.zig").Connection, filter: ConnectionFilter) bool {
    if (filter.connection_type) |ct| {
        const type_name = @tagName(conn.connection_type);
        if (std.mem.eql(u8, type_name, ct)) {
            return true;
        }
    }

    if (filter.target_id) |tid| {
        if (std.mem.eql(u8, conn.target_id, tid)) {
            return true;
        }
    }

    return false;
}

/// Match field filter
fn matchesFieldFilter(neurona: *const Neurona, filter: FieldFilter) bool {
    // For now, just check basic fields (id, title, type, status)
    const value = filter.value orelse return false;

    if (std.mem.eql(u8, filter.field, "id")) {
        return std.mem.eql(u8, neurona.id, value);
    } else if (std.mem.eql(u8, filter.field, "title")) {
        return std.mem.indexOf(u8, neurona.title, value) != null;
    } else if (std.mem.eql(u8, filter.field, "type")) {
        const type_str = @tagName(neurona.type);
        return std.mem.eql(u8, type_str, value);
    } else {
        return false;
    }
}

/// Sort results by ID
fn sortResults(allocator: Allocator, neuras: *[]*const Neurona) ![]const Neurona {
    // Simple bubble sort for small lists
    // For production, use std.sort

    const count = neuras.len;
    for (0..@min(3, count - 2)) |i| {
        for (0..count - i - 1) |j| {
            if (std.mem.order(u8, neuras[j].id, neuras[j + 1].id) == .gt) {
                const tmp = neuras[j];
                neuras[j] = neuras[j + 1];
                neuras[j + 1] = tmp;
            }
        }
    }

    return try allocator.dupe(*const Neurona, neuras.*);
}

/// Output list format
fn outputList(allocator: Allocator, neuras: []const Neurona) !void {
    _ = allocator;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll("\n🔍 Search Results\n");
    for (0..40) |_| try stdout.writeByte('=');
    try stdout.writeAll("\n");

    if (neuras.len == 0) {
        try stdout.writeAll("No results found matching criteria\n");
        return;
    }

    const display_count = @min(10, neuras.len);
    for (neuras[0..display_count]) |neurona| {
        try stdout.print("  {s}\n", .{neurona.id});
        try stdout.print("    Type: {s}\n", .{@tagName(neurona.type)});
        try stdout.print("    Title: {s}\n", .{neurona.title});

        // Show tags
        if (neurona.tags.items.len > 0) {
            try stdout.writeAll("    Tags: ");
            for (neurona.tags.items, 0..) |tag, i| {
                if (i > 0) try stdout.writeAll(", ");
                try stdout.print("{s}", .{tag});
            }
            try stdout.writeAll("\n");
        }
    }

    try stdout.print("\n  Found {d} results\n", .{neuras.len});
}

/// JSON output for AI
fn outputJson(allocator: Allocator, neuras: []const Neurona) !void {
    _ = allocator;
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll("[");
    for (neuras, 0..) |neurona, i| {
        if (i > 0) try stdout.writeAll(",");
        try stdout.print("\"id\":\"{s}\",", .{neurona.id});
        try stdout.print("\"title\":\"{s}\",", .{neurona.title});
        try stdout.print("\"type\":\"{s}\",", .{@tagName(neurona.type)});

        try stdout.print("\"tags\":[", .{});

        var tag_i: usize = 0;
        for (neurona.tags.items) |tag| {
            if (tag_i > 0) try stdout.writeAll(",");
            try stdout.print("\"{s}\"", .{tag});
            tag_i += 1;
        }

        try stdout.writeAll("}");
    }
    try stdout.writeAll("]\n");
}

// Example CLI usage:
//
//   engram query
//   → List all Neuronas
//
//   engram query --type issue
//   → List only issues
//
//   engram query --tag "bug,p1"
//   → List Neuronas with bug or p1 tags
//
//   engram query --limit 10
//   → Limit results to 10 items
//
//   engram query --json
//   → Return JSON for AI parsing
