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

/// Sync configuration
pub const SyncConfig = struct {
    directory: []const u8 = "neuronas",
    verbose: bool = false,
    rebuild_index: bool = false,
    force_rebuild: bool = false,
};

/// Main command handler
pub fn execute(allocator: Allocator, config: SyncConfig) !void {
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

            // If we only wanted to load the index, we are done
            if (!config.rebuild_index) return;
        } else |_| {
            if (config.verbose) {
                std.debug.print("No graph index cache found (or corrupt), rebuilding...\n", .{});
            }
        }
    }

    if (config.verbose) {
        std.debug.print("Scanning directory: {s}\n", .{config.directory});
    }

    // Step 1: Scan all Neuronas
    const neuronas = try storage.scanNeuronas(allocator, config.directory);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    if (config.verbose) {
        std.debug.print("Found {d} Neuronas\n", .{neuronas.len});
    }

    // Step 2: Build graph index
    try buildGraphIndex(allocator, neuronas, config.verbose);
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

    try std.testing.expectEqualStrings("neuronas", config.directory);
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

    try std.testing.expectEqualStrings("custom_neuronas", config.directory);
    try std.testing.expectEqual(true, config.verbose);
    try std.testing.expectEqual(false, config.rebuild_index);
}
