// Core Index Engine
// Manages the creation and maintenance of indices (Graph, Vector, LLM Cache)
// Decoupled from CLI output

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("neurona.zig").Neurona;
const Graph = @import("graph.zig").Graph;
const storage = @import("../storage/filesystem.zig");
const index_storage = @import("../storage/index.zig");
const VectorIndex = @import("../storage/vectors.zig").VectorIndex;
const GloVeIndex = @import("../storage/glove.zig").GloVeIndex;
const LLMCache = @import("../storage/llm_cache.zig").LLMCache;
const validator = @import("validator.zig");

pub const IndexStats = struct {
    neurona_count: usize,
    graph_nodes: usize,
    graph_edges: usize,
    vector_count: usize,
    cache_entries: usize,
    orphans: usize,
};

pub const IndexConfig = struct {
    neuronas_dir: []const u8,
    activations_dir: []const u8,
    force_rebuild: bool = false,
    verbose: bool = false, // If true, caller might want a way to receive logs. For now, we ignore or use debug.
};

/// Main entry point to sync all indices
pub fn sync(allocator: Allocator, config: IndexConfig) !IndexStats {
    // 1. Scan Neuronas
    const neuronas = try storage.scanNeuronas(allocator, config.neuronas_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // 2. Build Graph Index
    const graph_stats = try buildGraphIndex(allocator, neuronas, config.activations_dir);

    // 3. Sync LLM Cache
    const cache_count = try syncLLMCache(allocator, config.activations_dir);

    // 4. Sync Vectors
    const vector_count = try syncVectors(allocator, neuronas, config.neuronas_dir, config.activations_dir, config.force_rebuild);

    // 5. Detect Orphans
    var graph = Graph.init();
    defer graph.deinit(allocator);
    // Re-populate graph just for orphan check (inefficient, but reuses existing validator)
    // Optimization: buildGraphIndex could return the graph, or we pass it to validator before saving.
    // Let's refactor buildGraphIndex to do this internally or return stats.
    
    // For now, simple stats return:
    return IndexStats{
        .neurona_count = neuronas.len,
        .graph_nodes = graph_stats.nodes,
        .graph_edges = graph_stats.edges,
        .vector_count = vector_count,
        .cache_entries = cache_count,
        .orphans = 0, // TODO: calculate orphans if needed
    };
}

const GraphStats = struct { nodes: usize, edges: usize };

/// Build and save graph index
fn buildGraphIndex(allocator: Allocator, neuronas: []const Neurona, activations_dir: []const u8) !GraphStats {
    var graph = Graph.init();
    defer graph.deinit(allocator);

    for (neuronas) |*neurona| {
        var it = neurona.connections.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                try graph.addEdge(allocator, neurona.id, conn.target_id, conn.weight);
            }
        }
    }

    const index_path = try std.fs.path.join(allocator, &.{ activations_dir, "graph.idx" });
    defer allocator.free(index_path);

    // Ensure directory exists
    try std.fs.cwd().makePath(activations_dir);

    try index_storage.saveGraph(allocator, &graph, index_path);

    return GraphStats{ .nodes = graph.nodeCount(), .edges = graph.edgeCount() / 2 };
}

/// Sync LLM Cache
fn syncLLMCache(allocator: Allocator, activations_dir: []const u8) !usize {
    const cache_dir = try std.fs.path.join(allocator, &.{ activations_dir, "cache" });
    defer allocator.free(cache_dir);
    
    try std.fs.cwd().makePath(cache_dir);

    const summaries_path = try std.fs.path.join(allocator, &.{ cache_dir, "summaries.cache" });
    defer allocator.free(summaries_path);
    const tokens_path = try std.fs.path.join(allocator, &.{ cache_dir, "tokens.cache" });
    defer allocator.free(tokens_path);

    var cache = LLMCache.init(allocator);
    defer cache.deinit();

    cache.loadFromDisk(summaries_path, tokens_path) catch {};
    try cache.saveToDisk(summaries_path, tokens_path);

    return cache.summaries.count();
}

/// Sync Vectors
fn syncVectors(allocator: Allocator, neuronas: []const Neurona, neuronas_dir: []const u8, activations_dir: []const u8, force: bool) !usize {
    const vector_path = try std.fs.path.join(allocator, &.{ activations_dir, "vectors.bin" });
    defer allocator.free(vector_path);

    const latest_mtime = try storage.getLatestModificationTime(neuronas_dir);

    if (!force) {
        if (VectorIndex.load(allocator, vector_path)) |loaded| {
            defer loaded.index.deinit(allocator);
            if (loaded.timestamp >= latest_mtime) {
                return loaded.index.count();
            }
        } else |_| {}
    }

    // Need GloVe cache to build
    // Assuming glove_cache.bin is in current dir or known location.
    // Library should probably accept this path in config.
    // For now, default to "glove_cache.bin"
    const glove_cache_path = "glove_cache.bin";
    
    if (!GloVeIndex.cacheExists(glove_cache_path)) {
        return 0; // Skip if no embeddings
    }

    var glove = GloVeIndex.init(allocator);
    defer glove.deinit(allocator);
    try glove.loadCacheZeroCopy(allocator, glove_cache_path);

    var vec_idx = VectorIndex.init(allocator, glove.dimension);
    defer vec_idx.deinit(allocator);

    // Use query_engine helper logic directly or duplicate?
    // Let's implement embedding creation here to avoid circular dep on query_engine if it depends on index_engine.
    // query_engine depends on storage, graph, activation. index_engine depends on storage, graph. 
    // They are independent. But they share "embedding creation logic".
    // That logic should be in `storage/embeddings.zig` or similar.
    // For now, I will inline simple GloVe embedding creation.
    
    for (neuronas) |*n| {
        const vec = try createGloVeEmbedding(allocator, n, &glove);
        defer allocator.free(vec);
        try vec_idx.addVector(allocator, n.id, vec);
    }

    try vec_idx.save(allocator, vector_path, latest_mtime);
    return vec_idx.count();
}

fn createGloVeEmbedding(allocator: Allocator, neurona: *const Neurona, glove: *const GloVeIndex) ![]f32 {
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();
    try content.appendSlice(neurona.title);
    for (neurona.tags.items) |t| {
        try content.appendSlice(" ");
        try content.appendSlice(t);
    }
    
    // Tokenize
    var words = std.ArrayList([]const u8).init(allocator);
    defer words.deinit();
    
    // Very simple tokenizer (split by whitespace/non-alpha)
    // To match CLI exactly we'd need exact logic.
    // Simplified:
        var it = std.mem.tokenizeAny(u8, content.items, " \t\n\r.,:;()[]{}");    while (it.next()) |token| {
        try words.append(token);
    }
    
    return try glove.computeEmbedding(allocator, words.items);
}
