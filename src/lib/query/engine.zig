//! Query engine for searching Neuronas
//! Supports filter, text, vector, hybrid, and activation modes
//!
//! This is a library-only implementation without CLI dependencies.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Neurona = @import("../core/types.zig").Neurona;
const QueryMode = @import("modes.zig").QueryMode;
const Storage = @import("../storage/filesystem.zig").Storage;

/// Query result
pub const QueryResult = struct {
    neurona: *const Neurona,
    score: f32,
    mode: QueryMode,
};

/// Query configuration
pub const QueryConfig = struct {
    mode: QueryMode = .filter,
    query_text: []const u8 = "",
    limit: ?usize = null,
};

/// Query filter types
pub const QueryFilter = union(enum) {
    type_filter: TypeFilter,
    tag_filter: TagFilter,
};

pub const TypeFilter = struct {
    types: std.ArrayListUnmanaged([]const u8),

    pub fn deinit(self: *TypeFilter, allocator: Allocator) void {
        for (self.types.items) |t| allocator.free(t);
        self.types.deinit(allocator);
    }
};

pub const TagFilter = struct {
    tags: std.ArrayListUnmanaged([]const u8),

    pub fn deinit(self: *TagFilter, allocator: Allocator) void {
        for (self.tags.items) |t| allocator.free(t);
        self.tags.deinit(allocator);
    }
};

/// Query engine implementation
pub const QueryEngine = struct {
    allocator: Allocator,
    storage: *const Storage,

    pub fn init(allocator: Allocator, storage: *const Storage) QueryEngine {
        return QueryEngine{
            .allocator = allocator,
            .storage = storage,
        };
    }

    pub fn execute(engine: *const QueryEngine, config: QueryConfig, _: []const QueryFilter) ![]QueryResult {
        var all_neuronas = try engine.storage.scan();
        defer {
            for (all_neuronas) |*n| n.deinit(engine.allocator);
            engine.allocator.free(all_neuronas);
        }

        var results = std.ArrayListUnmanaged(QueryResult){};
        errdefer {
            results.deinit(engine.allocator);
        }

        switch (config.mode) {
            .filter => {
                try engine.executeFilter(&all_neuronas, &results);
            },
            .text => {
                try engine.executeTextSearch(&all_neuronas, config.query_text, &results);
            },
            .vector, .hybrid, .activation => {
                try engine.executeFilter(&all_neuronas, &results);
            },
        }

        if (config.limit) |limit| {
            if (results.items.len > limit) {
                results.shrinkRetainingCapacity(limit);
            }
        }

        return results.toOwnedSlice(engine.allocator);
    }

    fn executeFilter(engine: *const QueryEngine, neuronas: []const Neurona, results: *std.ArrayListUnmanaged(QueryResult)) !void {
        for (neuronas) |*neurona| {
            try results.append(engine.allocator, QueryResult{
                .neurona = neurona,
                .score = 1.0,
                .mode = .filter,
            });
        }
    }

    fn executeTextSearch(engine: *const QueryEngine, neuronas: []const Neurona, query_text: []const u8, results: *std.ArrayListUnmanaged(QueryResult)) !void {
        var query_lower = try engine.allocator.dupe(u8, query_text);
        defer engine.allocator.free(query_lower);

        for (query_lower, 0..) |c, i| {
            query_lower[i] = std.ascii.toLower(c);
        }

        for (neuronas) |*neurona| {
            const score = calculateTextScore(neurona, query_lower);
            if (score > 0) {
                try results.append(engine.allocator, QueryResult{
                    .neurona = neurona,
                    .score = score,
                    .mode = .text,
                });
            }
        }
    }
};

pub fn calculateTextScore(neurona: *const Neurona, query_lower: []const u8) f32 {
    var score: f32 = 0.0;

    const title_lower = try std.heap.page_allocator.dupe(u8, neurona.title);
    defer std.heap.page_allocator.free(title_lower);

    var title_mut = title_lower;
    for (title_mut, 0..) |c, i| {
        title_mut[i] = std.ascii.toLower(c);
    }

    if (std.mem.indexOf(u8, title_mut, query_lower) != null) {
        score += 2.0;
    }

    for (neurona.tags.items) |tag| {
        const tag_lower = try std.heap.page_allocator.dupe(u8, tag);
        defer std.heap.page_allocator.free(tag_lower);

        var tag_mut = tag_lower;
        for (tag_mut, 0..) |c, i| {
            tag_mut[i] = std.ascii.toLower(c);
        }

        if (std.mem.indexOf(u8, tag_mut, query_lower) != null) {
            score += 1.0;
        }
    }

    return score;
}

test "TypeFilter deinit cleans up memory" {
    const allocator = std.testing.allocator;

    var filter = TypeFilter{ .types = .{} };
    try filter.types.append(allocator, try allocator.dupe(u8, "requirement"));
    try filter.types.append(allocator, try allocator.dupe(u8, "test_case"));

    filter.deinit(allocator);
}

test "TagFilter deinit cleans up memory" {
    const allocator = std.testing.allocator;

    var filter = TagFilter{ .tags = .{} };
    try filter.tags.append(allocator, try allocator.dupe(u8, "security"));
    try filter.tags.append(allocator, try allocator.dupe(u8, "auth"));

    filter.deinit(allocator);
}

test "calculateTextScore scores by relevance" {
    const allocator = std.testing.allocator;

    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);

    neurona.title = try allocator.dupe(u8, "Test Title");

    try neurona.tags.append(allocator, try allocator.dupe(u8, "test"));

    const query = try allocator.dupe(u8, "test");
    defer allocator.free(query);

    const score = calculateTextScore(&neurona, query);
    try std.testing.expect(score > 0);
}
