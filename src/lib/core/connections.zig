//! Connection types and logic for Neurona relationships
//! Supports Tier 2+ structured connections between Neuronas

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Connection types for Neurona relationships
pub const ConnectionType = enum {
    /// Hierarchical: parent-child relationships
    parent,
    child,

    /// Validation: test_case validates requirement
    validates,
    validated_by,

    /// Blocking: issue blocks requirement/release
    blocks,
    blocked_by,

    /// Implementation: artifact implements requirement
    implements,
    implemented_by,

    /// Testing: artifact tested by test_case
    tested_by,
    tests,

    /// Relationships: related, similar, contrast
    relates_to,

    /// Learning: prerequisite, next, related
    prerequisite,
    next,
    related,

    /// Opposition: conflicts, opposes
    opposes,

    /// Notes-specific relationships
    builds_on, // Extends or develops another concept
    contradicts, // Opposes or conflicts with another view
    cites, // References external source
    example_of, // Concrete example of abstract concept
    proves, // Demonstrates or validates

    /// Parse string to ConnectionType
    /// Returns null if string is not a valid connection type
    pub fn fromString(s: []const u8) ?ConnectionType {
        if (std.mem.eql(u8, s, "parent")) return .parent;
        if (std.mem.eql(u8, s, "child")) return .child;
        if (std.mem.eql(u8, s, "validates")) return .validates;
        if (std.mem.eql(u8, s, "validated_by")) return .validated_by;
        if (std.mem.eql(u8, s, "blocks")) return .blocks;
        if (std.mem.eql(u8, s, "blocked_by")) return .blocked_by;
        if (std.mem.eql(u8, s, "implements")) return .implements;
        if (std.mem.eql(u8, s, "implemented_by")) return .implemented_by;
        if (std.mem.eql(u8, s, "tested_by")) return .tested_by;
        if (std.mem.eql(u8, s, "tests")) return .tests;
        if (std.mem.eql(u8, s, "relates_to")) return .relates_to;
        if (std.mem.eql(u8, s, "prerequisite")) return .prerequisite;
        if (std.mem.eql(u8, s, "next")) return .next;
        if (std.mem.eql(u8, s, "related")) return .related;
        if (std.mem.eql(u8, s, "opposes")) return .opposes;
        if (std.mem.eql(u8, s, "builds_on")) return .builds_on;
        if (std.mem.eql(u8, s, "contradicts")) return .contradicts;
        if (std.mem.eql(u8, s, "cites")) return .cites;
        if (std.mem.eql(u8, s, "example_of")) return .example_of;
        if (std.mem.eql(u8, s, "proves")) return .proves;
        return null;
    }

    /// Convert ConnectionType to string representation
    pub fn toString(self: ConnectionType) []const u8 {
        return switch (self) {
            .parent => "parent",
            .child => "child",
            .validates => "validates",
            .validated_by => "validated_by",
            .blocks => "blocks",
            .blocked_by => "blocked_by",
            .implements => "implements",
            .implemented_by => "implemented_by",
            .tested_by => "tested_by",
            .tests => "tests",
            .relates_to => "relates_to",
            .prerequisite => "prerequisite",
            .next => "next",
            .related => "related",
            .opposes => "opposes",
            .builds_on => "builds_on",
            .contradicts => "contradicts",
            .cites => "cites",
            .example_of => "example_of",
            .proves => "proves",
        };
    }
};

/// Connection with weight (0-100)
/// Tier 1/2 links default to weight 50
pub const Connection = struct {
    target_id: []const u8,
    connection_type: ConnectionType,
    weight: u8,

    /// Format connection as readable string
    pub fn format(self: Connection, allocator: Allocator) ![]const u8 {
        const type_name = self.connection_type.toString();
        return std.fmt.allocPrint(allocator, "{s} -> {s} (weight: {d})", .{
            type_name,
            self.target_id,
            self.weight,
        });
    }
};

/// Connection grouping (structured connections in Tier 2/3)
/// Groups connections by type for efficient querying
pub const ConnectionGroup = struct {
    /// Array of connections of this type
    connections: std.ArrayListUnmanaged(Connection),

    /// Create empty ConnectionGroup
    pub fn init() ConnectionGroup {
        return .{ .connections = .{} };
    }

    /// Free allocated memory
    pub fn deinit(self: *ConnectionGroup, allocator: Allocator) void {
        self.connections.deinit(allocator);
    }
};

test "ConnectionType fromString parses all 15 types" {
    const test_cases = [_]struct {
        input: []const u8,
        expected: ConnectionType,
    }{
        .{ .input = "parent", .expected = .parent },
        .{ .input = "child", .expected = .child },
        .{ .input = "validates", .expected = .validates },
        .{ .input = "validated_by", .expected = .validated_by },
        .{ .input = "blocks", .expected = .blocks },
        .{ .input = "blocked_by", .expected = .blocked_by },
        .{ .input = "implements", .expected = .implements },
        .{ .input = "implemented_by", .expected = .implemented_by },
        .{ .input = "tested_by", .expected = .tested_by },
        .{ .input = "tests", .expected = .tests },
        .{ .input = "relates_to", .expected = .relates_to },
        .{ .input = "prerequisite", .expected = .prerequisite },
        .{ .input = "next", .expected = .next },
        .{ .input = "related", .expected = .related },
        .{ .input = "opposes", .expected = .opposes },
    };

    for (test_cases) |tc| {
        const result = ConnectionType.fromString(tc.input);
        try std.testing.expectEqual(tc.expected, result.?);
    }
}

test "ConnectionType fromString returns null for invalid" {
    const result = ConnectionType.fromString("invalid_type");
    try std.testing.expectEqual(@as(?ConnectionType, null), result);
}

test "ConnectionType toString converts all types" {
    const test_cases = [_]struct {
        input: ConnectionType,
        expected: []const u8,
    }{
        .{ .input = .parent, .expected = "parent" },
        .{ .input = .child, .expected = "child" },
        .{ .input = .validates, .expected = "validates" },
        .{ .input = .validated_by, .expected = "validated_by" },
        .{ .input = .blocks, .expected = "blocks" },
        .{ .input = .blocked_by, .expected = "blocked_by" },
        .{ .input = .implements, .expected = "implements" },
        .{ .input = .implemented_by, .expected = "implemented_by" },
        .{ .input = .tested_by, .expected = "tested_by" },
        .{ .input = .tests, .expected = "tests" },
        .{ .input = .relates_to, .expected = "relates_to" },
        .{ .input = .prerequisite, .expected = "prerequisite" },
        .{ .input = .next, .expected = "next" },
        .{ .input = .related, .expected = "related" },
        .{ .input = .opposes, .expected = "opposes" },
    };

    for (test_cases) |tc| {
        const result = tc.input.toString();
        try std.testing.expectEqualStrings(tc.expected, result);
    }
}

test "ConnectionGroup init creates valid structure" {
    const group = ConnectionGroup.init();
    try std.testing.expectEqual(@as(usize, 0), group.connections.items.len);
}

test "Connection format produces readable string" {
    const allocator = std.testing.allocator;
    const conn = Connection{
        .target_id = "test.target",
        .connection_type = .validates,
        .weight = 100,
    };

    const formatted = try conn.format(allocator);
    defer allocator.free(formatted);

    try std.testing.expect(formatted.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "test.target") != null);
}
