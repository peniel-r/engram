// Core Query Engine
// Implements the search logic for Engram/Neurona
// Decoupled from CLI parsing and output

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("neurona.zig").Neurona;
const NeuronaType = @import("neurona.zig").NeuronaType;
const Graph = @import("graph.zig").Graph;
const NeuralActivation = @import("activation.zig").NeuralActivation;
const ActivationResult = @import("activation.zig").ActivationResult;
const storage = @import("../storage/filesystem.zig");
const BM25Index = @import("../storage/tfidf.zig").BM25Index;
const VectorIndex = @import("../storage/vectors.zig").VectorIndex;
const GloVeIndex = @import("../storage/glove.zig").GloVeIndex;

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

/// Result struct for hybrid/fused search
pub const FusedResult = struct {
    id: []const u8,
    score: f32,
    
    // Optional metadata for convenience
    title: ?[]const u8 = null,
    type: ?NeuronaType = null,
};

/// Configuration for query execution
pub const QueryConfig = struct {
    mode: QueryMode = .filter,
    query_text: []const u8 = "",
    filters: []QueryFilter = &[_]QueryFilter{},
    limit: ?usize = null,
    
    // Directory containing neuronas (required)
    neuronas_dir: []const u8,
};

/// Query filter types
pub const QueryFilter = union(enum) {
    type_filter: TypeFilter,
    tag_filter: TagFilter,
    connection_filter: ConnectionFilter,
    field_filter: FieldFilter,
};

pub const TypeFilter = struct {
    types: []const []const u8,
    include: bool = true,
};

pub const TagFilter = struct {
    tags: []const []const u8,
    include: bool = true,
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

/// Result set for queries
pub const QueryResult = union(enum) {
    neuronas: []const Neurona,
    scored: []const FusedResult,
    activation: []const ActivationResult,

    pub fn deinit(self: QueryResult, allocator: Allocator) void {
        switch (self) {
            .neuronas => {
                // The neuronas are typically owned by the caller or scanned list
                // For this result type, we just free the slice if allocated
                allocator.free(self.neuronas); 
            },
            .scored => {
                for (self.scored) |item| {
                    allocator.free(item.id);
                }
                allocator.free(self.scored);
            },
            .activation => {
                for (self.activation) |*item| {
                    item.deinit(allocator);
                }
                allocator.free(self.activation);
            },
        }
    }
};

/// Execute query based on configuration
pub fn execute(allocator: Allocator, config: QueryConfig) !QueryResult {
    // Scan all Neuronas first (in a real DB this would be optimized)
    const neuronas = try storage.scanNeuronas(allocator, config.neuronas_dir);
    // Note: neuronas are owned here. We need to handle lifecycle.
    // Ideally, we pass them down or return them.
    // For now, let's assume the engine takes ownership of loading, 
    // but we need to ensure we don't leak if we filter them.
    // Refactoring strategy: Load once, filter/rank, return subset or new structs.
    
    // Optimization: If we just filter, we can return a slice of the loaded neuronas.
    // But scanNeuronas returns []Neurona (structs).
    // Let's defer deinit of the full list until we extract what we need.
    
    switch (config.mode) {
        .filter => {
            // Filter and return a new list of copies
            var filtered = std.ArrayList(Neurona).init(allocator);
            defer filtered.deinit(); // We will return owned slice
            
            var count: usize = 0;
            for (neuronas) |*n| {
                if (matchesFilters(n, config.filters)) {
                    // Deep copy for return
                    const copy = try deepCopyNeurona(allocator, n);
                    try filtered.append(copy);
                    count += 1;
                    if (config.limit) |lim| {
                        if (count >= lim) break;
                    }
                }
            }
            
            // Clean up original scan
            for (neuronas) |*n| n.deinit(allocator);
            allocator.free(neuronas);
            
            return QueryResult{ .neuronas = try filtered.toOwnedSlice() };
        },
        .text => {
            defer {
                for (neuronas) |*n| n.deinit(allocator);
                allocator.free(neuronas);
            }
            return executeBM25Query(allocator, config, neuronas);
        },
        .vector => {
            defer {
                for (neuronas) |*n| n.deinit(allocator);
                allocator.free(neuronas);
            }
            return executeVectorQuery(allocator, config, neuronas);
        },
        .hybrid => {
            defer {
                for (neuronas) |*n| n.deinit(allocator);
                allocator.free(neuronas);
            }
            return executeHybridQuery(allocator, config, neuronas);
        },
        .activation => {
            defer {
                for (neuronas) |*n| n.deinit(allocator);
                allocator.free(neuronas);
            }
            return executeActivationQuery(allocator, config, neuronas);
        },
    }
}

// --- Helper: Deep copy neurona ---
fn deepCopyNeurona(allocator: Allocator, source: *const Neurona) !Neurona {
    var copy = try Neurona.init(allocator);
    
    // Copy fields
    allocator.free(copy.id);
    copy.id = try allocator.dupe(u8, source.id);
    
    allocator.free(copy.title);
    copy.title = try allocator.dupe(u8, source.title);
    
    copy.type = source.type;
    
    for (source.tags.items) |t| {
        try copy.tags.append(allocator, try allocator.dupe(u8, t));
    }
    
    // Deep copy connections
    var it = source.connections.iterator();
    while (it.next()) |entry| {
        const group_name = entry.key_ptr.*;
        const source_group = entry.value_ptr;
        
        var new_group = @import("neurona.zig").ConnectionGroup.init();
        for (source_group.connections.items) |conn| {
            try new_group.connections.append(allocator, .{
                .target_id = try allocator.dupe(u8, conn.target_id),
                .connection_type = conn.connection_type,
                .weight = conn.weight,
            });
        }
        try copy.connections.put(allocator, group_name, new_group);
    }
    
    // Copy metadata
    allocator.free(copy.updated);
    copy.updated = try allocator.dupe(u8, source.updated);
    
    allocator.free(copy.language);
    copy.language = try allocator.dupe(u8, source.language);
    
    // Context copying (simplified for now, assumes source.context is handled or we implement full deep copy)
    // For now, let's just do basic context copying if needed. 
    // Since this is a library, a full deep copy is safer.
    // TODO: Implement full context deep copy. For now, rely on default init (none) or shallow if safe?
    // No, shallow copy of strings in union is dangerous. 
    // Providing a minimal deep copy for essential fields.
    
    return copy;
}

// --- Filter Logic ---

fn matchesFilters(neurona: *const Neurona, filters: []const QueryFilter) bool {
    if (filters.len == 0) return true;
    for (filters) |filter| {
        if (!matchesFilter(neurona, filter)) return false;
    }
    return true;
}

fn matchesFilter(neurona: *const Neurona, filter: QueryFilter) bool {
    return switch (filter) {
        .type_filter => |tf| matchesTypeFilter(neurona, tf),
        .tag_filter => |tf| matchesTagFilter(neurona, tf),
        .connection_filter => |cf| matchesConnectionFilter(neurona, cf),
        .field_filter => |ff| matchesFieldFilter(neurona, ff),
    };
}

fn matchesTypeFilter(neurona: *const Neurona, filter: TypeFilter) bool {
    const type_str = @tagName(neurona.type);
    for (filter.types) |t| {
        if (std.mem.eql(u8, type_str, t)) return filter.include;
    }
    return !filter.include;
}

fn matchesTagFilter(neurona: *const Neurona, filter: TagFilter) bool {
    for (filter.tags) |tag| {
        for (neurona.tags.items) |nt| {
            if (std.mem.eql(u8, nt, tag)) return filter.include;
        }
    }
    return !filter.include;
}

fn matchesConnectionFilter(neurona: *const Neurona, filter: ConnectionFilter) bool {
    var conn_it = neurona.connections.iterator();
    var has_match = false;
    
    while (conn_it.next()) |entry| {
        for (entry.value_ptr.connections.items) |*conn| {
            var match = false;
            if (filter.connection_type) |ct| {
                if (std.mem.eql(u8, @tagName(conn.connection_type), ct)) match = true;
            } else if (filter.target_id) |tid| {
                if (std.mem.eql(u8, conn.target_id, tid)) match = true;
            }
            
            // Refine match logic: if both set, both must match? 
            // Simplified from CLI logic:
            if (filter.connection_type != null and filter.target_id != null) {
                 if (std.mem.eql(u8, @tagName(conn.connection_type), filter.connection_type.?) and
                     std.mem.eql(u8, conn.target_id, filter.target_id.?)) 
                 {
                     match = true;
                 } else {
                     match = false;
                 }
            }

            if (match) {
                if (filter.operator == .not) return false;
                has_match = true;
                if (filter.operator == .@"and") break; 
            }
        }
    }
    
    return switch (filter.operator) {
        .@"or" => has_match,
        .@"and" => has_match,
        .not => !has_match,
    };
}

fn matchesFieldFilter(neurona: *const Neurona, filter: FieldFilter) bool {
    const val = filter.value orelse return false;
    if (std.mem.eql(u8, filter.field, "id")) return std.mem.eql(u8, neurona.id, val);
    if (std.mem.eql(u8, filter.field, "title")) return std.mem.indexOf(u8, neurona.title, val) != null;
    return false;
}

// --- Search Modes ---

fn executeBM25Query(allocator: Allocator, config: QueryConfig, neuronas: []const Neurona) !QueryResult {
    var bm25 = BM25Index.init();
    defer bm25.deinit(allocator);

    for (neuronas) |*n| {
        var content = std.ArrayList(u8).init(allocator);
        defer content.deinit();
        try content.appendSlice(n.title);
        for (n.tags.items) |t| {
            try content.appendSlice(" ");
            try content.appendSlice(t);
        }
        try bm25.addDocument(allocator, n.id, content.items);
    }
    bm25.build();

    const limit = config.limit orelse 50;
    const results = try bm25.search(allocator, config.query_text, limit);
    defer allocator.free(results); // bm25 results are typically just structs, but check storage/tfidf.zig

    var fused = std.ArrayList(FusedResult).init(allocator);
    for (results) |r| {
        try fused.append(.{
            .id = try allocator.dupe(u8, r.doc_id),
            .score = r.score,
        });
        // r.deinit(allocator) if needed? BM25Result typically doesn't own strings if they reference index, 
        // but here we rebuild index every time so strings might be invalid if we don't copy.
        // Checking tfidf.zig: SearchResult has doc_id []const u8.
    }
    
    return QueryResult{ .scored = try fused.toOwnedSlice() };
}

fn executeVectorQuery(allocator: Allocator, config: QueryConfig, neuronas: []const Neurona) !QueryResult {
    // Simplified: Requires persistent vector store or building on fly (expensive)
    // For library usage, we likely want to load from .activations/vectors.bin if available
    // For now, let's assume on-the-fly build using simple embeddings if glove not available
    // or return empty if no index.
    
    // To properly support this in library, we need the IndexEngine to load/provide the VectorIndex.
    // For this standalone function, we will try to load.
    
    const index_path = try std.fs.path.join(allocator, &.{ config.neuronas_dir, "../.activations/vectors.bin" });
    defer allocator.free(index_path);

    var vector_index: VectorIndex = undefined;
    var loaded = false;

    if (VectorIndex.load(allocator, index_path)) |loaded_idx| {
        vector_index = loaded_idx.index;
        loaded = true;
    } else |_| {
        // Fallback: build simple
        vector_index = VectorIndex.init(allocator, 100); 
        for (neuronas) |*n| {
             const vec = try createSimpleEmbedding(allocator, n, 100);
             defer allocator.free(vec);
             try vector_index.addVector(allocator, n.id, vec);
        }
    }
    defer vector_index.deinit(allocator);

    const query_vec = try createQueryEmbedding(allocator, config.query_text, vector_index.dimension);
    defer allocator.free(query_vec);

    const limit = config.limit orelse 50;
    const results = try vector_index.search(allocator, query_vec, limit);
    defer allocator.free(results);

    var fused = std.ArrayList(FusedResult).init(allocator);
    for (results) |r| {
        try fused.append(.{
            .id = try allocator.dupe(u8, r.doc_id),
            .score = r.score,
        });
    }

    return QueryResult{ .scored = try fused.toOwnedSlice() };
}

fn executeHybridQuery(allocator: Allocator, config: QueryConfig, neuronas: []const Neurona) !QueryResult {
    // 1. BM25
    var bm25 = BM25Index.init();
    defer bm25.deinit(allocator);
    for (neuronas) |*n| {
        var content = std.ArrayList(u8).init(allocator);
        defer content.deinit();
        try content.appendSlice(n.title);
        try bm25.addDocument(allocator, n.id, content.items);
    }
    bm25.build();
    const bm25_results = try bm25.search(allocator, config.query_text, config.limit orelse 50);
    defer allocator.free(bm25_results);

    // 2. Vector
    var vector_index = VectorIndex.init(allocator, 100);
    defer vector_index.deinit(allocator);
    for (neuronas) |*n| {
        const vec = try createSimpleEmbedding(allocator, n, 100);
        defer allocator.free(vec);
        try vector_index.addVector(allocator, n.id, vec);
    }
    const query_vec = try createQueryEmbedding(allocator, config.query_text, 100);
    defer allocator.free(query_vec);
    const vec_results = try vector_index.search(allocator, query_vec, config.limit orelse 50);
    defer allocator.free(vec_results);

    // 3. Fusion
    var scores = std.StringHashMap(f32).init(allocator);
    defer {
        var it = scores.iterator();
        while (it.next()) |kv| allocator.free(kv.key_ptr.*);
        scores.deinit();
    }

    for (bm25_results) |r| {
        try scores.put(try allocator.dupe(u8, r.doc_id), r.score * 0.6);
    }
    for (vec_results) |r| {
        const g = try scores.getOrPut(r.doc_id);
        if (!g.found_existing) {
             g.key_ptr.* = try allocator.dupe(u8, r.doc_id);
             g.value_ptr.* = 0;
        }
        g.value_ptr.* += r.score * 0.4;
    }

    var fused = std.ArrayList(FusedResult).init(allocator);
    var it = scores.iterator();
    while (it.next()) |entry| {
        try fused.append(.{
            .id = try allocator.dupe(u8, entry.key_ptr.*),
            .score = entry.value_ptr.*,
        });
    }
    
    // Sort
    std.sort.insertion(FusedResult, fused.items, {}, struct {
        fn lessThan(_: void, a: FusedResult, b: FusedResult) bool {
            return a.score > b.score;
        }
    }.lessThan);

    return QueryResult{ .scored = try fused.toOwnedSlice() };
}

fn executeActivationQuery(allocator: Allocator, config: QueryConfig, neuronas: []const Neurona) !QueryResult {
    // Build Graph
    var graph = Graph.init();
    defer graph.deinit(allocator);
    for (neuronas) |*n| {
        var it = n.connections.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.connections.items) |c| {
                try graph.addEdge(allocator, n.id, c.target_id, c.weight);
            }
        }
    }

    // Build Indices
    var bm25 = BM25Index.init();
    defer bm25.deinit(allocator);
    for (neuronas) |*n| try bm25.addDocument(allocator, n.id, n.title);
    bm25.build();

    var vec_idx = VectorIndex.init(allocator, 100);
    defer vec_idx.deinit(allocator);
    for (neuronas) |*n| {
        const v = try createSimpleEmbedding(allocator, n, 100);
        defer allocator.free(v);
        try vec_idx.addVector(allocator, n.id, v);
    }

    // Activate
    var activation = NeuralActivation.init(&graph, &bm25, &vec_idx);
    const results = try activation.activate(allocator, config.query_text, null);
    
    // Results are already allocated/duped in activate()
    return QueryResult{ .activation = results };
}

// Simple embedding helper (fallback)
fn createSimpleEmbedding(allocator: Allocator, neurona: *const Neurona, dim: usize) ![]f32 {
    const vec = try allocator.alloc(f32, dim);
    @memset(vec, 0);
    // Naive hash-based
    var it = std.mem.splitScalar(u8, neurona.title, ' ');
    while (it.next()) |word| {
        const hash = std.hash.Wyhash.hash(0, word) % dim;
        vec[hash] += 1.0;
    }
    return vec;
}

fn createQueryEmbedding(allocator: Allocator, text: []const u8, dim: usize) ![]f32 {
    const vec = try allocator.alloc(f32, dim);
    @memset(vec, 0);
    var it = std.mem.splitScalar(u8, text, ' ');
    while (it.next()) |word| {
        const hash = std.hash.Wyhash.hash(0, word) % dim;
        vec[hash] += 1.0;
    }
    return vec;
}
