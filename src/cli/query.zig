// File: src/cli/query.zig
// The `engram query` command for searching Neuronas
// Supports type, tag, and connection filters
// MIGRATED: Now uses lib types via root.zig

const std = @import("std");
const Allocator = std.mem.Allocator;
// Use lib types via root.zig (Phase 4 migration)
const Neurona = @import("../root.zig").Neurona;
const NeuronaType = @import("../root.zig").NeuronaType;
const Connection = @import("../root.zig").Connection;
const storage = @import("../root.zig").storage;
const Graph = @import("../core/graph.zig").Graph;
const NeuralActivation = @import("../root.zig").core.NeuralActivation;
const GloVeIndex = @import("../root.zig").storage.GloVeIndex;
const uri_parser = @import("../utils/uri_parser.zig");

/// Query mode for different search algorithms
pub const QueryMode = enum {
    /// Filter by type, tags, connections (default)
    filter,
    /// BM25 full-text search
    text,
    /// Vector similarity search
    vector,
    /// Combined BM25 + vector with fusion
    hybrid,
    /// Neural propagation across graph
    activation,
};

/// Fused search result (for hybrid search)
pub const FusedResult = struct {
    id: []const u8,
    score: f32,
};

/// Query configuration
pub const QueryConfig = struct {
    mode: QueryMode = .filter,
    query_text: []const u8 = "",
    filters: []QueryFilter,
    limit: ?usize = null,
    json_output: bool = false,
    cortex_dir: ?[]const u8 = null,
};

/// Query filter types
pub const QueryFilter = union(enum) {
    /// Filter by Neurona type (issue, requirement, test_case, etc.)
    type_filter: TypeFilter,

    /// Filter by tags
    tag_filter: TagFilter,

    /// Filter by connection
    connection_filter: ConnectionFilter,

    /// Filter by metadata field
    field_filter: FieldFilter,
};

pub const TypeFilter = struct {
    types: std.ArrayListUnmanaged([]const u8),
    include: bool = true,

    pub fn deinit(self: *TypeFilter, allocator: Allocator) void {
        for (self.types.items) |t| {
            allocator.free(t);
        }
        self.types.deinit(allocator);
    }
};

pub const TagFilter = struct {
    tags: std.ArrayListUnmanaged([]const u8),
    include: bool = true,

    pub fn deinit(self: *TagFilter, allocator: Allocator) void {
        for (self.tags.items) |t| {
            allocator.free(t);
        }
        self.tags.deinit(allocator);
    }
};

pub const ConnectionOperator = enum {
    @"and",
    @"or",
    not,
};

pub const ConnectionFilter = struct {
    connection_type: ?[]const u8 = null,
    target_id: ?[]const u8 = null,
    operator: ConnectionOperator = .@"and",
};

pub const FieldFilter = struct {
    field: []const u8,
    value: ?[]const u8 = null,
    operator: FieldOperator = .equal,

    pub const FieldOperator = enum {
        equal,
        not_equal,
        contains,
        not_contains,
    };
};

/// Main command handler - routes to mode-specific handler
pub fn execute(allocator: Allocator, config: QueryConfig) !void {
    switch (config.mode) {
        .filter => try executeFilterQuery(allocator, config),
        .text => try executeBM25Query(allocator, config),
        .vector => try executeVectorQuery(allocator, config),
        .hybrid => try executeHybridQuery(allocator, config),
        .activation => try executeActivationQuery(allocator, config),
    }
}

fn getNeuronasDir(allocator: Allocator, cortex_dir: ?[]const u8) ![]const u8 {
    const cortex = uri_parser.findCortexDir(allocator, cortex_dir) catch |err| {
        if (err == error.CortexNotFound) {
            std.debug.print("Error: No cortex found in current directory or within 3 directory levels.\n", .{});
            std.debug.print("\nHint: Navigate to a cortex directory or use --cortex <path> to specify location.\n", .{});
            std.debug.print("Run 'engram init <name>' to create a new cortex.\n", .{});
            std.process.exit(1);
        }
        return err;
    };
    const path = try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex});
    allocator.free(cortex);
    return path;
}

/// Filter mode: Filter by type, tags, connections
pub fn executeFilterQuery(allocator: Allocator, config: QueryConfig) !void {
    // Step 1: Scan all Neuronas
    const directory = try getNeuronasDir(allocator, config.cortex_dir);
    defer allocator.free(directory);

    const neuronas = try storage.scanNeuronas(allocator, directory);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    if (config.filters.len == 0 and config.limit == null) {
        // No filters, show all
        if (config.json_output) {
            try outputJson(allocator, neuronas);
        } else {
            try outputList(allocator, neuronas);
        }
        return;
    }

    // Step 2: Apply filters
    var results = std.ArrayListUnmanaged(*const Neurona){};
    defer results.deinit(allocator);

    var count: usize = 0;

    for (neuronas) |*neurona| {
        if (matchesFilters(neurona, config.filters)) {
            try results.append(allocator, neurona);
            count += 1;

            if (config.limit) |limit| {
                if (count >= limit) break;
            }
        }
    }

    // Step 3: Sort results (by id for now)
    const sorted = try results.toOwnedSlice(allocator);
    defer allocator.free(sorted);

    // Step 4: Output - Dereference pointers for output
    var output_neuronas = std.ArrayListUnmanaged(Neurona){};
    defer output_neuronas.deinit(allocator);

    for (sorted) |n| {
        try output_neuronas.append(allocator, n.*);
    }

    if (config.json_output) {
        try outputJson(allocator, output_neuronas.items);
    } else {
        try outputList(allocator, output_neuronas.items);
    }
}

/// Filter mode using AST evaluator (Phase 3)
pub fn executeFilterQueryWithAST(allocator: Allocator, config: QueryConfig, ast: *const @import("../utils/eql_parser.zig").QueryAST) !void {
    const eql_parser = @import("../utils/eql_parser.zig");

    // Step 1: Scan all Neuronas
    const directory = try getNeuronasDir(allocator, config.cortex_dir);
    defer allocator.free(directory);

    const neuronas = try storage.scanNeuronas(allocator, directory);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Step 2: Apply AST evaluator with NeuronaView
    var results = std.ArrayListUnmanaged(*const Neurona){};
    defer results.deinit(allocator);

    var count: usize = 0;

    for (neuronas) |*neurona| {
        // Create NeuronaView for evaluation
        var view = try createNeuronaView(allocator, neurona);
        defer view.deinit(allocator);

        if (eql_parser.evaluateAST(ast.root, &view)) {
            try results.append(allocator, neurona);
            count += 1;

            if (config.limit) |limit| {
                if (count >= limit) break;
            }
        }
    }

    // Step 3: Sort results (by id for now)
    const sorted = try results.toOwnedSlice(allocator);
    defer allocator.free(sorted);

    // Step 4: Output - Dereference pointers for output
    var output_neuronas = std.ArrayListUnmanaged(Neurona){};
    defer output_neuronas.deinit(allocator);

    for (sorted) |n| {
        try output_neuronas.append(allocator, n.*);
    }

    if (config.json_output) {
        try outputJson(allocator, output_neuronas.items);
    } else {
        try outputList(allocator, output_neuronas.items);
    }
}

/// Create a NeuronaView from a Neurona for evaluation
fn createNeuronaView(allocator: Allocator, neurona: *const Neurona) !@import("../utils/eql_parser.zig").NeuronaView {
    const eql_parser = @import("../utils/eql_parser.zig");

    var view = eql_parser.NeuronaView{
        .id = neurona.id,
        .type = switch (neurona.type) {
            .concept => .concept,
            .reference => .reference,
            .artifact => .artifact,
            .state_machine => .state_machine,
            .lesson => .lesson,
            .requirement => .requirement,
            .test_case => .test_case,
            .issue => .issue,
            .feature => .feature,
        },
        .title = neurona.title,
        .tags = neurona.tags.items,
        .connections = .{},
    };

    // Copy connections
    var conn_it = neurona.connections.iterator();
    while (conn_it.next()) |entry| {
        // Parse connection type from key (which is @tagName(connection_type))
        const conn_type = eql_parser.connectionTypeFromString(entry.key_ptr.*) orelse continue;

        var conn_list = eql_parser.ConnectionList{
            .connection_type = conn_type,
            .connections = .{},
        };

        for (entry.value_ptr.connections.items) |*conn| {
            try conn_list.connections.append(allocator, .{
                .target_id = try allocator.dupe(u8, conn.target_id),
                .weight = conn.weight, // u8 from Neurona.Connection
            });
        }

        try view.connections.put(allocator, entry.key_ptr.*, conn_list);
    }

    return view;
}

/// Check if Neurona matches all filters
fn matchesFilters(neurona: *const Neurona, filters: []const QueryFilter) bool {
    if (filters.len == 0) return true;

    for (filters) |filter| {
        if (!matchesFilter(neurona, filter)) return false;
    }
    return true;
}

/// Match a single filter
fn matchesFilter(neurona: *const Neurona, filter: QueryFilter) bool {
    return switch (filter) {
        .type_filter => |tf| matchesTypeFilter(neurona, tf),
        .tag_filter => |tf| matchesTagFilter(neurona, tf),
        .connection_filter => |cf| matchesConnectionFilter(neurona, cf),
        .field_filter => |ff| matchesFieldFilter(neurona, ff),
    };
}

/// Match type filter
fn matchesTypeFilter(neurona: *const Neurona, filter: TypeFilter) bool {
    const type_str = @tagName(neurona.type);
    for (filter.types.items) |t| {
        if (filter.include) {
            if (std.mem.eql(u8, type_str, t)) return true;
        } else {
            if (std.mem.eql(u8, type_str, t)) return false;
        }
    }
    return !filter.include;
}

/// Match tag filter
fn matchesTagFilter(neurona: *const Neurona, filter: TagFilter) bool {
    for (filter.tags.items) |tag| {
        for (neurona.tags.items) |neurona_tag| {
            if (std.mem.eql(u8, neurona_tag, tag)) {
                return filter.include;
            }
        }
    }
    return !filter.include;
}

/// Match connection filter
fn matchesConnectionFilter(neurona: *const Neurona, filter: ConnectionFilter) bool {
    var conn_it = neurona.connections.iterator();
    var has_match = false;

    while (conn_it.next()) |entry| {
        for (entry.value_ptr.connections.items) |*conn| {
            const conn_matches = matchesSingleConnection(conn, filter);

            if (conn_matches and filter.operator == .@"and") {
                has_match = true;
                break; // At least one match required
            }

            if (conn_matches and filter.operator == .not) {
                return false; // Found a match when we should NOT match
            }

            if (conn_matches) has_match = true;
        }
    }

    return switch (filter.operator) {
        .@"or" => has_match, // Found at least one match
        .not => !has_match,
        .@"and" => has_match,
    };
}

/// Match a single connection
fn matchesSingleConnection(conn: *const Connection, filter: ConnectionFilter) bool {
    if (filter.connection_type) |ct| {
        const type_name = @tagName(conn.connection_type);
        if (std.mem.eql(u8, type_name, ct)) {
            return true;
        }
    }

    if (filter.target_id) |tid| {
        if (std.mem.eql(u8, conn.target_id, tid)) {
            return true;
        }
    }

    return false;
}

/// BM25 text search mode
pub fn executeBM25Query(allocator: Allocator, config: QueryConfig) !void {
    if (config.query_text.len == 0) {
        std.debug.print("Error: Text search requires a query string\n", .{});
        return error.MissingQueryText;
    }

    // Step 1: Scan all Neuronas
    const directory = try getNeuronasDir(allocator, config.cortex_dir);
    defer allocator.free(directory);

    const neuronas = try storage.scanNeuronas(allocator, directory);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Step 2: Build BM25 index
    var bm25_index = storage.BM25Index.init();
    defer bm25_index.deinit(allocator);

    for (neuronas) |*neurona| {
        // Combine title and tags for indexing
        var content = std.ArrayList(u8){};
        try content.ensureTotalCapacity(allocator, neurona.title.len + 200); // Reserve space for title + tags
        defer content.deinit(allocator);

        try content.appendSlice(allocator, neurona.title);

        // Add tags to search content
        for (neurona.tags.items) |tag| {
            try content.appendSlice(allocator, " ");
            try content.appendSlice(allocator, tag);
        }

        try bm25_index.addDocument(allocator, neurona.id, content.items);
    }

    bm25_index.build();

    // Step 3: Search
    const limit = config.limit orelse 50;
    const results = try bm25_index.search(allocator, config.query_text, limit);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    // Step 4: Output results with scores
    if (config.json_output) {
        try outputJsonWithScores(results, neuronas);
    } else {
        try outputListWithScores(results, neuronas, "BM25 Score");
    }
}

/// Vector similarity search mode
fn executeVectorQuery(allocator: Allocator, config: QueryConfig) !void {
    if (config.query_text.len == 0) {
        std.debug.print("Error: Vector search requires a query string\n", .{});
        return error.MissingQueryText;
    }

    // Step 1: Scan all Neuronas
    const directory = try getNeuronasDir(allocator, config.cortex_dir);
    defer allocator.free(directory);

    const neuronas = try storage.scanNeuronas(allocator, directory);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Step 2: Load GloVe index
    var glove_index = GloVeIndex.init(allocator);
    defer glove_index.deinit(allocator);

    const glove_cache_path = "glove_cache.bin";
    if (GloVeIndex.cacheExists(glove_cache_path)) {
        try glove_index.loadCacheZeroCopy(allocator, glove_cache_path);
    } else {
        std.debug.print("Error: GloVe cache not found at {s}\n", .{glove_cache_path});
        std.debug.print("Please create a GloVe cache first using the engram index command\n", .{});
        return error.GloVeCacheNotFound;
    }

    const vector_index_path = try storage.VectorIndex.getVectorIndexPath(allocator);
    defer allocator.free(vector_index_path);

    var vector_index: storage.VectorIndex = undefined;
    var loaded_from_cache = false;

    if (storage.VectorIndex.load(allocator, vector_index_path)) |loaded| {
        vector_index = loaded.index;
        loaded_from_cache = true;
    } else |_| {
        // Fallback: Build index if cache is missing
        vector_index = storage.VectorIndex.init(allocator, glove_index.dimension);
        for (neuronas) |*neurona| {
            const embedding = try createGloVeEmbedding(allocator, neurona, &glove_index);
            defer allocator.free(embedding);
            try vector_index.addVector(allocator, neurona.id, embedding);
        }
    }
    defer vector_index.deinit(allocator);

    // Step 3: Create query vector
    const query_embedding = try createGloVeQueryEmbedding(allocator, config.query_text, &glove_index);
    defer allocator.free(query_embedding);

    // Step 4: Search
    const limit = config.limit orelse 50;
    const results = try vector_index.search(allocator, query_embedding, limit);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    // Step 5: Output results with scores
    if (config.json_output) {
        try outputJsonWithScores(results, neuronas);
    } else {
        try outputListWithScores(results, neuronas, "Similarity");
    }
}

/// Hybrid search mode: BM25 + Vector + Fusion
fn executeHybridQuery(allocator: Allocator, config: QueryConfig) !void {
    if (config.query_text.len == 0) {
        std.debug.print("Error: Hybrid search requires a query string\n", .{});
        return error.MissingQueryText;
    }

    // Step 1: Scan all Neuronas
    const directory = try getNeuronasDir(allocator, config.cortex_dir);
    defer allocator.free(directory);

    const neuronas = try storage.scanNeuronas(allocator, directory);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Step 2: Build BM25 index
    var bm25_index = storage.BM25Index.init();
    defer bm25_index.deinit(allocator);

    for (neuronas) |*neurona| {
        var content = std.ArrayList(u8){};
        try content.ensureTotalCapacity(allocator, neurona.title.len + 200);
        defer content.deinit(allocator);
        try content.appendSlice(allocator, neurona.title);
        for (neurona.tags.items) |tag| {
            try content.appendSlice(allocator, " ");
            try content.appendSlice(allocator, tag);
        }
        try bm25_index.addDocument(allocator, neurona.id, content.items);
    }
    bm25_index.build();

    // Step 3: Load GloVe index
    var glove_index = GloVeIndex.init(allocator);
    defer glove_index.deinit(allocator);

    const glove_cache_path = "glove_cache.bin";
    if (GloVeIndex.cacheExists(glove_cache_path)) {
        try glove_index.loadCacheZeroCopy(allocator, glove_cache_path);
    } else {
        std.debug.print("Error: GloVe cache not found at {s}\n", .{glove_cache_path});
        std.debug.print("Please create a GloVe cache first using engram index command\n", .{});
        return error.GloVeCacheNotFound;
    }

    const vector_index_path = try storage.VectorIndex.getVectorIndexPath(allocator);
    defer allocator.free(vector_index_path);

    var vector_index: storage.VectorIndex = undefined;
    var loaded_from_cache = false;

    if (storage.VectorIndex.load(allocator, vector_index_path)) |loaded| {
        vector_index = loaded.index;
        loaded_from_cache = true;
    } else |_| {
        // Fallback: Build index if cache is missing
        vector_index = storage.VectorIndex.init(allocator, glove_index.dimension);
        for (neuronas) |*neurona| {
            const embedding = try createGloVeEmbedding(allocator, neurona, &glove_index);
            defer allocator.free(embedding);
            try vector_index.addVector(allocator, neurona.id, embedding);
        }
    }
    defer vector_index.deinit(allocator);

    // Step 4: Run both searches
    const limit = config.limit orelse 50;
    const bm25_results = try bm25_index.search(allocator, config.query_text, limit);
    defer {
        for (bm25_results) |*r| r.deinit(allocator);
        allocator.free(bm25_results);
    }

    const query_embedding = try createGloVeQueryEmbedding(allocator, config.query_text, &glove_index);
    defer allocator.free(query_embedding);
    const vector_results = try vector_index.search(allocator, query_embedding, limit);
    defer {
        for (vector_results) |*r| r.deinit(allocator);
        allocator.free(vector_results);
    }

    // Step 5: Fusion: Combine scores (0.6 * BM25 + 0.4 * Vector)
    var fused_scores = std.StringHashMap(f32).init(allocator);
    defer {
        var it = fused_scores.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        fused_scores.deinit();
    }

    // Add BM25 scores
    for (bm25_results) |r| {
        const key = try allocator.dupe(u8, r.doc_id);
        try fused_scores.put(key, r.score * 0.6);
    }

    // Add vector scores and merge
    for (vector_results) |r| {
        if (fused_scores.getPtr(r.doc_id)) |score| {
            score.* += r.score * 0.4;
        } else {
            const key = try allocator.dupe(u8, r.doc_id);
            try fused_scores.put(key, r.score * 0.4);
        }
    }

    // Step 6: Sort by fused score
    var sorted_results = std.ArrayList(FusedResult){};
    try sorted_results.ensureTotalCapacity(allocator, 50);
    defer {
        for (sorted_results.items) |*r| allocator.free(r.id);
        sorted_results.deinit(allocator);
    }

    var it = fused_scores.iterator();
    while (it.next()) |entry| {
        try sorted_results.append(allocator, .{
            .id = try allocator.dupe(u8, entry.key_ptr.*),
            .score = entry.value_ptr.*,
        });
    }

    std.sort.insertion(@TypeOf(sorted_results.items[0]), sorted_results.items, {}, struct {
        fn lessThan(_: void, a: @TypeOf(sorted_results.items[0]), b: @TypeOf(sorted_results.items[0])) bool {
            return a.score > b.score;
        }
    }.lessThan);

    // Limit results
    if (sorted_results.items.len > limit) {
        for (sorted_results.items[limit..]) |*r| allocator.free(r.id);
        sorted_results.items.len = limit;
    }

    // Step 7: Output results
    if (config.json_output) {
        try outputJsonWithFusedScores(sorted_results.items, neuronas);
    } else {
        try outputListWithFusedScores(sorted_results.items, neuronas, "Fused Score");
    }
}

/// Neural activation search mode
fn executeActivationQuery(allocator: Allocator, config: QueryConfig) !void {
    if (config.query_text.len == 0) {
        std.debug.print("Error: Activation search requires a query string\n", .{});
        return error.MissingQueryText;
    }

    // Step 1: Scan all Neuronas
    const directory = try getNeuronasDir(allocator, config.cortex_dir);
    defer allocator.free(directory);

    const neuronas = try storage.scanNeuronas(allocator, directory);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Step 2: Build Graph
    var graph = Graph.init();
    defer graph.deinit(allocator);

    for (neuronas) |*neurona| {
        var conn_it = neurona.connections.iterator();
        while (conn_it.next()) |entry| {
            const conn_list = entry.value_ptr.*;
            for (conn_list.connections.items) |*conn| {
                try graph.addEdge(allocator, neurona.id, conn.target_id, conn.weight);
            }
        }
    }

    // Step 3: Build BM25 index
    var bm25_index = storage.BM25Index.init();
    defer bm25_index.deinit(allocator);

    for (neuronas) |*neurona| {
        var content = std.ArrayList(u8){};
        try content.ensureTotalCapacity(allocator, neurona.title.len + 200);
        defer content.deinit(allocator);
        try content.appendSlice(allocator, neurona.title);
        for (neurona.tags.items) |tag| {
            try content.appendSlice(allocator, " ");
            try content.appendSlice(allocator, tag);
        }
        try bm25_index.addDocument(allocator, neurona.id, content.items);
    }
    bm25_index.build();

    // Step 4: Build vector index (simplified - just use dummy vectors)
    const dimension = 100;
    var vector_index = storage.VectorIndex.init(allocator, dimension);
    defer vector_index.deinit(allocator);

    for (neuronas) |*neurona| {
        const embedding = try createSimpleEmbedding(allocator, neurona, dimension);
        defer allocator.free(embedding);
        try vector_index.addVector(allocator, neurona.id, embedding);
    }

    // Step 5: Initialize neural activation
    var activation = NeuralActivation.init(&graph, &bm25_index, &vector_index);

    // Step 6: Run activation
    const results = try activation.activate(allocator, config.query_text, null);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    // Step 7: Output results
    if (config.json_output) {
        try outputJsonWithActivation(results, neuronas);
    } else {
        try outputListWithActivation(results, neuronas);
    }
}

/// Create a simple word frequency embedding for a Neurona
fn createSimpleEmbedding(allocator: Allocator, neurona: *const Neurona, dimension: usize) ![]f32 {
    const embedding = try allocator.alloc(f32, dimension);
    @memset(embedding, 0.0);

    var content = std.ArrayList(u8){};
    try content.ensureTotalCapacity(allocator, neurona.title.len + 200);
    defer content.deinit(allocator);

    try content.appendSlice(allocator, neurona.title);
    for (neurona.tags.items) |tag| {
        try content.appendSlice(allocator, " ");
        try content.appendSlice(allocator, tag);
    }

    // Tokenize and create simple hash-based embedding
    const lower = try allocator.alloc(u8, content.items.len);
    defer allocator.free(lower);
    for (content.items, 0..) |c, i| {
        lower[i] = std.ascii.toLower(c);
    }

    var start: usize = 0;
    var in_word = false;
    for (lower, 0..) |c, i| {
        const is_alpha = std.ascii.isAlphanumeric(c);
        if (is_alpha and !in_word) {
            start = i;
            in_word = true;
        } else if (!is_alpha and in_word) {
            const word = lower[start..i];
            if (word.len >= 2) {
                // Simple hash to map words to dimensions
                const hash = @rem(std.hash.Wyhash.hash(0, word), dimension);
                embedding[hash] += 1.0;
            }
            in_word = false;
        }
    }
    return embedding;
}

/// Create GloVe embedding for a neurona document
pub fn createGloVeEmbedding(allocator: Allocator, neurona: *const Neurona, glove_index: *const GloVeIndex) ![]f32 {
    // Combine title and tags for embedding
    var content = std.ArrayListUnmanaged(u8){};
    try content.ensureTotalCapacity(allocator, neurona.title.len + 200);
    defer content.deinit(allocator);

    try content.appendSlice(allocator, neurona.title);
    for (neurona.tags.items) |tag| {
        try content.appendSlice(allocator, " ");
        try content.appendSlice(allocator, tag);
    }

    // Tokenize and create GloVe embedding
    const lower = try allocator.alloc(u8, content.items.len);
    defer allocator.free(lower);
    for (content.items, 0..) |c, i| {
        lower[i] = std.ascii.toLower(c);
    }

    var words = std.ArrayListUnmanaged([]const u8){};
    defer words.deinit(allocator);

    var start: usize = 0;
    var in_word = false;
    for (lower, 0..) |c, i| {
        const is_alpha = std.ascii.isAlphanumeric(c);
        if (is_alpha and !in_word) {
            start = i;
            in_word = true;
        } else if (!is_alpha and in_word) {
            const word = lower[start..i];
            if (word.len >= 2) {
                try words.append(allocator, word);
            }
            in_word = false;
        }
    }
    // Handle last word
    if (in_word) {
        const word = lower[start..];
        if (word.len >= 2) {
            try words.append(allocator, word);
        }
    }

    // Create GloVe embedding by averaging word vectors
    return try glove_index.computeEmbedding(allocator, words.items);
}

/// Create a GloVe embedding for a query string
fn createGloVeQueryEmbedding(allocator: Allocator, query: []const u8, glove_index: *GloVeIndex) ![]f32 {
    const lower = try allocator.alloc(u8, query.len);
    defer allocator.free(lower);
    for (query, 0..) |c, i| {
        lower[i] = std.ascii.toLower(c);
    }

    var words = std.ArrayList([]const u8){};
    defer words.deinit(allocator);

    var start: usize = 0;
    var in_word = false;
    for (lower, 0..) |c, i| {
        const is_alpha = std.ascii.isAlphanumeric(c);
        if (is_alpha and !in_word) {
            start = i;
            in_word = true;
        } else if (!is_alpha and in_word) {
            const word = lower[start..i];
            if (word.len >= 2) {
                try words.append(allocator, word);
            }
            in_word = false;
        }
    }
    // Handle last word
    if (in_word) {
        const word = lower[start..];
        if (word.len >= 2) {
            try words.append(allocator, word);
        }
    }

    // Create GloVe embedding by averaging word vectors
    return try glove_index.computeEmbedding(allocator, words.items);
}

/// Create a simple embedding for a query string
fn createQueryEmbedding(allocator: Allocator, query: []const u8, dimension: usize) ![]f32 {
    const embedding = try allocator.alloc(f32, dimension);
    @memset(embedding, 0.0);

    const lower = try allocator.alloc(u8, query.len);
    defer allocator.free(lower);
    for (query, 0..) |c, i| {
        lower[i] = std.ascii.toLower(c);
    }

    var start: usize = 0;
    var in_word = false;
    for (lower, 0..) |c, i| {
        const is_alpha = std.ascii.isAlphanumeric(c);
        if (is_alpha and !in_word) {
            start = i;
            in_word = true;
        } else if (!is_alpha and in_word) {
            const word = lower[start..i];
            if (word.len >= 2) {
                const hash = @rem(std.hash.Wyhash.hash(0, word), dimension);
                embedding[hash] += 1.0;
            }
            in_word = false;
        }
    }
    return embedding;
}

/// Output list with scores
fn outputListWithScores(results: anytype, neuronas: []const Neurona, score_label: []const u8) !void {
    std.debug.print("\n🔍 Search Results\n", .{});
    for (0..40) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});

    if (results.len == 0) {
        std.debug.print("No results found\n", .{});
        return;
    }

    // Create lookup map
    const page_allocator = std.heap.page_allocator;
    var neurona_map = std.StringHashMap(*const Neurona).init(page_allocator);
    defer neurona_map.deinit();
    for (neuronas) |*n| {
        try neurona_map.put(n.id, n);
    }

    for (results) |result| {
        if (neurona_map.get(result.doc_id)) |neurona| {
            std.debug.print("  {s}\n", .{neurona.id});
            std.debug.print("    Type: {s}\n", .{@tagName(neurona.type)});
            std.debug.print("    Title: {s}\n", .{neurona.title});
            std.debug.print("    {s}: {d:.3}\n", .{ score_label, result.score });

            if (neurona.tags.items.len > 0) {
                std.debug.print("    Tags: ", .{});
                for (neurona.tags.items, 0..) |tag, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{tag});
                }
                std.debug.print("\n", .{});
            }
            std.debug.print("\n", .{});
        }
    }

    std.debug.print("  Found {d} results\n", .{results.len});
}

/// Output list with fused scores
fn outputListWithFusedScores(results: []const FusedResult, neuronas: []const Neurona, score_label: []const u8) !void {
    std.debug.print("\n🔍 Hybrid Search Results\n", .{});
    for (0..40) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});

    if (results.len == 0) {
        std.debug.print("No results found\n", .{});
        return;
    }

    const page_allocator = std.heap.page_allocator;
    var neurona_map = std.StringHashMap(*const Neurona).init(page_allocator);
    defer neurona_map.deinit();
    for (neuronas) |*n| {
        try neurona_map.put(n.id, n);
    }

    for (results) |result| {
        if (neurona_map.get(result.id)) |neurona| {
            std.debug.print("  {s}\n", .{neurona.id});
            std.debug.print("    Type: {s}\n", .{@tagName(neurona.type)});
            std.debug.print("    Title: {s}\n", .{neurona.title});
            std.debug.print("    {s}: {d:.3}\n", .{ score_label, result.score });

            if (neurona.tags.items.len > 0) {
                std.debug.print("    Tags: ", .{});
                for (neurona.tags.items, 0..) |tag, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{tag});
                }
                std.debug.print("\n", .{});
            }
            std.debug.print("\n", .{});
        }
    }

    std.debug.print("  Found {d} results\n", .{results.len});
}

/// Output list with activation scores
fn outputListWithActivation(results: []const @import("../root.zig").core.ActivationResult, neuronas: []const Neurona) !void {
    std.debug.print("\n🧠 Neural Activation Results\n", .{});
    for (0..40) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});

    if (results.len == 0) {
        std.debug.print("No results found\n", .{});
        return;
    }

    const page_allocator = std.heap.page_allocator;
    var neurona_map = std.StringHashMap(*const Neurona).init(page_allocator);
    defer neurona_map.deinit();
    for (neuronas) |*n| {
        try neurona_map.put(n.id, n);
    }

    for (results) |result| {
        if (neurona_map.get(result.node_id)) |neurona| {
            std.debug.print("  {s}\n", .{neurona.id});
            std.debug.print("    Type: {s}\n", .{@tagName(neurona.type)});
            std.debug.print("    Title: {s}\n", .{neurona.title});
            std.debug.print("    Stimulus: {d:.3}\n", .{result.stimulus_score});
            std.debug.print("    Activation: {d:.3}\n", .{result.activation_score});
            std.debug.print("    Depth: {d}\n", .{result.depth});

            if (neurona.tags.items.len > 0) {
                std.debug.print("    Tags: ", .{});
                for (neurona.tags.items, 0..) |tag, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{tag});
                }
                std.debug.print("\n", .{});
            }
            std.debug.print("\n", .{});
        }
    }

    std.debug.print("  Found {d} results\n", .{results.len});
}

/// JSON output with scores
fn outputJsonWithScores(results: anytype, neuronas: []const Neurona) !void {
    std.debug.print("[", .{});
    for (results, 0..) |result, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{{", .{});
        std.debug.print("\"id\":\"{s}\",", .{result.doc_id});
        std.debug.print("\"score\":{d:.3}", .{result.score});

        // Find neurona by id
        for (neuronas) |n| {
            if (std.mem.eql(u8, n.id, result.doc_id)) {
                std.debug.print(",\"title\":\"{s}\",", .{n.title});
                std.debug.print("\"type\":\"{s}\"", .{@tagName(n.type)});
                break;
            }
        }
        std.debug.print("}}", .{});
    }
    std.debug.print("]\n", .{});
}

/// JSON output with fused scores
fn outputJsonWithFusedScores(results: []const FusedResult, neuronas: []const Neurona) !void {
    std.debug.print("[", .{});
    for (results, 0..) |result, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{{", .{});
        std.debug.print("\"id\":\"{s}\",", .{result.id});
        std.debug.print("\"score\":{d:.3}", .{result.score});

        for (neuronas) |n| {
            if (std.mem.eql(u8, n.id, result.id)) {
                std.debug.print(",\"title\":\"{s}\",", .{n.title});
                std.debug.print("\"type\":\"{s}\"", .{@tagName(n.type)});
                break;
            }
        }
        std.debug.print("}}", .{});
    }
    std.debug.print("]\n", .{});
}

/// JSON output with activation scores
fn outputJsonWithActivation(results: []const @import("../root.zig").core.ActivationResult, neuronas: []const Neurona) !void {
    std.debug.print("[", .{});
    for (results, 0..) |result, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{{", .{});
        std.debug.print("\"id\":\"{s}\",", .{result.node_id});
        std.debug.print("\"stimulus\":{d:.3},", .{result.stimulus_score});
        std.debug.print("\"activation\":{d:.3},", .{result.activation_score});
        std.debug.print("\"depth\":{d}", .{result.depth});

        for (neuronas) |n| {
            if (std.mem.eql(u8, n.id, result.node_id)) {
                std.debug.print(",\"title\":\"{s}\",", .{n.title});
                std.debug.print("\"type\":\"{s}\"", .{@tagName(n.type)});
                break;
            }
        }
        std.debug.print("}}", .{});
    }
    std.debug.print("]\n", .{});
}

/// Match field filter
fn matchesFieldFilter(neurona: *const Neurona, filter: FieldFilter) bool {
    // For now, just check basic fields (id, title, type, status)
    const value = filter.value orelse return false;

    if (std.mem.eql(u8, filter.field, "id")) {
        return std.mem.eql(u8, neurona.id, value);
    } else if (std.mem.eql(u8, filter.field, "title")) {
        return std.mem.indexOf(u8, neurona.title, value) != null;
    } else if (std.mem.eql(u8, filter.field, "type")) {
        const type_str = @tagName(neurona.type);
        return std.mem.eql(u8, type_str, value);
    } else {
        return false;
    }
}

/// Sort results by ID
fn sortResults(allocator: Allocator, neuras: *[]*const Neurona) ![]const Neurona {
    // Simple bubble sort for small lists
    // For production, use std.sort

    const count = neuras.len;
    for (0..@min(3, count - 2)) |i| {
        for (0..count - i - 1) |j| {
            if (std.mem.order(u8, neuras[j].id, neuras[j + 1].id) == .gt) {
                const tmp = neuras[j];
                neuras[j] = neuras[j + 1];
                neuras[j + 1] = tmp;
            }
        }
    }

    return try allocator.dupe(*const Neurona, neuras.*);
}

/// Output list format
fn outputList(allocator: Allocator, neuras: []const Neurona) !void {
    _ = allocator;
    std.debug.print("\n🔍 Search Results\n", .{});
    for (0..40) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});

    if (neuras.len == 0) {
        std.debug.print("No results found matching criteria\n", .{});
        return;
    }

    const display_count = @min(10, neuras.len);
    for (neuras[0..display_count]) |neurona| {
        std.debug.print("  {s}\n", .{neurona.id});
        std.debug.print("    Type: {s}\n", .{@tagName(neurona.type)});
        std.debug.print("    Title: {s}\n", .{neurona.title});

        // Show tags
        if (neurona.tags.items.len > 0) {
            std.debug.print("    Tags: ", .{});
            for (neurona.tags.items, 0..) |tag, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{tag});
            }
            std.debug.print("\n", .{});
        }
    }

    std.debug.print("\n  Found {d} results\n", .{neuras.len});
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

/// JSON output for AI - complete neurona data
fn outputJson(allocator: Allocator, neuras: []const Neurona) !void {
    _ = allocator;
    std.debug.print("[", .{});
    for (neuras, 0..) |neurona, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{{", .{});
        std.debug.print("\"id\":\"{s}\",", .{neurona.id});
        std.debug.print("\"title\":\"{s}\",", .{neurona.title});
        std.debug.print("\"type\":\"{s}\",", .{@tagName(neurona.type)});

        // Tags
        std.debug.print("\"tags\":[", .{});
        for (neurona.tags.items, 0..) |tag, ti| {
            if (ti > 0) std.debug.print(",", .{});
            printJsonString(tag);
        }
        std.debug.print("],", .{});

        // Context
        std.debug.print("\"context\":{{", .{});
        switch (neurona.context) {
            .requirement => |ctx| {
                std.debug.print("\"status\":\"{s}\",", .{ctx.status});
                std.debug.print("\"verification_method\":\"{s}\",", .{ctx.verification_method});
                std.debug.print("\"priority\":{d}", .{ctx.priority});
                if (ctx.assignee) |a| std.debug.print(",\"assignee\":\"{s}\"", .{a});
            },
            .test_case => |ctx| {
                std.debug.print("\"status\":\"{s}\",", .{ctx.status});
                std.debug.print("\"framework\":\"{s}\"", .{ctx.framework});
                if (ctx.assignee) |a| std.debug.print(",\"assignee\":\"{s}\"", .{a});
            },
            .issue => |ctx| {
                std.debug.print("\"status\":\"{s}\",", .{ctx.status});
                std.debug.print("\"priority\":{d}", .{ctx.priority});
                if (ctx.assignee) |a| std.debug.print(",\"assignee\":\"{s}\"", .{a});
            },
            .artifact => |ctx| {
                std.debug.print("\"runtime\":\"{s}\",", .{ctx.runtime});
                std.debug.print("\"file_path\":\"{s}\"", .{ctx.file_path});
            },
            else => {},
        }
        std.debug.print("}},", .{});

        // LLM metadata
        if (neurona.llm_metadata) |*meta| {
            std.debug.print("\"_llm\":{{", .{});
            std.debug.print("\"t\":\"{s}\",", .{meta.short_title});
            std.debug.print("\"d\":{d},", .{meta.density});
            std.debug.print("\"strategy\":\"{s}\"", .{meta.strategy});
            if (meta.keywords.items.len > 0) {
                std.debug.print(",\"k\":[", .{});
                for (meta.keywords.items, 0..) |kw, ki| {
                    if (ki > 0) std.debug.print(",", .{});
                    printJsonString(kw);
                }
                std.debug.print("]", .{});
                std.debug.print(",\"c\":{d}", .{meta.token_count});
            }
            std.debug.print("}},", .{});
        }

        // Connections count
        std.debug.print("\"connections\":{d}", .{neurona.connections.count()});
        std.debug.print("}}", .{});
    }
    std.debug.print("]\n", .{});
}

// Example CLI usage:
//
//   engram query
//   → List all Neuronas
//
//   engram query --type issue
//   → List only issues
//
//   engram query --tag "bug,p1"
//   → List Neuronas with bug or p1 tags
//
//   engram query --limit 10
//   → Limit results to 10 items
//
//   engram query --json
//   → Return JSON for AI parsing

// ==================== Tests ====================

test "QueryConfig with default values" {
    const query_mod = @import("query.zig");

    const config = query_mod.QueryConfig{
        .filters = &[_]query_mod.QueryFilter{},
        .limit = null,
        .json_output = false,
    };

    try std.testing.expectEqual(@as(usize, 0), config.filters.len);
    try std.testing.expectEqual(@as(?usize, null), config.limit);
    try std.testing.expectEqual(false, config.json_output);
}

test "QueryConfig with limit and JSON set" {
    const query_mod = @import("query.zig");

    const config = query_mod.QueryConfig{
        .filters = &[_]query_mod.QueryFilter{},
        .limit = 10,
        .json_output = true,
    };

    try std.testing.expectEqual(@as(usize, 0), config.filters.len);
    try std.testing.expectEqual(@as(usize, 10), config.limit.?);
    try std.testing.expectEqual(true, config.json_output);
}

test "QueryFilter type_filter variant" {
    const query_mod = @import("query.zig");
    const allocator = std.testing.allocator;

    var types = std.ArrayListUnmanaged([]const u8){};
    try types.append(allocator, try allocator.dupe(u8, "issue"));
    try types.append(allocator, try allocator.dupe(u8, "requirement"));

    var filter = query_mod.QueryFilter{
        .type_filter = query_mod.TypeFilter{
            .types = types,
            .include = true,
        },
    };

    const type_filter = &filter.type_filter;
    try std.testing.expectEqual(@as(usize, 2), type_filter.types.items.len);
    try std.testing.expectEqual(true, type_filter.include);

    type_filter.deinit(allocator);
}

test "matchesFilters with type filter" {
    const allocator = std.testing.allocator;

    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);
    neurona.type = .issue;

    var types = std.ArrayListUnmanaged([]const u8){};
    try types.append(allocator, try allocator.dupe(u8, "issue"));
    defer {
        for (types.items) |t| allocator.free(t);
        types.deinit(allocator);
    }

    const filter = QueryFilter{
        .type_filter = TypeFilter{
            .types = types,
            .include = true,
        },
    };

    const filters = [_]QueryFilter{filter};
    try std.testing.expect(matchesFilters(&neurona, &filters));

    var types2 = std.ArrayListUnmanaged([]const u8){};
    try types2.append(allocator, try allocator.dupe(u8, "requirement"));
    defer {
        for (types2.items) |t| allocator.free(t);
        types2.deinit(allocator);
    }

    const filter2 = QueryFilter{
        .type_filter = TypeFilter{
            .types = types2,
            .include = true,
        },
    };
    const filters2 = [_]QueryFilter{filter2};
    try std.testing.expect(!matchesFilters(&neurona, &filters2));
}

test "QueryFilter tag_filter variant" {
    const query_mod = @import("query.zig");
    const allocator = std.testing.allocator;

    var tags = std.ArrayListUnmanaged([]const u8){};
    try tags.append(allocator, try allocator.dupe(u8, "bug"));
    try tags.append(allocator, try allocator.dupe(u8, "feature"));

    var filter = query_mod.QueryFilter{
        .tag_filter = query_mod.TagFilter{
            .tags = tags,
            .include = true,
        },
    };

    const tag_filter = &filter.tag_filter;
    try std.testing.expectEqual(@as(usize, 2), tag_filter.tags.items.len);
    try std.testing.expectEqual(true, tag_filter.include);

    tag_filter.deinit(allocator);
}
