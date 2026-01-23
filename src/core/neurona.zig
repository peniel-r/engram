// Neurona data structure for the Neurona System
// Supports Tier 1, 2, and 3 specifications
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
        return null;
    }
};

/// Connection with weight
pub const Connection = struct {
    target_id: []const u8,
    connection_type: ConnectionType,
    weight: u8, // 0-100, default 50 for Tier 1/2

    pub fn format(self: Connection, allocator: Allocator) ![]const u8 {
        const type_name = switch (self.connection_type) {
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
        };

        return std.fmt.allocPrint(allocator, "{s} -> {s} (weight: {d})", .{
            type_name,
            self.target_id,
            self.weight,
        });
    }
};

/// Neurona types (Flavors)
pub const NeuronaType = enum {
    /// General purpose concept (default)
    concept,

    /// Reference material: docs, definitions, facts
    reference,

    /// Code snippets, scripts, tools
    artifact,

    /// State machine node
    state_machine,

    /// Educational content
    lesson,

    /// ALM: Requirement
    requirement,

    /// ALM: Test case
    test_case,

    /// ALM: Issue/bug
    issue,

    /// ALM: Feature
    feature,
};

/// Connection grouping (structured connections in Tier 2/3)
pub const ConnectionGroup = struct {
    /// Array of connections of this type
    connections: std.ArrayListUnmanaged(Connection),

    pub fn init() ConnectionGroup {
        return .{ .connections = .{} };
    }

    pub fn deinit(self: *ConnectionGroup, allocator: Allocator) void {
        self.connections.deinit(allocator);
    }
};

/// LLM optimization metadata (Tier 3)
pub const LLMMetadata = struct {
    /// Short title for token efficiency
    short_title: []const u8,

    /// Density/Difficulty (1-4)
    density: u8,

    /// Top keywords for RAG
    keywords: std.ArrayListUnmanaged([]const u8),

    /// Body token count
    token_count: u32,

    /// Strategy: full, summary, hierarchical
    strategy: []const u8,

    pub fn deinit(self: *LLMMetadata, allocator: Allocator) void {
        for (self.keywords.items) |kw| allocator.free(kw);
        self.keywords.deinit(allocator);
        allocator.free(self.short_title);
        allocator.free(self.strategy);
    }
};

/// Context extensions (Tier 3)
/// Allows custom context based on neurona type
pub const Context = union(enum) {
    /// State machine context
    state_machine: struct {
        triggers: std.ArrayListUnmanaged([]const u8),
        entry_action: []const u8,
        exit_action: []const u8,
        allowed_roles: std.ArrayListUnmanaged([]const u8),

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            for (self.triggers.items) |t| allocator.free(t);
            self.triggers.deinit(allocator);
            allocator.free(self.entry_action);
            allocator.free(self.exit_action);
            for (self.allowed_roles.items) |r| allocator.free(r);
            self.allowed_roles.deinit(allocator);
        }
    },

    /// Artifact context
    artifact: struct {
        runtime: []const u8,
        file_path: []const u8,
        safe_to_exec: bool,
        language_version: ?[]const u8,
        last_modified: ?[]const u8,

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            allocator.free(self.runtime);
            allocator.free(self.file_path);
            if (self.language_version) |v| allocator.free(v);
            if (self.last_modified) |v| allocator.free(v);
        }
    },

    /// Test case context
    test_case: struct {
        framework: []const u8,
        test_file: ?[]const u8,
        status: []const u8,
        priority: u8,
        assignee: ?[]const u8,
        duration: ?[]const u8,
        last_run: ?[]const u8,

        pub fn deinit(self: *@This(), allocator: Allocator) void {
            allocator.free(self.framework);
            if (self.test_file) |f| allocator.free(f);
            allocator.free(self.status);
            if (self.assignee) |a| allocator.free(a);
            if (self.duration) |d| allocator.free(d);
            if (self.last_run) |v| allocator.free(v);
        }
    },

    /// Custom context (any key-value pairs)
    custom: std.StringHashMap([]const u8),

    /// No context (Tier 1/2 default)
    none,
};

/// Main Neurona data structure
/// Supports all three tiers
pub const Neurona = struct {
    // === Tier 1: Essential Fields ===
    id: []const u8,
    title: []const u8,
    tags: std.ArrayListUnmanaged([]const u8),

    // === Tier 2: Standard Fields ===
    type: NeuronaType,
    connections: std.StringHashMapUnmanaged(ConnectionGroup),
    updated: []const u8,
    language: []const u8,

    // === Tier 3: Advanced Fields (Optional) ===
    hash: ?[]const u8,
    llm_metadata: ?LLMMetadata,
    context: Context,

    /// Initialize empty Neurona
    pub fn init(allocator: Allocator) !Neurona {
        return Neurona{
            .id = try allocator.dupe(u8, ""),
            .title = try allocator.dupe(u8, ""),
            .tags = .{},
            .type = .concept,
            .connections = .{},
            .updated = try allocator.dupe(u8, ""),
            .language = try allocator.dupe(u8, "en"),
            .hash = null,
            .llm_metadata = null,
            .context = .none,
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *Neurona, allocator: Allocator) void {
        // Free basic fields
        allocator.free(self.id);
        allocator.free(self.title);
        for (self.tags.items) |tag| allocator.free(tag);
        self.tags.deinit(allocator);
        allocator.free(self.updated);
        allocator.free(self.language);

        // Free connections (including target_id strings)
        var conn_it = self.connections.iterator();
        while (conn_it.next()) |entry| {
            for (entry.value_ptr.connections.items) |*conn| {
                allocator.free(conn.target_id);
            }
            entry.value_ptr.deinit(allocator);
        }
        self.connections.deinit(allocator);

        // Free Tier 3 fields
        if (self.hash) |h| allocator.free(h);
        if (self.llm_metadata) |*meta| meta.deinit(allocator);

        // Free context
        switch (self.context) {
            .state_machine => |*ctx| ctx.deinit(allocator),
            .artifact => |*ctx| ctx.deinit(allocator),
            .test_case => |*ctx| ctx.deinit(allocator),
            .custom => |*ctx| {
                var it = ctx.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    allocator.free(entry.value_ptr.*);
                }
                ctx.deinit();
            },
            .none => {},
        }
    }

    /// Add a connection to the Neurona
    pub fn addConnection(self: *Neurona, allocator: Allocator, connection: Connection) !void {
        const conn_group = try self.connections.getOrPut(allocator, @tagName(connection.connection_type));
        if (!conn_group.found_existing) {
            conn_group.value_ptr.* = ConnectionGroup.init();
        }
        try conn_group.value_ptr.connections.append(allocator, connection);
    }

    /// Get connections of a specific type
    pub fn getConnections(self: *const Neurona, conn_type: ConnectionType) []const Connection {
        const group = self.connections.get(@tagName(conn_type)) orelse return &[0]Connection{};
        return group.connections.items;
    }

    /// Check if Neurona has Tier 2+ features
    pub fn isTier2(self: *const Neurona) bool {
        return self.type != .concept or self.connections.count() > 0;
    }

    /// Check if Neurona has Tier 3 features
    pub fn isTier3(self: *const Neurona) bool {
        return self.hash != null or self.llm_metadata != null or self.context != .none;
    }
};

test "Neurona init creates valid structure" {
    const allocator = std.testing.allocator;

    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), neurona.tags.items.len);
    try std.testing.expectEqual(@as(usize, 0), neurona.connections.count());
    try std.testing.expectEqual(.concept, neurona.type);
    try std.testing.expectEqualStrings("", neurona.id);
    try std.testing.expectEqualStrings("", neurona.title);
}

test "Neurona addConnection works" {
    const allocator = std.testing.allocator;

    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);

    const conn = Connection{
        .target_id = try allocator.dupe(u8, "test.target"),
        .connection_type = .parent,
        .weight = 90,
    };
    // Note: conn.target_id will be freed by neurona.deinit()

    try neurona.addConnection(allocator, conn);

    try std.testing.expectEqual(@as(usize, 1), neurona.connections.count());
    const parent_conns = neurona.getConnections(.parent);
    try std.testing.expectEqual(@as(usize, 1), parent_conns.len);
    try std.testing.expectEqualStrings("test.target", parent_conns[0].target_id);
}

test "Neurona isTier2 detects tier 2 features" {
    const allocator = std.testing.allocator;

    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);

    try std.testing.expect(!neurona.isTier2());
    neurona.type = .requirement;
    try std.testing.expect(neurona.isTier2());

    const conn = Connection{
        .target_id = try allocator.dupe(u8, "test"),
        .connection_type = .parent,
        .weight = 50,
    };
    // Note: conn.target_id will be freed by neurona.deinit()

    try neurona.addConnection(allocator, conn);
    try std.testing.expect(neurona.isTier2());
}

test "Neurona isTier3 detects tier 3 features" {
    const allocator = std.testing.allocator;

    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);

    try std.testing.expect(!neurona.isTier3());

    neurona.hash = try allocator.dupe(u8, "sha256:abc123");
    try std.testing.expect(neurona.isTier3());
}

test "Neurona deinit cleans up all memory" {
    const allocator = std.testing.allocator;

    var neurona = try Neurona.init(allocator);
    neurona.title = try allocator.dupe(u8, "Test Neurona");

    const conn = Connection{
        .target_id = try allocator.dupe(u8, "test.target"),
        .connection_type = .parent,
        .weight = 90,
    };
    try neurona.addConnection(allocator, conn);

    const tag = try allocator.dupe(u8, "test-tag");
    try neurona.tags.append(allocator, tag);

    neurona.deinit(allocator);

    // Should not leak (checked by zig test with leak detection)
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

test "ConnectionType fromString parses all 15 types" {
    // Test all 15 connection types
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
