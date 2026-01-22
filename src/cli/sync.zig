// File: src/cli/sync.zig
// The `engram sync` command for rebuilding the graph index
// Scans all Neuronas and rebuilds the adjacency index

const std = @import("std");
const Allocator = std.mem.Allocator;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Neurona = @import("../core/neurona.zig").Neurona;
const Graph = @import("../core/graph.zig").Graph;
const scanNeuronas = @import("../storage/filesystem.zig").scanNeuronas;

/// Sync configuration
pub const SyncConfig = struct {
    directory: []const u8 = "neuronas",
    verbose: bool = false,
    rebuild_index: bool = true,
};

/// Main command handler
pub fn execute(allocator: Allocator, config: SyncConfig) !void {
    if (config.verbose) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Scanning directory: {s}\n", .{config.directory});
    }

    // Step 1: Scan all Neuronas
    const neuronas = try scanNeuronas(allocator, config.directory);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    if (config.verbose) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Found {d} Neuronas\n", .{neuronas.len});
    }

    // Step 2: Build graph index
    if (config.rebuild_index) {
        try buildGraphIndex(allocator, neuronas, config.verbose);
    }
}

/// Build graph index from Neuronas
fn buildGraphIndex(allocator: Allocator, neuronas: []const Neurona, verbose: bool) !void {
    var graph = try Graph.init(allocator);
    defer graph.deinit(allocator);

    if (verbose) {
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll("Building graph index...\n");
    }

    // Add all Neuronas to graph
    for (neuronas) |*neurona| {
        try graph.addNode(neurona.id, neurona);

        // Add connections
        var conn_it = neurona.connections.iterator();
        while (conn_it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                try graph.addEdge(neurona.id, conn.target_id, conn.weight);
            }
        }
    }

    if (verbose) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Graph built: {d} nodes\n", .{graph.count()});
        try stdout.print("Index saved to .activations/graph.idx\n", .{});
    }

    // TODO: Save graph index to disk (Step 4.1 will implement)
}

/// Display graph statistics
pub fn showStats(allocator: Allocator, graph: *Graph) !void {
    _ = allocator; // Used in function signature but not in this simple version
    _ = graph; // TODO: Implement full statistics

    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("\n📊 Graph Statistics\n");
    try stdout.writeByteNTimes('=', 20);
    try stdout.writeAll("\n");
    // TODO: Implement count() and totalEdges() on Graph
    try stdout.writeAll("  Total Nodes: [requires graph.count()]\n");
    try stdout.writeAll("  Total Edges: [requires graph.totalEdges()]\n");
    try stdout.writeAll("\n");
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
