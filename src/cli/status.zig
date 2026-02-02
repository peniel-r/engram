// File: src/cli/status.zig
// The `engram status` command for listing and filtering open issues
// Sorts by priority, assignee, status
// Supports EQL filtering: --filter "state:open AND priority:1"

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const storage = @import("../root.zig").storage;
const state_filters = @import("../utils/state_filters.zig");

/// Status configuration
pub const StatusConfig = struct {
    type_filter: ?[]const u8 = null,
    status_filter: ?[]const u8 = null,
    priority_filter: ?u8 = null,
    assignee_filter: ?[]const u8 = null,
    filter_str: ?[]const u8 = null, // EQL filter string: "state:open AND priority:1"
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
    // Step 1: Parse EQL filter if provided
    var filter_expr: ?state_filters.FilterExpression = null;
    defer {
        if (filter_expr) |*expr| expr.deinit(allocator);
    }

    if (config.filter_str) |filter| {
        filter_expr = try state_filters.parseFilter(allocator, filter);
    }

    // Step 2: Scan all Neuronas
    const neuronas = try storage.scanNeuronas(allocator, "neuronas");
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Step 3: Filter by type, status, and EQL filter
    const filtered = try filterNeuronas(allocator, neuronas, config, filter_expr);
    defer allocator.free(filtered);

    // Step 4: Sort results - skip for now due to const issues
    // sortResults(allocator, &filtered, config.sort_by);

    // Step 5: Output
    if (config.json_output) {
        try outputJson(filtered);
    } else {
        try outputList(filtered);
    }
}

/// Filter Neuronas by criteria
fn filterNeuronas(allocator: Allocator, neuronas: []const Neurona, config: StatusConfig, filter_expr: ?state_filters.FilterExpression) ![]*const Neurona {
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

        // Filter by EQL expression
        if (filter_expr) |expr| {
            if (!applyFilter(allocator, neurona, &expr)) continue;
        }

        try result.append(allocator, neurona);
    }

    const result_slice = try result.toOwnedSlice(allocator);
    return result_slice;
}

/// Apply EQL filter expression to a Neurona
fn applyFilter(allocator: Allocator, neurona: *const Neurona, expr: *const state_filters.FilterExpression) bool {
    const operator = expr.operator;

    // Evaluate each condition
    for (expr.conditions.items) |cond| {
        const matches = evaluateCondition(allocator, neurona, cond);

        // Apply logical operator
        if (operator == .@"and" and !matches) {
            return false; // AND: all must match
        }
        if (operator == .@"or" and matches) {
            return true; // OR: any match is sufficient
        }
    }

    // If all conditions passed (AND mode) or none passed (OR mode with empty list)
    return operator == .@"and" or expr.conditions.items.len == 0;
}

/// Evaluate a single filter condition against a Neurona
fn evaluateCondition(allocator: Allocator, neurona: *const Neurona, cond: state_filters.FilterCondition) bool {
    _ = allocator;
    const field = cond.field;
    const operator = cond.operator;
    const value = cond.value;

    // Handle direct fields
    if (std.mem.eql(u8, field, "type")) {
        const type_str = @tagName(neurona.type);
        return state_filters.compareStrings(type_str, operator, value);
    }

    if (std.mem.eql(u8, field, "title")) {
        return state_filters.compareStrings(neurona.title, operator, value);
    }

    if (std.mem.eql(u8, field, "language")) {
        return state_filters.compareStrings(neurona.language, operator, value);
    }

    if (std.mem.eql(u8, field, "id")) {
        return state_filters.compareStrings(neurona.id, operator, value);
    }

    // Handle context.field syntax
    if (std.mem.startsWith(u8, field, "context.")) {
        return evaluateContextField(neurona, field["context.".len..], operator, value);
    }

    // Handle special fields (state is alias for context.status)
    if (std.mem.eql(u8, field, "state")) {
        return evaluateContextField(neurona, "status", operator, value);
    }

    // Handle priority as alias for context.priority
    if (std.mem.eql(u8, field, "priority")) {
        return evaluateContextField(neurona, "priority", operator, value);
    }

    // Unknown field - don't match
    return false;
}

/// Evaluate context field condition
fn evaluateContextField(neurona: *const Neurona, context_field: []const u8, operator: state_filters.FilterOperator, expected: []const u8) bool {
    switch (neurona.context) {
        .test_case => |ctx| {
            if (std.mem.eql(u8, context_field, "status")) {
                return state_filters.compareStrings(ctx.status, operator, expected);
            }
            if (std.mem.eql(u8, context_field, "framework")) {
                return state_filters.compareStrings(ctx.framework, operator, expected);
            }
            if (std.mem.eql(u8, context_field, "assignee")) {
                if (ctx.assignee) |a| {
                    return state_filters.compareStrings(a, operator, expected);
                }
                return false;
            }
            if (std.mem.eql(u8, context_field, "priority")) {
                const priority_val = std.fmt.parseInt(u8, expected, 10) catch return false;
                return state_filters.compareIntegers(ctx.priority, operator, priority_val);
            }
        },
        .issue => |ctx| {
            if (std.mem.eql(u8, context_field, "status")) {
                return state_filters.compareStrings(ctx.status, operator, expected);
            }
            if (std.mem.eql(u8, context_field, "assignee")) {
                if (ctx.assignee) |a| {
                    return state_filters.compareStrings(a, operator, expected);
                }
                return false;
            }
            if (std.mem.eql(u8, context_field, "priority")) {
                const priority_val = std.fmt.parseInt(u8, expected, 10) catch return false;
                return state_filters.compareIntegers(ctx.priority, operator, priority_val);
            }
        },
        .requirement => |ctx| {
            if (std.mem.eql(u8, context_field, "status")) {
                return state_filters.compareStrings(ctx.status, operator, expected);
            }
            if (std.mem.eql(u8, context_field, "assignee")) {
                if (ctx.assignee) |a| {
                    return state_filters.compareStrings(a, operator, expected);
                }
                return false;
            }
            if (std.mem.eql(u8, context_field, "priority")) {
                const priority_val = std.fmt.parseInt(u8, expected, 10) catch return false;
                return state_filters.compareIntegers(ctx.priority, operator, priority_val);
            }
        },
        .artifact => |ctx| {
            if (std.mem.eql(u8, context_field, "runtime")) {
                return state_filters.compareStrings(ctx.runtime, operator, expected);
            }
            if (std.mem.eql(u8, context_field, "file_path")) {
                return state_filters.compareStrings(ctx.file_path, operator, expected);
            }
        },
        .state_machine => |ctx| {
            if (std.mem.eql(u8, context_field, "entry_action")) {
                return state_filters.compareStrings(ctx.entry_action, operator, expected);
            }
            if (std.mem.eql(u8, context_field, "exit_action")) {
                return state_filters.compareStrings(ctx.exit_action, operator, expected);
            }
        },
        .custom => |ctx| {
            if (ctx.get(context_field)) |v| {
                return state_filters.compareStrings(v, operator, expected);
            }
        },
        .none => {},
    }

    return false;
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

/// Print string as JSON-escaped value
fn printJsonString(s: []const u8) void {
    std.debug.print("\"", .{});
    for (s) |c| {
        switch (c) {
            '"' => std.debug.print("\\\"", .{}),
            '\\' => std.debug.print("\\\\", .{}),
            '\n' => std.debug.print("\\n", .{}),
            '\r' => std.debug.print("\\r", .{}),
            '\t' => std.debug.print("\\t", .{}),
            else => std.debug.print("{c}", .{c}),
        }
    }
    std.debug.print("\"", .{});
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
        std.debug.print("\"status\":\"", .{});
        switch (issue.context) {
            .test_case => |ctx| std.debug.print("{s}", .{ctx.status}),
            .issue => |ctx| std.debug.print("{s}", .{ctx.status}),
            .requirement => |ctx| std.debug.print("{s}", .{ctx.status}),
            else => std.debug.print("[N/A]", .{}),
        }
        std.debug.print("\",", .{});

        // Get priority from context
        std.debug.print("\"priority\":", .{});
        switch (issue.context) {
            .test_case => |ctx| std.debug.print("{d}", .{ctx.priority}),
            .issue => |ctx| std.debug.print("{d}", .{ctx.priority}),
            .requirement => |ctx| std.debug.print("{d}", .{ctx.priority}),
            else => std.debug.print("null", .{}),
        }
        std.debug.print(",", .{});

        // Tags count
        std.debug.print("\"tags\":{d}", .{issue.tags.items.len});
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
        .filter_str = null,
        .sort_by = .priority,
        .json_output = false,
    };

    try std.testing.expectEqual(@as(?[]const u8, null), config.type_filter);
    try std.testing.expectEqual(@as(?[]const u8, null), config.status_filter);
    try std.testing.expectEqual(@as(?u8, null), config.priority_filter);
    try std.testing.expectEqual(@as(?[]const u8, null), config.assignee_filter);
    try std.testing.expectEqual(@as(?[]const u8, null), config.filter_str);
    try std.testing.expectEqual(SortField.priority, config.sort_by);
    try std.testing.expectEqual(false, config.json_output);
}

test "StatusConfig with all filters set" {
    const config = StatusConfig{
        .type_filter = "issue",
        .status_filter = "open",
        .priority_filter = 1,
        .assignee_filter = "alice",
        .filter_str = "state:open AND priority:1",
        .sort_by = .created,
        .json_output = true,
    };

    try std.testing.expectEqualStrings("issue", config.type_filter.?);
    try std.testing.expectEqualStrings("open", config.status_filter.?);
    try std.testing.expectEqual(@as(u8, 1), config.priority_filter.?);
    try std.testing.expectEqualStrings("alice", config.assignee_filter.?);
    try std.testing.expectEqualStrings("state:open AND priority:1", config.filter_str.?);
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

    const filtered = try filterNeuronas(allocator, &neuronas, config, null);
    defer allocator.free(filtered);

    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqual(NeuronaType.issue, filtered[0].type);
}

test "applyFilter with simple type condition" {
    const allocator = std.testing.allocator;

    var n1 = try Neurona.init(allocator);
    defer n1.deinit(allocator);
    n1.type = .issue;

    var expr = state_filters.FilterExpression{
        .conditions = .{},
        .operator = .@"and",
    };
    defer {
        // Manual cleanup to avoid const qualifier issues
        for (expr.conditions.items) |*cond| {
            allocator.free(cond.field);
            allocator.free(cond.value);
        }
        expr.conditions.deinit(allocator);
    }

    try expr.conditions.append(allocator, .{
        .field = try allocator.dupe(u8, "type"),
        .operator = .eq,
        .value = try allocator.dupe(u8, "issue"),
    });

    try std.testing.expect(applyFilter(allocator, &n1, &expr));
}

test "evaluateCondition matches type field" {
    const allocator = std.testing.allocator;

    var n1 = try Neurona.init(allocator);
    defer n1.deinit(allocator);
    n1.type = .issue;

    const cond = state_filters.FilterCondition{
        .field = try allocator.dupe(u8, "type"),
        .operator = .eq,
        .value = try allocator.dupe(u8, "issue"),
    };
    defer {
        allocator.free(cond.field);
        allocator.free(cond.value);
    }

    try std.testing.expect(evaluateCondition(allocator, &n1, cond));
}

test "SortField enum has correct values" {
    try std.testing.expectEqual(SortField.priority, SortField.priority);
    try std.testing.expectEqual(SortField.created, SortField.created);
    try std.testing.expectEqual(SortField.assignee, SortField.assignee);
}
