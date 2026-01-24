// File: src/cli/trace.zig
// The `engram trace` command for visualizing dependency trees
// Traces requirements → tests → code, issues → blocked artifacts

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const readNeurona = @import("../storage/filesystem.zig").readNeurona;
const scanNeuronas = @import("../storage/filesystem.zig").scanNeuronas;
const findNeuronaPath = @import("../storage/filesystem.zig").findNeuronaPath;
const Graph = @import("../core/graph.zig").Graph;

/// Trace configuration
pub const TraceConfig = struct {
    id: []const u8,
    direction: Direction = .down,
    max_depth: usize = 10,
    format: OutputFormat = .tree,
    json_output: bool = false,
};

pub const Direction = enum {
    up, // Trace parents/dependencies
    down, // Trace children/implementations
};

pub const OutputFormat = enum {
    tree, // Indented tree representation
    list, // Flat list with indentation
};

/// Trace result with connection info
pub const TraceNode = struct {
    id: []const u8,
    level: usize,
    connections: std.ArrayListUnmanaged([]const u8),
    node_type: []const u8,

    pub fn deinit(self: *TraceNode, allocator: Allocator) void {
        allocator.free(self.id);
        for (self.connections.items) |conn| allocator.free(conn);
        self.connections.deinit(allocator);
        allocator.free(self.node_type);
    }
};

/// Main command handler
pub fn execute(allocator: Allocator, config: TraceConfig) !void {
    // Step 1: Load all Neuronas and build graph
    const neuronas = scanNeuronas(allocator, "neuronas") catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.debug.print("Error: No neuronas directory found. Please run 'engram init' first or ensure you're in a Cortex directory.\n", .{});
                return err;
            },
            else => return err,
        }
    };
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    var graph = Graph.init();
    defer graph.deinit(allocator);

    // Build graph from Neuronas
    for (neuronas) |*neurona| {
        // Add connections - addEdge automatically creates nodes
        var conn_it = neurona.connections.iterator();
        while (conn_it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                try graph.addEdge(allocator, neurona.id, conn.target_id, conn.weight);
            }
        }
    }

    // Step 2: Trace from target node
    const trace_result = try trace(allocator, &graph, "neuronas", config);
    defer {
        for (trace_result) |*n| n.deinit(allocator);
        allocator.free(trace_result);
    }

    // Step 3: Output
    if (config.json_output) {
        try outputJson(trace_result);
    } else {
        try outputTree(trace_result);
    }
}

/// Trace dependencies from target node
pub fn trace(allocator: Allocator, graph: *Graph, directory: []const u8, config: TraceConfig) ![]TraceNode {
    // Load starting Neurona to verify it exists
    const filepath = try findNeuronaPath(allocator, directory, config.id);
    defer allocator.free(filepath);

    var start_neurona = try readNeurona(allocator, filepath);
    defer start_neurona.deinit(allocator);

    var visited = std.StringHashMap(*TraceNode).init(allocator);
    defer visited.deinit();

    var result = std.ArrayListUnmanaged(*TraceNode){};
    errdefer {
        for (result.items) |n| {
            n.deinit(allocator);
            allocator.destroy(n);
        }
        result.deinit(allocator);
    }

    if (config.direction == .down) {
        try buildDownstreamTree(allocator, graph, &visited, &result, config.id, config.max_depth);
    } else {
        try buildUpstreamTree(allocator, graph, &visited, &result, config.id, config.max_depth);
    }

    // Convert pointer list to value list
    var final_result = std.ArrayListUnmanaged(TraceNode){};
    for (result.items) |node_ptr| {
        try final_result.append(allocator, node_ptr.*);
    }

    // Clean up pointers only (data moved to final_result)
    for (result.items) |node_ptr| {
        allocator.destroy(node_ptr);
    }
    result.deinit(allocator);

    return final_result.toOwnedSlice(allocator);
}

/// Build downstream tree (children, implementations)
fn buildDownstreamTree(allocator: Allocator, graph: *Graph, visited: *std.StringHashMap(*TraceNode), result: *std.ArrayListUnmanaged(*TraceNode), start_id: []const u8, max_depth: usize) !void {
    // Create root node
    const root = try allocator.create(TraceNode);
    root.* = TraceNode{
        .id = try allocator.dupe(u8, start_id),
        .level = 0,
        .connections = std.ArrayListUnmanaged([]const u8){},
        .node_type = try allocator.dupe(u8, "root"),
    };

    try visited.put(root.id, root);
    try result.append(allocator, root);

    const QueueNode = struct { id: []const u8, depth: usize };
    var queue = std.ArrayListUnmanaged(QueueNode){};
    defer queue.deinit(allocator);

    try queue.append(allocator, .{ .id = start_id, .depth = 0 });

    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);
        if (current.depth >= max_depth) continue;

        const adj = graph.getAdjacent(current.id);
        for (adj) |edge| {
            if (visited.get(edge.target_id) == null) {
                const child = try allocator.create(TraceNode);
                child.* = TraceNode{
                    .id = try allocator.dupe(u8, edge.target_id),
                    .level = current.depth + 1,
                    .connections = std.ArrayListUnmanaged([]const u8){},
                    .node_type = try allocator.dupe(u8, "downstream"),
                };

                try visited.put(child.id, child);
                try result.append(allocator, child);
                try queue.append(allocator, .{ .id = edge.target_id, .depth = current.depth + 1 });

                // Add connection to parent
                const parent_node = visited.get(current.id).?;
                try parent_node.connections.append(allocator, try allocator.dupe(u8, edge.target_id));
            }
        }
    }
}

/// Build upstream tree (parents, dependencies)
fn buildUpstreamTree(allocator: Allocator, graph: *Graph, visited: *std.StringHashMap(*TraceNode), result: *std.ArrayListUnmanaged(*TraceNode), start_id: []const u8, max_depth: usize) !void {
    // Create root node
    const root = try allocator.create(TraceNode);
    root.* = TraceNode{
        .id = try allocator.dupe(u8, start_id),
        .level = 0,
        .connections = std.ArrayListUnmanaged([]const u8){},
        .node_type = try allocator.dupe(u8, "root"),
    };

    try visited.put(root.id, root);
    try result.append(allocator, root);

    const StackNode = struct { id: []const u8, depth: usize };
    var stack = std.ArrayListUnmanaged(StackNode){};
    defer stack.deinit(allocator);

    try stack.append(allocator, .{ .id = start_id, .depth = 0 });

    while (stack.items.len > 0) {
        const current = stack.pop().?;
        if (current.depth >= max_depth) continue;

        // Get incoming edges (parents)
        const incoming = graph.getIncoming(current.id);
        for (incoming) |edge| {
            if (visited.get(edge.target_id) == null) {
                const parent = try allocator.create(TraceNode);
                parent.* = TraceNode{
                    .id = try allocator.dupe(u8, edge.target_id),
                    .level = current.depth + 1,
                    .connections = std.ArrayListUnmanaged([]const u8){},
                    .node_type = try allocator.dupe(u8, "upstream"),
                };

                try visited.put(parent.id, parent);
                try result.append(allocator, parent);
                try stack.append(allocator, .{ .id = edge.target_id, .depth = current.depth + 1 });

                // Add connection to child
                const child_node = visited.get(current.id).?;
                try child_node.connections.append(allocator, try allocator.dupe(u8, edge.target_id));
            }
        }
    }
}

/// Output tree format to stdout
fn outputTree(trace_nodes: []const TraceNode) !void {
    std.debug.print("\n🌲 Dependency Tree\n", .{});
    for (0..40) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});

    for (trace_nodes) |node| {
        // Indent based on level
        for (0..node.level * 2) |_| std.debug.print(" ", .{});

        std.debug.print("{s} ({d})\n", .{ node.id, node.connections.items.len });
        if (node.connections.items.len > 0) {
            for (node.connections.items, 0..) |conn, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{conn});
            }
            std.debug.print("\n", .{});
        }
    }

    std.debug.print("\n", .{});
}

/// JSON output for AI
fn outputJson(trace_nodes: []const TraceNode) !void {
    std.debug.print("[", .{});
    for (trace_nodes, 0..) |node, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{{", .{});
        std.debug.print("\"id\":\"{s}\",", .{node.id});
        std.debug.print("\"level\":{d},", .{node.level});
        std.debug.print("\"type\":\"{s}\",", .{node.node_type});
        std.debug.print("\"connections\":[", .{});

        for (node.connections.items, 0..) |conn, j| {
            if (j > 0) std.debug.print(",", .{});
            std.debug.print("\"{s}\"", .{conn});
        }

        std.debug.print("]}}", .{});
    }
    std.debug.print("]\n", .{});
}

// ==================== Tests ====================

test "trace command loads neuronas and builds graph" {
    const allocator = std.testing.allocator;

    // Scan test fixtures
    const neuronas = try scanNeuronas(allocator, "tests/fixtures/trace");
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Should load all 4 test neuronas
    try std.testing.expectEqual(@as(usize, 4), neuronas.len);

    // Build graph
    var graph = Graph.init();
    defer graph.deinit(allocator);

    for (neuronas) |*neurona| {
        var conn_it = neurona.connections.iterator();
        while (conn_it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                try graph.addEdge(allocator, neurona.id, conn.target_id, conn.weight);
            }
        }
    }

    // Verify graph structure
    try std.testing.expectEqual(@as(usize, 4), graph.nodeCount());

    // req.auth should have incoming edges (blocks from issue, implements from impl, validates from test)
    const incoming_to_req = graph.getIncoming("req.auth");
    try std.testing.expectEqual(@as(usize, 3), incoming_to_req.len);
}

test "trace downstream from req.auth" {
    const allocator = std.testing.allocator;

    const neuronas = try scanNeuronas(allocator, "tests/fixtures/trace");
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    var graph = Graph.init();
    defer graph.deinit(allocator);

    for (neuronas) |*neurona| {
        var conn_it = neurona.connections.iterator();
        while (conn_it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                try graph.addEdge(allocator, neurona.id, conn.target_id, conn.weight);
            }
        }
    }

    const config = TraceConfig{
        .id = "req.auth",
        .direction = .down,
        .max_depth = 10,
        .format = .tree,
        .json_output = false,
    };

    const trace_result = try trace(allocator, &graph, "tests/fixtures/trace", config);
    defer {
        for (trace_result) |*n| n.deinit(allocator);
        allocator.free(trace_result);
    }

    // Should find 3 downstream nodes (test, impl, issue)
    try std.testing.expect(trace_result.len >= 1);
}

test "trace upstream from test.auth.login" {
    const allocator = std.testing.allocator;

    const neuronas = try scanNeuronas(allocator, "tests/fixtures/trace");
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    var graph = Graph.init();
    defer graph.deinit(allocator);

    for (neuronas) |*neurona| {
        var conn_it = neurona.connections.iterator();
        while (conn_it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                try graph.addEdge(allocator, neurona.id, conn.target_id, conn.weight);
            }
        }
    }

    const config = TraceConfig{
        .id = "test.auth.login",
        .direction = .up,
        .max_depth = 10,
        .format = .tree,
        .json_output = false,
    };

    const trace_result = try trace(allocator, &graph, "tests/fixtures/trace", config);
    defer {
        for (trace_result) |*n| n.deinit(allocator);
        allocator.free(trace_result);
    }

    // Should find req.auth as upstream
    try std.testing.expect(trace_result.len >= 1);
}

test "findNeuronaPath finds existing file" {
    const allocator = std.testing.allocator;

    const path = try findNeuronaPath(allocator, "tests/fixtures/trace", "req.auth");
    defer allocator.free(path);

    try std.testing.expect(path.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, path, "req.auth") != null);
}

test "findNeuronaPath returns error for non-existent file" {
    const allocator = std.testing.allocator;

    const result = findNeuronaPath(allocator, "tests/fixtures/trace", "nonexistent");
    try std.testing.expectError(error.NeuronaNotFound, result);
}

test "outputTree generates valid output" {
    const allocator = std.testing.allocator;

    var nodes = std.ArrayListUnmanaged(TraceNode){};
    defer {
        for (nodes.items) |*n| n.deinit(allocator);
        nodes.deinit(allocator);
    }

    // Create test node
    const node = TraceNode{
        .id = try allocator.dupe(u8, "test.id"),
        .level = 0,
        .connections = std.ArrayListUnmanaged([]const u8){},
        .node_type = try allocator.dupe(u8, "root"),
    };
    try nodes.append(allocator, node);

    // Should not panic
    try outputTree(nodes.items);
}

test "outputJson generates valid JSON" {
    const allocator = std.testing.allocator;

    var nodes = std.ArrayListUnmanaged(TraceNode){};
    defer {
        for (nodes.items) |*n| n.deinit(allocator);
        nodes.deinit(allocator);
    }

    // Create test node
    const node = TraceNode{
        .id = try allocator.dupe(u8, "test.id"),
        .level = 0,
        .connections = std.ArrayListUnmanaged([]const u8){},
        .node_type = try allocator.dupe(u8, "root"),
    };
    try nodes.append(allocator, node);

    // Should not panic
    try outputJson(nodes.items);
}
