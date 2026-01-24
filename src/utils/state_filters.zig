// State Filter Parser for EQL queries
// Parses filter strings like "state:open AND priority:1"
// Supports filtering by context fields and state

const std = @import("std");
const Allocator = std.mem.Allocator;

// ==================== Filter Operators ====================

/// Filter operators
pub const FilterOperator = enum {
    eq, // Equal (default)
    neq, // Not equal
    gt, // Greater than
    lt, // Less than
    gte, // Greater or equal
    lte, // Less or equal
    contains, // String contains
    regex, // Regex match

    pub fn fromString(s: []const u8) ?FilterOperator {
        if (std.mem.eql(u8, s, "eq")) return .eq;
        if (std.mem.eql(u8, s, "=")) return .eq;
        if (std.mem.eql(u8, s, "neq")) return .neq;
        if (std.mem.eql(u8, s, "!=")) return .neq;
        if (std.mem.eql(u8, s, "gt")) return .gt;
        if (std.mem.eql(u8, s, ">")) return .gt;
        if (std.mem.eql(u8, s, "lt")) return .lt;
        if (std.mem.eql(u8, s, "<")) return .lt;
        if (std.mem.eql(u8, s, "gte")) return .gte;
        if (std.mem.eql(u8, s, ">=")) return .gte;
        if (std.mem.eql(u8, s, "lte")) return .lte;
        if (std.mem.eql(u8, s, "<=")) return .lte;
        if (std.mem.eql(u8, s, "contains")) return .contains;
        if (std.mem.eql(u8, s, "regex")) return .regex;
        return null;
    }
};

/// Filter condition
pub const FilterCondition = struct {
    field: []const u8,
    operator: FilterOperator,
    value: []const u8,
};

/// Logical operator for combining conditions
pub const LogicalOperator = enum {
    @"and",
    @"or",
};

/// Parsed filter expression
pub const FilterExpression = struct {
    conditions: std.ArrayListUnmanaged(FilterCondition),
    operator: LogicalOperator = .@"and",

    pub fn deinit(self: *FilterExpression, allocator: Allocator) void {
        for (self.conditions.items) |*cond| {
            allocator.free(cond.field);
            allocator.free(cond.value);
        }
        self.conditions.deinit(allocator);
    }
};

// ==================== Parser ====================

/// Parse EQL filter string
pub fn parseFilter(allocator: Allocator, filter_str: []const u8) !FilterExpression {
    var result = FilterExpression{
        .conditions = .{},
        .operator = .@"and",
    };
    errdefer result.deinit(allocator);

    var iter = std.mem.splitScalar(u8, filter_str, ' ');
    while (iter.next()) |token| {
        const trimmed = std.mem.trim(u8, token, &std.ascii.whitespace);

        if (trimmed.len == 0) continue;

        // Check for logical operators
        if (std.mem.eql(u8, trimmed, "AND")) {
            result.operator = .@"and";
            continue;
        }
        if (std.mem.eql(u8, trimmed, "OR")) {
            result.operator = .@"or";
            continue;
        }

        // Parse condition (field:operator:value or field:value)
        if (parseCondition(allocator, trimmed, &result) catch |err| return err) {
            // Successfully parsed
        }
    }

    return result;
}

/// Parse single condition
fn parseCondition(allocator: Allocator, token: []const u8, result: *FilterExpression) !bool {
    // Handle field:operator:value or field:value
    var field_iter = std.mem.splitScalar(u8, token, ':');
    const field = field_iter.next() orelse return error.InvalidFilter;
    const rest = field_iter.rest();

    // Check if there's an operator (second colon)
    var rest_iter = std.mem.splitScalar(u8, rest, ':');
    const possible_operator = rest_iter.next() orelse {
        // No second colon, treat as field:value (default eq)
        if (rest.len == 0) return error.InvalidFilter;
        const field_dup = try allocator.dupe(u8, field);
        const value_dup = try allocator.dupe(u8, rest);

        try result.conditions.append(allocator, .{
            .field = field_dup,
            .operator = .eq,
            .value = value_dup,
        });
        return true;
    };

    // Has second colon - try to parse as field:operator:value
    const op = FilterOperator.fromString(possible_operator) orelse {
        // Not a known operator, treat as field:operator (where operator is value)
        // This handles the case of field:value where value contains the operator name
        const field_dup = try allocator.dupe(u8, field);
        const value_dup = try allocator.dupe(u8, rest);

        try result.conditions.append(allocator, .{
            .field = field_dup,
            .operator = .eq,
            .value = value_dup,
        });
        return true;
    };

    const value = rest_iter.rest();
    if (value.len == 0) return error.InvalidFilter;

    try result.conditions.append(allocator, .{
        .field = try allocator.dupe(u8, field),
        .operator = op,
        .value = try allocator.dupe(u8, value),
    });
    return true;
}

// ==================== Filter Application ====================

/// Compare strings based on operator
pub fn compareStrings(actual: []const u8, op: FilterOperator, expected: []const u8) bool {
    return switch (op) {
        .eq => std.mem.eql(u8, actual, expected),
        .neq => !std.mem.eql(u8, actual, expected),
        .contains => std.mem.indexOf(u8, actual, expected) != null,
        else => false,
    };
}

/// Compare integers based on operator
pub fn compareIntegers(actual: u8, op: FilterOperator, expected: u8) bool {
    return switch (op) {
        .eq => actual == expected,
        .neq => actual != expected,
        .gt => actual > expected,
        .lt => actual < expected,
        .gte => actual >= expected,
        .lte => actual <= expected,
        else => false,
    };
}

/// Check if value matches a condition
pub fn matchesCondition(cond: FilterCondition, actual_value: []const u8) bool {
    return compareStrings(actual_value, cond.operator, cond.value);
}

// ==================== Tests ====================

test "FilterOperator fromString parses operators" {
    try std.testing.expectEqual(.eq, FilterOperator.fromString("eq").?);
    try std.testing.expectEqual(.neq, FilterOperator.fromString("neq").?);
    try std.testing.expectEqual(.gt, FilterOperator.fromString("gt").?);
    try std.testing.expectEqual(.lt, FilterOperator.fromString("lt").?);
    try std.testing.expectEqual(.gte, FilterOperator.fromString("gte").?);
    try std.testing.expectEqual(.lte, FilterOperator.fromString("lte").?);
    try std.testing.expectEqual(.contains, FilterOperator.fromString("contains").?);
    try std.testing.expectEqual(@as(?FilterOperator, null), FilterOperator.fromString("invalid"));
}

test "parseFilter parses simple filter" {
    const allocator = std.testing.allocator;

    var expr = try parseFilter(allocator, "state:open");
    defer expr.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), expr.conditions.items.len);
    try std.testing.expectEqualStrings("state", expr.conditions.items[0].field);
    try std.testing.expectEqual(.eq, expr.conditions.items[0].operator);
    try std.testing.expectEqualStrings("open", expr.conditions.items[0].value);
}

test "parseFilter parses complex filter with AND" {
    const allocator = std.testing.allocator;

    var expr = try parseFilter(allocator, "state:open AND priority:1");
    defer expr.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), expr.conditions.items.len);
    try std.testing.expectEqualStrings("state", expr.conditions.items[0].field);
    try std.testing.expectEqualStrings("priority", expr.conditions.items[1].field);
    try std.testing.expectEqual(LogicalOperator.@"and", expr.operator);
}

test "parseFilter parses context field" {
    const allocator = std.testing.allocator;

    var expr = try parseFilter(allocator, "context.status:passing");
    defer expr.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), expr.conditions.items.len);
    try std.testing.expectEqualStrings("context.status", expr.conditions.items[0].field);
}

test "matchesCondition works with equality" {
    const allocator = std.testing.allocator;

    const cond = FilterCondition{
        .field = try allocator.dupe(u8, "title"),
        .operator = .eq,
        .value = try allocator.dupe(u8, "Test Title"),
    };
    defer {
        allocator.free(cond.field);
        allocator.free(cond.value);
    }

    try std.testing.expect(matchesCondition(cond, "Test Title"));
    try std.testing.expect(!matchesCondition(cond, "Other Title"));
}

test "compareStrings works correctly" {
    try std.testing.expect(compareStrings("hello", .eq, "hello"));
    try std.testing.expect(!compareStrings("hello", .eq, "world"));
    try std.testing.expect(compareStrings("hello", .neq, "world"));
    try std.testing.expect(compareStrings("hello world", .contains, "world"));
    try std.testing.expect(!compareStrings("hello world", .contains, "foo"));
}

test "compareIntegers works correctly" {
    try std.testing.expect(compareIntegers(5, .eq, 5));
    try std.testing.expect(!compareIntegers(5, .eq, 3));
    try std.testing.expect(compareIntegers(5, .gt, 3));
    try std.testing.expect(!compareIntegers(3, .gt, 5));
    try std.testing.expect(compareIntegers(5, .gte, 5));
    try std.testing.expect(compareIntegers(5, .lte, 10));
}
