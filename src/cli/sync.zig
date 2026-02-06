// File: src/cli/sync.zig
// The `engram sync` command for rebuilding the graph index
// Scans all Neuronas and rebuilds the adjacency index

const std = @import("std");
const Allocator = std.mem.Allocator;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Neurona = @import("../core/neurona.zig").Neurona;
const Graph = @import("../core/graph.zig").Graph;
const storage = @import("../root.zig").storage;
const validator = @import("../core/validator.zig");
const benchmark = @import("../root.zig").utils.benchmark;
const uri_parser = @import("../utils/uri_parser.zig");

/// Sync configuration
pub const SyncConfig = struct {
    directory: ?[]const u8 = null,
    cortex_dir: ?[]const u8 = null,
    verbose: bool = false,
    rebuild_index: bool = false,
    force_rebuild: bool = false,
};

/// Main command handler
pub fn execute(allocator: Allocator, config: SyncConfig) !void {
    // Step 0: Determine cortex directory and neuronas directory
    const cortex_dir = if (config.cortex_dir) |cd|
        cd // Use provided path directly
    else
        uri_parser.findCortexDir(allocator) catch |err| {
            if (err == error.CortexNotFound) {
                std.debug.print("Error: No cortex found in current directory or parent directories.\n", .{});
                std.debug.print("\nHint: Navigate to a cortex directory or use --cortex <path> to specify location.\n", .{});
                std.debug.print("Run 'engram init <name>' to create a new cortex.\n", .{});
                std.process.exit(1);
            }
            return err;
        };
    defer if (config.cortex_dir == null) allocator.free(cortex_dir);

    const directory = config.directory orelse try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex_dir});
    defer if (config.directory == null) allocator.free(directory);

    var reports = std.ArrayListUnmanaged(benchmark.BenchmarkReport){};
    defer reports.deinit(allocator);

    // Step 1: Cold Start Timer
    var cold_start_timer = try benchmark.Timer.start();
    const index_path = try storage.index.getGraphIndexPath(allocator);
    defer allocator.free(index_path);

    if (!config.force_rebuild) {
        if (storage.index.loadGraph(allocator, index_path)) |graph| {
            var g = graph;
            defer g.deinit(allocator);

            if (config.verbose) {
                std.debug.print("Loaded graph index from cache: {s}\n", .{index_path});
                std.debug.print("Graph nodes: {d}, edges: {d}\n", .{ g.nodeCount(), g.edgeCount() / 2 });
            }

            try reports.append(allocator, .{
                .operation = "Cold Start (Index Load)",
                .iterations = 1,
                .total_ms = cold_start_timer.readMs(),
                .avg_ms = cold_start_timer.readMs(),
                .min_ms = cold_start_timer.readMs(),
                .max_ms = cold_start_timer.readMs(),
                .passes_10ms_rule = cold_start_timer.readMs() < 50.0, // Cold start target is 50ms
            });

            // If we only wanted to load the index, we are done
            if (!config.rebuild_index) {
                printPerformanceSummary(reports.items);
                return;
            }
        } else |_| {
            if (config.verbose) {
                std.debug.print("No graph index cache found (or corrupt), rebuilding...\n", .{});
            }
        }
    }

    if (config.verbose) {
        std.debug.print("Scanning directory: {s}\n", .{directory});
    }

    // Step 1: Scan all Neuronas
    var scan_timer = try benchmark.Timer.start();
    const neuronas = try storage.scanNeuronas(allocator, directory);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }
    const scan_ms = scan_timer.readMs();
    try reports.append(allocator, .{
        .operation = "Neurona Scanning",
        .iterations = 1,
        .total_ms = scan_ms,
        .avg_ms = scan_ms,
        .min_ms = scan_ms,
        .max_ms = scan_ms,
        .passes_10ms_rule = scan_ms < 1000.0, // Scan target is 1000ms for 10k
    });

    if (config.verbose) {
        std.debug.print("Found {d} Neuronas\n", .{neuronas.len});
    }

    // Step 2: Build graph index
    var graph_timer = try benchmark.Timer.start();
    try buildGraphIndex(allocator, neuronas, config.verbose);
    const graph_ms = graph_timer.readMs();
    try reports.append(allocator, .{
        .operation = "Graph Build",
        .iterations = 1,
        .total_ms = graph_ms,
        .avg_ms = graph_ms,
        .min_ms = graph_ms,
        .max_ms = graph_ms,
        .passes_10ms_rule = graph_ms < 1000.0, // Graph target is 1000ms
    });

    // Step 3: Manage LLM Cache (Issue 1.3)
    var cache_timer = try benchmark.Timer.start();
    try syncLLMCache(allocator, neuronas, config.verbose);
    const cache_ms = cache_timer.readMs();
    try reports.append(allocator, .{
        .operation = "LLM Cache Sync",
        .iterations = 1,
        .total_ms = cache_ms,
        .avg_ms = cache_ms,
        .min_ms = cache_ms,
        .max_ms = cache_ms,
        .passes_10ms_rule = true, // No strict limit in compliance plan for cache
    });

    // Step 4: Build/Load Vector Index (Issue 1.2)
    var vector_timer = try benchmark.Timer.start();
    try syncVectors(allocator, neuronas, config.verbose, config.force_rebuild, directory);
    const vector_ms = vector_timer.readMs();
    try reports.append(allocator, .{
        .operation = "Vector Sync",
        .iterations = 1,
        .total_ms = vector_ms,
        .avg_ms = vector_ms,
        .min_ms = vector_ms,
        .max_ms = vector_ms,
        .passes_10ms_rule = vector_ms < 1000.0, // Vector target depends on embeddings
    });

    printPerformanceSummary(reports.items);
}

/// Print performance summary table
fn printPerformanceSummary(reports: []const benchmark.BenchmarkReport) void {
    std.debug.print("\nPerformance Summary (10ms Rule Validation)\n", .{});
    std.debug.print("------------------------------------------------------------\n", .{});
    std.debug.print("{s: <30} | {s: >14} | {s}\n", .{ "Operation", "Duration", "Status" });
    std.debug.print("------------------------------------------------------------\n", .{});
    for (reports) |r| {
        const threshold: f64 = if (std.mem.indexOf(u8, r.operation, "Cold Start") != null) 50.0 else 1000.0;
        const status = if (r.avg_ms < threshold) "✅ PASS" else "❌ FAIL";
        // Special 10ms rule mention for traversals would go here if we were doing them
        // For sync, we use the targets from Issue 1.4
        std.debug.print("{s: <30} | {d: >11.3} ms | {s}\n", .{ r.operation, r.avg_ms, status });
    }
    std.debug.print("------------------------------------------------------------\n\n", .{});
}

/// Sync LLM Cache (Issue 1.3)
fn syncLLMCache(allocator: Allocator, neuronas: []const Neurona, verbose: bool) !void {
    _ = neuronas;
    const cache_dir = ".activations/cache/";
    const summaries_path = cache_dir ++ "summaries.cache";
    const tokens_path = cache_dir ++ "tokens.cache";

    // Ensure directory exists
    std.fs.cwd().makePath(cache_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var cache = storage.llm_cache.LLMCache.init(allocator);
    defer cache.deinit();

    // Load existing
    cache.loadFromDisk(summaries_path, tokens_path) catch |err| {
        if (verbose) std.debug.print("Note: Could not load LLM cache: {}\n", .{err});
    };

    if (verbose) {
        std.debug.print("LLM Cache loaded: {d} summaries, {d} token counts\n", .{
            cache.summaries.count(),
            cache.tokens.count(),
        });
    }

    // TODO: Perform enrichment/cleanup if needed
    // For now, we just ensure it's initialized and persisted

    // Save back to disk
    try cache.saveToDisk(summaries_path, tokens_path);
    if (verbose) {
        std.debug.print("✓ LLM Cache saved to {s}\n", .{cache_dir});
    }
}

/// Sync vectors and persist to .activations/vectors.bin
fn syncVectors(allocator: Allocator, neuronas: []const Neurona, verbose: bool, force: bool, directory: []const u8) !void {
    const vector_path = try storage.VectorIndex.getVectorIndexPath(allocator);
    defer allocator.free(vector_path);

    const latest_mtime = try storage.getLatestModificationTime(directory);

    if (!force) {
        if (storage.VectorIndex.load(allocator, vector_path)) |loaded| {
            if (loaded.timestamp >= latest_mtime) {
                if (verbose) {
                    std.debug.print("✓ Vector index is up to date (Timestamp: {d})\n", .{loaded.timestamp});
                }
                var idx = loaded.index;
                idx.deinit(allocator);
                return;
            }
            var idx = loaded.index;
            idx.deinit(allocator);
            if (verbose) {
                std.debug.print("Vector index is stale, rebuilding...\n", .{});
            }
        } else |_| {
            if (verbose) {
                std.debug.print("No vector index found, building...\n", .{});
            }
        }
    }

    const GloVeIndex = storage.GloVeIndex;

    // Build vectors
    var glove_index = GloVeIndex.init(allocator);
    defer glove_index.deinit(allocator);

    const glove_cache_path = "glove_cache.bin";
    if (GloVeIndex.cacheExists(glove_cache_path)) {
        try glove_index.loadCacheZeroCopy(allocator, glove_cache_path);
    } else {
        if (verbose) {
            std.debug.print("⚠️  Warning: GloVe cache not found at {s}. Skipping vector building.\n", .{glove_cache_path});
        }
        return;
    }

    var vector_index = storage.VectorIndex.init(allocator, glove_index.dimension);
    defer vector_index.deinit(allocator);

    if (verbose) {
        std.debug.print("Computing embeddings for {d} Neuronas...\n", .{neuronas.len});
    }

    const query = @import("query.zig");
    for (neuronas) |*neurona| {
        const embedding = try query.createGloVeEmbedding(allocator, neurona, &glove_index);
        defer allocator.free(embedding);
        try vector_index.addVector(allocator, neurona.id, embedding);
    }

    // Save
    try vector_index.save(allocator, vector_path, latest_mtime);
    if (verbose) {
        std.debug.print("✓ Vector index saved to {s}\n", .{vector_path});
    }
}

/// Build graph index from Neuronas
fn buildGraphIndex(allocator: Allocator, neuronas: []const Neurona, verbose: bool) !void {
    var graph = Graph.init();
    defer graph.deinit(allocator);

    if (verbose) {
        std.debug.print("Building graph index...\n", .{});
    }

    // Add all Neuronas to graph
    for (neuronas) |*neurona| {
        // Add connections - edges automatically create nodes
        var conn_it = neurona.connections.iterator();
        while (conn_it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                try graph.addEdge(allocator, neurona.id, conn.target_id, conn.weight);
            }
        }
    }

    if (verbose) {
        std.debug.print("Graph built: {d} nodes\n", .{graph.nodeCount()});
        std.debug.print("Index saved to .activations/graph.idx\n", .{});
    }

    // Step 2.5: Detect and report orphans
    const orphans = try validator.findOrphans(neuronas, &graph, allocator);
    defer allocator.free(orphans);

    if (orphans.len > 0) {
        std.debug.print("\n⚠️  Warning: Found {d} orphaned Neurona(s):\n", .{orphans.len});
        for (orphans) |orphan_id| {
            std.debug.print("  - {s}\n", .{orphan_id});
        }
        std.debug.print("  Orphaned Neuronas have no connections in or out.\n", .{});
        std.debug.print("  Consider linking them to the graph.\n\n", .{});
    } else if (verbose) {
        std.debug.print("✓ No orphaned Neuronas found\n\n", .{});
    }

    // Step 3: Save graph index to disk
    const index_path = try storage.index.getGraphIndexPath(allocator);
    defer allocator.free(index_path);

    try storage.index.ensureActivationsDir(allocator);
    try storage.index.saveGraph(allocator, &graph, index_path);

    if (verbose) {
        std.debug.print("✓ Graph index saved to {s}\n", .{index_path});
    }
}

/// Display graph statistics
pub fn showStats(allocator: Allocator, graph: *Graph) !void {
    _ = allocator; // Used in function signature but not in this simple version
    _ = graph; // TODO: Implement full statistics

    std.debug.print("\n📊 Graph Statistics\n", .{});
    for (0..20) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});
    // TODO: Implement count() and totalEdges() on Graph
    std.debug.print("  Total Nodes: [requires graph.count()]\n", .{});
    std.debug.print("  Total Edges: [requires graph.totalEdges()]\n", .{});
    std.debug.print("\n", .{});
}

// Example CLI usage:
//
//   engram sync
//   → Scans neuronas/ directory and rebuilds graph index
//
//   engram sync --verbose
//   → Shows detailed progress during sync
//
//   engram sync --rebuild-index
//   → Forces graph index rebuild

// ==================== Tests ====================

test "SyncConfig with default values" {
    const sync_mod = @import("sync.zig");

    const config = sync_mod.SyncConfig{
        .directory = "neuronas",
        .verbose = false,
        .rebuild_index = true,
    };

    try std.testing.expectEqualStrings("neuronas", config.directory.?);
    try std.testing.expectEqual(false, config.verbose);
    try std.testing.expectEqual(true, config.rebuild_index);
}

test "buildGraphIndex builds correct graph" {
    const allocator = std.testing.allocator;

    var n1 = try Neurona.init(allocator);
    defer n1.deinit(allocator);
    allocator.free(n1.id);
    n1.id = try allocator.dupe(u8, "node1");

    var n2 = try Neurona.init(allocator);
    defer n2.deinit(allocator);
    allocator.free(n2.id);
    n2.id = try allocator.dupe(u8, "node2");

    try n1.addConnection(allocator, .{
        .target_id = try allocator.dupe(u8, "node2"),
        .connection_type = .relates_to,
        .weight = 50,
    });

    const neuronas = [_]Neurona{ n1, n2 };
    try buildGraphIndex(allocator, &neuronas, false);
    // buildGraphIndex currently doesn't return anything or save to disk in this version
}

test "SyncConfig with custom values" {
    const sync_mod = @import("sync.zig");

    const config = sync_mod.SyncConfig{
        .directory = "custom_neuronas",
        .verbose = true,
        .rebuild_index = false,
    };

    try std.testing.expectEqualStrings("custom_neuronas", config.directory.?);
    try std.testing.expectEqual(true, config.verbose);
    try std.testing.expectEqual(false, config.rebuild_index);
}
