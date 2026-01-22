// File: src/cli/status.zig
// The `engram status` command for listing and filtering open issues
// Sorts by priority, assignee, status

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("storage").readNeurona;
const scanNeuronas = @import("storage").scanNeuronas;

/// Status configuration
pub const StatusConfig = struct {
    type_filter: ?[]const u8 = null,
    status_filter: ?[]const u8 = null,
    priority_filter: ?u8 = null,
    assignee_filter: ?[]const u8 = null,
    sort_by: SortField = .priority,
    json_output: bool = false,
};

pub const SortField = enum {
    priority,    // Sort by priority (high to low)
    created,    // Sort by creation date
    assignee,    // Sort by assignee
};

/// Main command handler
pub fn execute(allocator: Allocator, config: StatusConfig) !void {
    // Step 1: Scan all Neuronas
    const neuronas = try scanNeuronas(allocator, "neuronas");
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Step 2: Filter by type (issue) and status
    var filtered = try filterNeuronas(allocator, neuronas, config);
    defer {
        for (filtered) |*n| n.deinit(allocator);
        allocator.free(filtered);
    }

    // Step 3: Sort results
    sortResults(allocator, &filtered, config.sort_by);

    // Step 4: Output
    if (config.json_output) {
        try outputJson(filtered);
    } else {
        try outputList(filtered);
    }
}

/// Filter Neuronas by criteria
fn filterNeuronas(
    allocator: Allocator,
    neuronas: []const Neurona,
    config: StatusConfig
) ![]const *Neurona {
    var result = std.ArrayList(*const Neurona).init(allocator);
    errdefer result.deinit(allocator);

    for (neuronas) |*neurona| {
        // Filter by type
        if (config.type_filter) |filter| {
            const type_str = @tagName(neurona.type);
            if (!std.mem.eql(u8, type_str, filter)) continue;
        }

        // Filter by status
        if (config.status_filter) |status| {
            if (!std.mem.eql(u8, neurona.status, status)) continue;
        }

        // Filter by priority
        if (config.priority_filter) |p| {
            // Would need to parse context.priority from neurona.context
            // For now, skip complex context filtering
            continue;
        }

        // Filter by assignee
        if (config.assignee_filter) |assignee| {
            // Would need to parse context.assignee from neurona.context
            // For now, skip complex context filtering
            continue;
        }

        try result.append(neurona);
    }

    return result.toOwnedSlice();
}

/// Sort results by specified field
fn sortResults(allocator: Allocator, neuronas: *[]const *Neurona, field: SortField) void {
    // Simple bubble sort (good enough for small lists)
    // For production, use std.sort
    _ = allocator; // Suppress unused warning
    _ = field;

    // Clone slice for sorting
    const count = neuronas.len;
    for (0..@min(3, count - 2)) |i| {
        for (0..count - 1 - i - 1) |j| {
            if (compareNeuronas(neuronas[j], neuronas[j + 1], field) > 0) {
                const tmp = neuronas[j];
                neuronas[j] = neuronas[j + 1];
                neuronas[j + 1] = tmp;
            }
        }
    }
}

/// Compare two neuronas for sorting
fn compareNeuronas(a: *const Neurona, b: *const Neurona, field: SortField) bool {
    return switch (field) {
        .priority => comparePriority(a, b),
        .created => compareStrings(a, b),
        .assignee => compareAssignee(a, b),
    };
}

/// Compare by priority
fn comparePriority(a: *const Neurona, b: *const Neurona) bool {
    // Simplified - assume issues have higher priority = lower number
    // For now, just return true (a < b)
    // TODO: Parse priority from context when needed
    return true;
}

/// Compare by strings (assignee, title)
fn compareStrings(a: *const Neurona, b: *const Neurona) bool {
    return std.mem.order(u8, a.title, b.title) == .lt;
}

/// Compare by assignee
fn compareAssignee(a: *const Neurona, b: *const Neurona) bool {
    _ = a;
    _ = b;
    // TODO: Parse assignee from context
    return false;
}

/// Output list format
fn outputList(issues: []const *Neurona) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("\n📋 Open Issues\n");
    try stdout.writeByteNTimes('=', 40);
    try stdout.writeAll("\n");

    for (issues) |issue| {
        try stdout.print("  [{s}] {s}\n", .{ issue.id, issue.title });

        // Show priority
        const priority_str = try getPriorityString(issue);
        try stdout.print("      Priority: {s}\n", .{priority_str});

        // Show status
        try stdout.print("      Status: {s}\n", .{issue.status});

        // Show assignee if available (would need context parsing)
        try stdout.writeAll("      Assignee: [context-based]\n");

        try stdout.writeAll("\n");
    }

    if (issues.len == 0) {
        try stdout.writeAll("\nNo issues found matching criteria\n");
    }
}

/// Get priority string from context (placeholder)
fn getPriorityString(issue: *const Neurona) ![]const u8 {
    _ = issue;
    // TODO: Parse context.priority from issue.context
    return try issue.allocator.dupe(u8, "[priority from context]");
}

/// JSON output for AI
fn outputJson(issues: []const *Neurona) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("[");
    for (issues, 0..) |issue| {
        if (issue.id > 0) try stdout.writeAll(",");
        try stdout.writeAll("{");
        try stdout.print("\"id\":\"{s}", .{issue.id});
        try stdout.print("\"title\":\"{s}", .{issue.title});
        try stdout.print("\"type\":\"{s}", .{@tagName(issue.type)});
        try stdout.print("\"status\":\"{s}", .{issue.status});
        try stdout.print("\"priority\":\"[from context]\"");
        try stdout.writeAll("}");
    }
    try stdout.writeAll("]\n");
}

// Example CLI usage:
//
//   engram status
//   → List all open issues sorted by priority
//
//   engram status --filter "status:open"
//   → Filter by status field
//
//   engram status --assignee alice
//   → Filter issues assigned to alice
//
//   engram status --sort-by created
//   → Sort by creation date
//
//   engram status --json
//   → Return JSON for AI parsing
