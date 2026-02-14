//! Core data structures for Neurona System
//! Supports Tier 1, 2, and 3 specifications

const std = @import("std");
const Allocator = std.mem.Allocator;

const Connection = @import("connections.zig").Connection;
const ConnectionType = @import("connections.zig").ConnectionType;
const ConnectionGroup = @import("connections.zig").ConnectionGroup;
const Context = @import("context.zig").Context;

/// Neurona types (Flavors)
/// Determines interpretation and available features
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

/// LLM optimization metadata (Tier 3)
/// Used for token efficiency and AI optimization
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

    /// Free allocated memory
    pub fn deinit(self: *LLMMetadata, allocator: Allocator) void {
        for (self.keywords.items) |kw| allocator.free(kw);
        self.keywords.deinit(allocator);
        allocator.free(self.short_title);
        allocator.free(self.strategy);
    }
};

/// Main Neurona data structure
/// Supports all three tiers of the Neurona specification
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

    /// Initialize empty Neurona with defaults
    /// Caller must set all required fields
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
        // Free basic fields (safely check for null pointers and empty strings)
        if (@intFromPtr(self.id.ptr) != 0 and self.id.len > 0) allocator.free(self.id);
        if (@intFromPtr(self.title.ptr) != 0 and self.title.len > 0) allocator.free(self.title);
        for (self.tags.items) |tag| allocator.free(tag);
        self.tags.deinit(allocator);
        if (@intFromPtr(self.updated.ptr) != 0 and self.updated.len > 0) allocator.free(self.updated);
        if (@intFromPtr(self.language.ptr) != 0 and self.language.len > 0) allocator.free(self.language);

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
        self.context.deinit(allocator);
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

test "LLMMetadata deinit cleans up all memory" {
    const allocator = std.testing.allocator;

    var meta = LLMMetadata{
        .short_title = try allocator.dupe(u8, "Short"),
        .density = 2,
        .keywords = .{},
        .token_count = 100,
        .strategy = try allocator.dupe(u8, "summary"),
    };
    try meta.keywords.append(allocator, try allocator.dupe(u8, "keyword1"));
    try meta.keywords.append(allocator, try allocator.dupe(u8, "keyword2"));

    meta.deinit(allocator);

    // Should not leak
}
