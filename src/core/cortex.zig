// Cortex configuration parser
// Handles cortex.json configuration file
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Cortex capabilities configuration
pub const Capabilities = struct {
    /// Cortex type: zettelkasten, alm, etc.
    type: []const u8,

    /// Enable semantic search (vectors)
    semantic_search: bool,

    /// Enable LLM integration
    llm_integration: bool,

    /// Default language
    default_language: []const u8,

    pub fn deinit(self: *Capabilities, allocator: Allocator) void {
        allocator.free(self.type);
        allocator.free(self.default_language);
    }
};

/// Index configuration
pub const IndexConfig = struct {
    /// Strategy: lazy, eager, on_save
    strategy: []const u8,

    /// Embedding model name
    embedding_model: []const u8,

    pub fn deinit(self: *IndexConfig, allocator: Allocator) void {
        allocator.free(self.strategy);
        allocator.free(self.embedding_model);
    }
};

/// Cortex configuration structure
pub const Cortex = struct {
    /// Unique cortex ID
    id: []const u8,

    /// Human-readable name
    name: []const u8,

    /// Version
    version: []const u8,

    /// Spec version supported
    spec_version: []const u8,

    /// Capabilities
    capabilities: Capabilities,

    /// Index configuration
    indices: IndexConfig,

    /// Parse cortex.json file
    pub fn fromFile(allocator: Allocator, path: []const u8) !Cortex {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
        defer allocator.free(content);

        return fromJson(allocator, content);
    }

    /// Parse Cortex from JSON string
    pub fn fromJson(allocator: Allocator, json: []const u8) !Cortex {
        const parsed = try std.json.parseFromSlice(struct {
            id: []const u8,
            name: []const u8,
            version: []const u8,
            spec_version: []const u8,
            capabilities: struct {
                type: []const u8,
                semantic_search: bool,
                llm_integration: bool,
                default_language: []const u8,
            },
            indices: struct {
                strategy: []const u8,
                embedding_model: []const u8,
            },
        }, allocator, json, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        return Cortex{
            .id = try allocator.dupe(u8, parsed.value.id),
            .name = try allocator.dupe(u8, parsed.value.name),
            .version = try allocator.dupe(u8, parsed.value.version),
            .spec_version = try allocator.dupe(u8, parsed.value.spec_version),
            .capabilities = Capabilities{
                .type = try allocator.dupe(u8, parsed.value.capabilities.type),
                .semantic_search = parsed.value.capabilities.semantic_search,
                .llm_integration = parsed.value.capabilities.llm_integration,
                .default_language = try allocator.dupe(u8, parsed.value.capabilities.default_language),
            },
            .indices = IndexConfig{
                .strategy = try allocator.dupe(u8, parsed.value.indices.strategy),
                .embedding_model = try allocator.dupe(u8, parsed.value.indices.embedding_model),
            },
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *Cortex, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.spec_version);
        self.capabilities.deinit(allocator);
        self.indices.deinit(allocator);
    }

    /// Validate cortex configuration
    pub fn validate(self: *const Cortex) !void {
        // Check required fields
        if (self.id.len == 0) return error.InvalidCortexId;
        if (self.name.len == 0) return error.InvalidCortexName;

        // Check capabilities type
        const valid_types = [_][]const u8{ "zettelkasten", "alm", "knowledge" };
        var type_valid = false;
        for (valid_types) |t| {
            if (std.mem.eql(u8, self.capabilities.type, t)) {
                type_valid = true;
                break;
            }
        }
        if (!type_valid) return error.InvalidCortexType;

        // Check index strategy
        const valid_strategies = [_][]const u8{ "lazy", "eager", "on_save" };
        var strategy_valid = false;
        for (valid_strategies) |s| {
            if (std.mem.eql(u8, self.indices.strategy, s)) {
                strategy_valid = true;
                break;
            }
        }
        if (!strategy_valid) return error.InvalidIndexStrategy;
    }

    /// Generate default cortex configuration
    pub fn default(allocator: Allocator, id: []const u8, name: []const u8) !Cortex {
        const cortex_id = try allocator.dupe(u8, id);
        const cortex_name = try allocator.dupe(u8, name);

        return Cortex{
            .id = cortex_id,
            .name = cortex_name,
            .version = try allocator.dupe(u8, "0.1.0"),
            .spec_version = try allocator.dupe(u8, "0.1.0"),
            .capabilities = Capabilities{
                .type = try allocator.dupe(u8, "zettelkasten"),
                .semantic_search = false,
                .llm_integration = false,
                .default_language = try allocator.dupe(u8, "en"),
            },
            .indices = IndexConfig{
                .strategy = try allocator.dupe(u8, "lazy"),
                .embedding_model = try allocator.dupe(u8, "none"),
            },
        };
    }
};

test "Cortex fromJson parses correctly" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "id": "test_cortex",
        \\  "name": "Test Cortex",
        \\  "version": "0.1.0",
        \\  "spec_version": "0.1.0",
        \\  "capabilities": {
        \\    "type": "zettelkasten",
        \\    "semantic_search": false,
        \\    "llm_integration": false,
        \\    "default_language": "en"
        \\  },
        \\  "indices": {
        \\    "strategy": "lazy",
        \\    "embedding_model": "none"
        \\  }
        \\}
    ;

    var cortex = try Cortex.fromJson(allocator, json);

    try std.testing.expectEqualStrings("test_cortex", cortex.id);
    try std.testing.expectEqualStrings("Test Cortex", cortex.name);
    try std.testing.expectEqualStrings("0.1.0", cortex.version);
    try std.testing.expectEqualStrings("zettelkasten", cortex.capabilities.type);
    try std.testing.expect(!cortex.capabilities.semantic_search);
    try std.testing.expectEqualStrings("lazy", cortex.indices.strategy);

    cortex.deinit(allocator);
}

test "Cortex validate accepts valid config" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "id": "test",
        \\  "name": "Test",
        \\  "version": "0.1.0",
        \\  "spec_version": "0.1.0",
        \\  "capabilities": {
        \\    "type": "zettelkasten",
        \\    "semantic_search": false,
        \\    "llm_integration": false,
        \\    "default_language": "en"
        \\  },
        \\  "indices": {
        \\    "strategy": "lazy",
        \\    "embedding_model": "none"
        \\  }
        \\}
    ;

    var cortex = try Cortex.fromJson(allocator, json);

    try cortex.validate();

    cortex.deinit(allocator);
}

test "Cortex validate rejects invalid type" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "id": "test",
        \\  "name": "Test",
        \\  "version": "0.1.0",
        \\  "spec_version": "0.1.0",
        \\  "capabilities": {
        \\    "type": "invalid_type",
        \\    "semantic_search": false,
        \\    "llm_integration": false,
        \\    "default_language": "en"
        \\  },
        \\  "indices": {
        \\    "strategy": "lazy",
        \\    "embedding_model": "none"
        \\  }
        \\}
    ;

    var cortex = try Cortex.fromJson(allocator, json);

    try std.testing.expectError(error.InvalidCortexType, cortex.validate());

    cortex.deinit(allocator);
}

test "Cortex validate rejects invalid strategy" {
    const allocator = std.testing.allocator;

    const json =
        \\{
        \\  "id": "test",
        \\  "name": "Test",
        \\  "version": "0.1.0",
        \\  "spec_version": "0.1.0",
        \\  "capabilities": {
        \\    "type": "zettelkasten",
        \\    "semantic_search": false,
        \\    "llm_integration": false,
        \\    "default_language": "en"
        \\  },
        \\  "indices": {
        \\    "strategy": "invalid",
        \\    "embedding_model": "none"
        \\  }
        \\}
    ;

    var cortex = try Cortex.fromJson(allocator, json);

    try std.testing.expectError(error.InvalidIndexStrategy, cortex.validate());

    cortex.deinit(allocator);
}

test "Cortex default creates valid config" {
    const allocator = std.testing.allocator;

    var cortex = try Cortex.default(allocator, "test_cortex", "Test Cortex");

    try std.testing.expectEqualStrings("test_cortex", cortex.id);
    try std.testing.expectEqualStrings("Test Cortex", cortex.name);
    try std.testing.expectEqualStrings("0.1.0", cortex.version);

    // Should validate
    try cortex.validate();

    cortex.deinit(allocator);
}
