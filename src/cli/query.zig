// File: src/cli/query.zig
// The `engram query` command for searching Neuronas
// Supports type, tag, and connection filters

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("storage").readNeurona;
const scanNeuronas = @import("storage").scanNeuronas;

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

pub const ConnectionFilter = struct {
    connection_type: ?[]const u8 = null,
    target_id: ?[]const u8 = null,
    operator: ConnectionOperator = .and,

    pub const ConnectionOperator = enum {
        and,
        or,
    not,
    };
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
    const neuronas = try scanNeuronas(allocator, "neuronas");
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
    var results = std.ArrayList(*const Neurona).init(allocator);
    defer {
        for (results.items) |*n| n.deinit(allocator);
        allocator.free(results);
    }

    var count: usize = 0;

    for (neuronas) |*neurona| {
        if (matchesFilters(neurona.*, config.filters)) {
            try results.append(neurona);
            count += 1;

            if (config.limit) |limit| {
                if (count >= limit.*) break;
            }
        }
    }

    // Step 3: Sort results (by id for now)
    const sorted = sortResults(allocator, results.toOwnedSlice());

    // Step 4: Output
    if (config.json_output) {
        try outputJson(allocator, sorted);
    } else {
        try outputList(allocator, sorted);
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
        .type_filter => |tf| matchesTypeFilter(neurona.*, tf),
        .tag_filter => |tf| matchesTagFilter(neurona.*, tf),
        .connection_filter => |cf| matchesConnectionFilter(neurona.*, cf),
        .field_filter => |ff| matchesFieldFilter(neurona.*, ff),
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
        var found = false;
        for (neurona.tags.items) |neurona_tag| {
            if (std.mem.eql(u8, neurona_tag, tag)) {
                found = true;
                break;
            }
        }
        if (found) {
            return filter.include;
        }
    }
    return !filter.include;
}

/// Match connection filter
fn matchesConnectionFilter(neurona: *const Neurona, filter: ConnectionFilter) bool {
    var conn_it = neurona.connections.iterator();

    while (conn_it.next()) |entry| {
        for (entry.value_ptr.connections.items) |conn| {
            var matches = matchesSingleConnection(conn, filter);

            if (!matches and filter.operator == .and) {
                break; // At least one match required
            }

            if (matches and filter.operator == .not) {
                return false; // Found a match when we should NOT match
            }
        }
    }

    return switch (filter.operator) {
        .or => matches, // Found at least one match
        .not => !matches,
        .and => matches,
    };
}

/// Match a single connection
fn matchesSingleConnection(conn: *const Neurona, filter: ConnectionFilter) bool {
    var matches_type = false;
    var matches_target = false;

    if (filter.connection_type) |ct| {
        matches_type = std.mem.eql(u8, @tagName(conn.connection_type), ct);
    }

    if (filter.target_id) |tid| {
        matches_target = std.mem.eql(u8, conn.target_id, tid);
    }

    if (matches_type or matches_target) {
        return true;
    }

    return false;
}

/// Match field filter
fn matchesFieldFilter(neurona: *const Neurona, filter: FieldFilter) bool {
    // For now, just check basic fields (id, title, type, status)
    const value = filter.value orelse return false;

    return switch (filter.field) {
        "id" => if (value) |v| std.mem.eql(u8, neurona.id, v) else false,
        "title" => if (value) |v| std.mem.indexOf(u8, neurona.title, v) != null else false,
        "type" => if (value) |v| {
            const type_str = @tagName(neurona.type);
            std.mem.eql(u8, type_str, v);
        } else false,
        else => false,
    };
}

/// Sort results by ID
fn sortResults(allocator: Allocator, neuras: []*const Neurona) ![]const Neurona {
    // Simple bubble sort for small lists
    // For production, use std.sort
    _ = allocator;

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

    return try allocator.dupe(*const Neurona, neuras);
}

/// Output list format
fn outputList(allocator: Allocator, neuras: []const Neurona) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("\n🔍 Search Results\n");
    try stdout.writeByteNTimes('=', 40);
    try stdout.writeAll("\n");

    if (neuronas.len == 0) {
        try stdout.writeAll("No results found matching criteria\n");
    return;
    }

    for (neuronas, 0..@min(10, neuronas.len - 1)) |neurona| {
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

    try stdout.print("\n  Found {d} results\n", .{neuronas.len});
}

/// JSON output for AI
fn outputJson(allocator: Allocator, neuras: []const Neurona) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("[");
    for (neuronas, 0..) |neurona| {
        if (neurona.id > 0) try stdout.writeAll(",");
        try stdout.print("\"id\":\"{s}", .{neurona.id});
        try stdout.print("\"title\":\"{s}\"", .{neurona.title});
        try stdout.print("\"type\":\"{s}\"", .{@tagName(neurona.type)});

        try stdout.print("\"tags\":[", .{});

        for (neurona.tags.items, 0..) |tag, i| {
            if (i > 0) try stdout.writeAll(",");
            try stdout.print("\"{s}\"", .{tag});
        }

        try stdout.writeAll("]");
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
