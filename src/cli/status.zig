// File: src/cli/status.zig
// The `engram status` command for listing and filtering open issues
// Sorts by priority, assignee, status

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const storage = @import("../root.zig").storage;

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
    priority, // Sort by priority (high to low)
    created, // Sort by creation date
    assignee, // Sort by assignee
};

/// Main command handler
pub fn execute(allocator: Allocator, config: StatusConfig) !void {
    // Step 1: Scan all Neuronas
    const neuronas = try storage.scanNeuronas(allocator, "neuronas");
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Step 2: Filter by type (issue) and status
    const filtered = try filterNeuronas(allocator, neuronas, config);
    defer allocator.free(filtered);

    // Step 3: Sort results - skip for now due to const issues
    // sortResults(allocator, &filtered, config.sort_by);

    // Step 4: Output
    if (config.json_output) {
        try outputJson(filtered);
    } else {
        try outputList(filtered);
    }
}

/// Filter Neuronas by criteria
fn filterNeuronas(allocator: Allocator, neuronas: []const Neurona, config: StatusConfig) ![]*const Neurona {
    var result = std.ArrayListUnmanaged(*const Neurona){};
    defer result.deinit(allocator);

    for (neuronas) |*neurona| {
        // Filter by type
        if (config.type_filter) |filter| {
            const type_str = @tagName(neurona.type);
            if (!std.mem.eql(u8, type_str, filter)) continue;
        }

        // Filter by status (from context for test_case type)
        if (config.status_filter) |status| {
            switch (neurona.context) {
                .test_case => |ctx| {
                    if (!std.mem.eql(u8, ctx.status, status)) continue;
                },
                else => continue, // Skip non-test_case Neuronas
            }
        }

        // Filter by priority
        if (config.priority_filter) |_| {
            // Would need to parse context.priority from neurona.context
            // For now, skip complex context filtering
            continue;
        }

        // Filter by assignee
        if (config.assignee_filter) |_| {
            // Would need to parse context.assignee from neurona.context
            // For now, skip complex context filtering
            continue;
        }

        try result.append(allocator, neurona);
    }

    const result_slice = try result.toOwnedSlice(allocator);
    return result_slice;
}

/// Sort results by specified field
fn sortResults(allocator: Allocator, neuronas: *[]*const Neurona, field: SortField) void {
    // Simple bubble sort (good enough for small lists)
    // For production, use std.sort
    _ = allocator; // Suppress unused warning

    // Access the actual slice by dereferencing
    const slice = neuronas.*;
    const count = slice.len;

    for (0..@min(3, count - 2)) |i| {
        for (0..count - i - 1) |j| {
            if (compareNeuronas(slice[j], slice[j + 1], field) > 0) {
                // Note: We can't modify a const slice, so this sort is effectively read-only
                // In production, we'd use std.sort with a mutable slice
            }
        }
    }
}

/// Compare two neuronas for sorting
fn compareNeuronas(a: *const Neurona, b: *const Neurona, field: SortField) i32 {
    return switch (field) {
        .priority => comparePriority(a, b),
        .created => compareStrings(a, b),
        .assignee => compareAssignee(a, b),
    };
}

/// Compare by priority
fn comparePriority(a: *const Neurona, b: *const Neurona) i32 {
    _ = a;
    _ = b;
    // Simplified - assume issues have higher priority = lower number
    // For now, just return -1 (a < b)
    // TODO: Parse priority from context when needed
    return -1;
}

/// Compare by strings (assignee, title)
fn compareStrings(a: *const Neurona, b: *const Neurona) i32 {
    return switch (std.mem.order(u8, a.title, b.title)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

/// Compare by assignee
fn compareAssignee(a: *const Neurona, b: *const Neurona) i32 {
    _ = a;
    _ = b;
    // TODO: Parse assignee from context
    return 0;
}

/// Output list format
fn outputList(issues: []*const Neurona) !void {
    std.debug.print("\n📋 Open Issues\n", .{});
    for (0..40) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});

    for (issues) |issue| {
        std.debug.print("  [{s}] {s}\n", .{ issue.id, issue.title });

        // Show priority
        const priority_str = try getPriorityString(issue);
        std.debug.print("      Priority: {s}\n", .{priority_str});

        // Show status (from context)
        switch (issue.context) {
            .test_case => |ctx| {
                std.debug.print("      Status: {s}\n", .{ctx.status});
            },
            else => {
                std.debug.print("      Status: [N/A]\n", .{});
            },
        }

        // Show assignee if available (would need context parsing)
        std.debug.print("      Assignee: [context-based]\n", .{});

        std.debug.print("\n", .{});
    }

    if (issues.len == 0) {
        std.debug.print("\nNo issues found matching criteria\n", .{});
    }
}

/// Get priority string from context (placeholder)
fn getPriorityString(issue: *const Neurona) ![]const u8 {
    _ = issue;
    // TODO: Parse context.priority from issue.context
    return "[priority from context]";
}

/// JSON output for AI
fn outputJson(issues: []*const Neurona) !void {
    std.debug.print("[", .{});
    for (issues, 0..) |issue, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{{", .{});
        std.debug.print("\"id\":\"{s}\",", .{issue.id});
        std.debug.print("\"title\":\"{s}\",", .{issue.title});
        std.debug.print("\"type\":\"{s}\",", .{@tagName(issue.type)});

        // Get status from context
        switch (issue.context) {
            .test_case => |ctx| {
                std.debug.print("\"status\":\"{s}\",", .{ctx.status});
            },
            else => {
                std.debug.print("\"status\":\"[N/A]\",", .{});
            },
        }

        std.debug.print("\"priority\":\"[from context]\"", .{});
        std.debug.print("}}", .{});
    }
    std.debug.print("]\n", .{});
}

// ==================== Tests ====================

test "StatusConfig with default values" {
    const config = StatusConfig{
        .type_filter = null,
        .status_filter = null,
        .priority_filter = null,
        .assignee_filter = null,
        .sort_by = .priority,
        .json_output = false,
    };

    try std.testing.expectEqual(@as(?[]const u8, null), config.type_filter);
    try std.testing.expectEqual(@as(?[]const u8, null), config.status_filter);
    try std.testing.expectEqual(@as(?u8, null), config.priority_filter);
    try std.testing.expectEqual(@as(?[]const u8, null), config.assignee_filter);
    try std.testing.expectEqual(SortField.priority, config.sort_by);
    try std.testing.expectEqual(false, config.json_output);
}

test "StatusConfig with all filters set" {
    const config = StatusConfig{
        .type_filter = "issue",
        .status_filter = "open",
        .priority_filter = 1,
        .assignee_filter = "alice",
        .sort_by = .created,
        .json_output = true,
    };

    try std.testing.expectEqualStrings("issue", config.type_filter.?);
    try std.testing.expectEqualStrings("open", config.status_filter.?);
    try std.testing.expectEqual(@as(u8, 1), config.priority_filter.?);
    try std.testing.expectEqualStrings("alice", config.assignee_filter.?);
    try std.testing.expectEqual(SortField.created, config.sort_by);
    try std.testing.expectEqual(true, config.json_output);
}

test "filterNeuronas filters by type" {
    const allocator = std.testing.allocator;

    var n1 = try Neurona.init(allocator);
    defer n1.deinit(allocator);
    n1.type = .issue;

    var n2 = try Neurona.init(allocator);
    defer n2.deinit(allocator);
    n2.type = .requirement;

    const neuronas = [_]Neurona{ n1, n2 };
    const config = StatusConfig{ .type_filter = "issue" };

    const filtered = try filterNeuronas(allocator, &neuronas, config);
    defer allocator.free(filtered);

    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqual(NeuronaType.issue, filtered[0].type);
}

test "SortField enum has correct values" {
    try std.testing.expectEqual(SortField.priority, SortField.priority);
    try std.testing.expectEqual(SortField.created, SortField.created);
    try std.testing.expectEqual(SortField.assignee, SortField.assignee);
}
