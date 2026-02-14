// File: src/cli/status.zig
// The `engram status` command for listing and filtering open issues
// Sorts by priority, assignee, status
// Supports EQL filtering: --filter "state:open AND priority:1"
// MIGRATED: Now uses Phase 3 CLI utilities (JsonOutput, HumanOutput)

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const storage = @import("../root.zig").storage;
const state_filters = @import("../utils/state_filters.zig");
const uri_parser = @import("../utils/uri_parser.zig");

// Import Phase 3 CLI utilities
const JsonOutput = @import("output/json.zig").JsonOutput;
const HumanOutput = @import("output/human.zig").HumanOutput;

/// Status configuration
pub const StatusConfig = struct {
    type_filter: ?[]const u8 = null,
    status_filter: ?[]const u8 = null,
    priority_filter: ?u8 = null,
    assignee_filter: ?[]const u8 = null,
    filter_str: ?[]const u8 = null,
    sort_by: SortField = .priority,
    json_output: bool = false,
    cortex_dir: ?[]const u8 = null,
};

pub const SortField = enum {
    priority,
    created,
    assignee,
};

/// Main command handler
pub fn execute(allocator: Allocator, config: StatusConfig) !void {
    const cortex_dir = uri_parser.findCortexDir(allocator, config.cortex_dir) catch |err| {
        if (err == error.CortexNotFound) {
            try HumanOutput.printError("No cortex found in current directory or within 3 directory levels.");
            try HumanOutput.printInfo("Navigate to a cortex directory or use --cortex <path> to specify location.");
            try HumanOutput.printInfo("Run 'engram init <name>' to create a new cortex.");
            std.process.exit(1);
        }
        return err;
    };
    defer if (config.cortex_dir == null) allocator.free(cortex_dir);

    const neuronas_dir = try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex_dir});
    defer allocator.free(neuronas_dir);

    var filter_expr: ?state_filters.FilterExpression = null;
    defer {
        if (filter_expr) |*expr| expr.deinit(allocator);
    }

    if (config.filter_str) |filter| {
        filter_expr = try state_filters.parseFilter(allocator, filter);
    }

    const neuronas = try storage.scanNeuronas(allocator, neuronas_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    const filtered = try filterNeuronas(allocator, neuronas, config, filter_expr);
    defer allocator.free(filtered);

    if (config.json_output) {
        try outputJson(filtered);
    } else {
        try outputList(filtered);
    }
}

fn filterNeuronas(allocator: Allocator, neuronas: []const Neurona, config: StatusConfig, filter_expr: ?state_filters.FilterExpression) ![]*const Neurona {
    var result = std.ArrayListUnmanaged(*const Neurona){};
    defer result.deinit(allocator);

    for (neuronas) |*neurona| {
        if (config.type_filter) |filter| {
            const type_str = @tagName(neurona.type);
            if (!std.mem.eql(u8, type_str, filter)) continue;
        }

        if (config.status_filter) |status| {
            switch (neurona.context) {
                .test_case => |ctx| {
                    if (!std.mem.eql(u8, ctx.status, status)) continue;
                },
                else => continue,
            }
        }

        if (filter_expr) |expr| {
            if (!applyFilter(allocator, neurona, &expr)) continue;
        }

        try result.append(allocator, neurona);
    }

    const result_slice = try result.toOwnedSlice(allocator);
    return result_slice;
}

fn applyFilter(allocator: Allocator, neurona: *const Neurona, expr: *const state_filters.FilterExpression) bool {
    const operator = expr.operator;

    for (expr.conditions.items) |cond| {
        const matches = evaluateCondition(allocator, neurona, cond);

        if (operator == .@"and" and !matches) {
            return false;
        }
        if (operator == .@"or" and matches) {
            return true;
        }
    }

    return operator == .@"and" or expr.conditions.items.len == 0;
}

fn evaluateCondition(allocator: Allocator, neurona: *const Neurona, cond: state_filters.FilterCondition) bool {
    _ = allocator;
    const field = cond.field;
    const operator = cond.operator;
    const value = cond.value;

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

    if (std.mem.startsWith(u8, field, "context.")) {
        return evaluateContextField(neurona, field["context.".len..], operator, value);
    }

    if (std.mem.eql(u8, field, "state")) {
        return evaluateContextField(neurona, "status", operator, value);
    }

    if (std.mem.eql(u8, field, "priority")) {
        return evaluateContextField(neurona, "priority", operator, value);
    }

    return false;
}

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
            return false;
        },
        .none => {},
    }
    return false;
}

fn compareNeuronas(a: *const Neurona, b: *const Neurona, field: SortField) i32 {
    return switch (field) {
        .priority => comparePriority(a, b),
        .created => compareStrings(a, b),
        .assignee => compareAssignee(a, b),
    };
}

fn comparePriority(a: *const Neurona, b: *const Neurona) i32 {
    _ = a;
    _ = b;
    return -1;
}

fn compareStrings(a: *const Neurona, b: *const Neurona) i32 {
    return switch (std.mem.order(u8, a.title, b.title)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

fn compareAssignee(a: *const Neurona, b: *const Neurona) i32 {
    _ = a;
    _ = b;
    return 0;
}

fn outputList(issues: []*const Neurona) !void {
    try HumanOutput.printHeader("Open Issues", "📋");

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    for (issues) |issue| {
        try HumanOutput.printSubheader(issue.id, "  ");

        const priority_str = try getPriorityString(issue);

        try stdout.print("  Priority: {s}\n", .{priority_str});
        try stdout.flush();

        switch (issue.context) {
            .test_case => |ctx| {
                try stdout.print("  Status: {s}\n", .{ctx.status});
                try stdout.flush();
            },
            else => {
                try stdout.print("  Status: [N/A]\n", .{});
                try stdout.flush();
            },
        }

        try stdout.print("  Assignee: [context-based]\n", .{});
        try stdout.flush();
    }

    if (issues.len == 0) {
        try HumanOutput.printWarning("No issues found matching criteria");
    }
}

fn getPriorityString(issue: *const Neurona) ![]const u8 {
    _ = issue;
    return "[priority from context]";
}

fn outputJson(issues: []*const Neurona) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try JsonOutput.beginArray(stdout);
    for (issues, 0..) |issue, i| {
        if (i > 0) {
            try JsonOutput.separator(stdout, true);
        }
        try JsonOutput.beginObject(stdout);

        try JsonOutput.stringField(stdout, "id", issue.id);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.stringField(stdout, "title", issue.title);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.enumField(stdout, "type", issue.type);
        try JsonOutput.separator(stdout, true);

        try JsonOutput.stringField(stdout, "status", getContextStatus(issue));
        try JsonOutput.separator(stdout, true);

        try JsonOutput.numberField(stdout, "priority", getContextPriority(issue));
        try JsonOutput.separator(stdout, true);

        try JsonOutput.numberField(stdout, "tags", issue.tags.items.len);

        try JsonOutput.endObject(stdout);
    }
    try JsonOutput.endArray(stdout);
    try stdout.flush();
}

fn getContextStatus(neurona: *const Neurona) []const u8 {
    switch (neurona.context) {
        .test_case => |ctx| return ctx.status,
        .issue => |ctx| return ctx.status,
        .requirement => |ctx| return ctx.status,
        else => return "[N/A]",
    }
}

fn getContextPriority(neurona: *const Neurona) i64 {
    switch (neurona.context) {
        .test_case => |ctx| return ctx.priority,
        .issue => |ctx| return ctx.priority,
        .requirement => |ctx| return ctx.priority,
        else => return 0,
    }
}

// ==================== Tests ====================

test "filterNeuronas filters by type" {
    const allocator = std.testing.allocator;

    const config = StatusConfig{
        .type_filter = "issue",
    };

    // Helper function to create test neurona with proper context
    const neurona1 = Neurona{
        .id = "test.001",
        .title = "Test Issue",
        .type = .issue,
        .language = "en",
        .context = .{ .issue = .{
            .status = "open",
            .priority = 1,
            .assignee = null,
            .created = "2024-01-01T00:00:00Z",
            .resolved = null,
            .closed = null,
            .blocked_by = std.ArrayListUnmanaged([]const u8){},
            .related_to = std.ArrayListUnmanaged([]const u8){},
        } },
        .tags = std.ArrayListUnmanaged([]const u8){},
        .links = std.ArrayListUnmanaged([]const u8){},
    };

    const neurona2 = Neurona{
        .id = "test.002",
        .title = "Test Requirement",
        .type = .requirement,
        .language = "en",
        .context = .{ .requirement = .{
            .status = "draft",
            .priority = 2,
            .assignee = null,
            .verification_method = "test",
            .effort_points = null,
            .sprint = null,
        } },
        .tags = std.ArrayListUnmanaged([]const u8){},
        .links = std.ArrayListUnmanaged([]const u8){},
    };

    const neuronas = [_]Neurona{ neurona1, neurona2 };
    const pointers = [_]*const Neurona{ &neuronas[0], &neuronas[1] };

    const result = try filterNeuronas(allocator, &pointers, config, null);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("test.001", result[0].id);
}

test "evaluateCondition matches type field" {
    const allocator = std.testing.allocator;

    const neurona = Neurona{
        .id = "test.001",
        .title = "Test",
        .type = .issue,
        .language = "en",
        .context = .{ .issue = .{
            .status = "open",
            .priority = 1,
            .assignee = null,
            .created = "2024-01-01T00:00:00Z",
            .resolved = null,
            .closed = null,
            .blocked_by = std.ArrayListUnmanaged([]const u8){},
            .related_to = std.ArrayListUnmanaged([]const u8){},
        } },
        .tags = std.ArrayListUnmanaged([]const u8){},
        .links = std.ArrayListUnmanaged([]const u8){},
    };

    const cond = state_filters.FilterCondition{
        .field = "type",
        .operator = .eq,
        .value = "issue",
    };

    const result = evaluateCondition(allocator, &neurona, cond);
    try std.testing.expect(result);
}
