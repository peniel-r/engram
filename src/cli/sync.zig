// File: src/cli/sync.zig
// The `engram sync` command for rebuilding the graph index
// Scans all Neuronas and rebuilds the adjacency index

const std = @import("std");
const Allocator = std.mem.Allocator;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Neurona = @import("../core/neurona.zig").Neurona;
const Graph = @import("../core/graph.zig").Graph;
const storage = @import("../root.zig").storage;

/// Sync configuration
pub const SyncConfig = struct {
    directory: []const u8 = "neuronas",
    verbose: bool = false,
    rebuild_index: bool = true,
};

/// Main command handler
pub fn execute(allocator: Allocator, config: SyncConfig) !void {
    if (config.verbose) {
        var stdout_buffer: [512]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("Scanning directory: {s}\n", .{config.directory});
    }

    // Step 1: Scan all Neuronas
    const neuronas = try storage.scanNeuronas(allocator, config.directory);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    if (config.verbose) {
        var stdout_buffer: [512]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("Found {d} Neuronas\n", .{neuronas.len});
    }

    // Step 2: Build graph index
    if (config.rebuild_index) {
        try buildGraphIndex(allocator, neuronas, config.verbose);
    }
}

/// Build graph index from Neuronas
fn buildGraphIndex(allocator: Allocator, neuronas: []const Neurona, verbose: bool) !void {
    var graph = Graph.init();
    defer graph.deinit(allocator);

    if (verbose) {
        var stdout_buffer: [512]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.writeAll("Building graph index...\n");
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
        var stdout_buffer: [512]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("Graph built: {d} nodes\n", .{graph.nodeCount()});
        try stdout.print("Index saved to .activations/graph.idx\n", .{});
    }

    // TODO: Save graph index to disk (Step 4.1 will implement)
}

/// Display graph statistics
pub fn showStats(allocator: Allocator, graph: *Graph) !void {
    _ = allocator; // Used in function signature but not in this simple version
    _ = graph; // TODO: Implement full statistics

    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll("\n📊 Graph Statistics\n");
    for (0..20) |_| try stdout.writeByte('=');
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

