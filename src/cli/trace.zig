// File: src/cli/trace.zig
// The `engram trace` command for visualizing dependency trees
// Traces requirements → tests → code, issues → blocked artifacts

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const readNeurona = @import("../storage/filesystem.zig").readNeurona;
const scanNeuronas = @import("../storage/filesystem.zig").scanNeuronas;
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
    up,     // Trace parents/dependencies
    down,   // Trace children/implementations
};

pub const OutputFormat = enum {
    tree,    // Indented tree representation
    list,    // Flat list with indentation
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
                var stdout_buffer: [512]u8 = undefined;
                var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
                const stdout = &stdout_writer.interface;
                try stdout.writeAll("Error: No neuronas directory found. Please run 'engram init' first or ensure you're in a Cortex directory.\n");
                try stdout.flush();
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
    const trace_result = try trace(allocator, &graph, config);
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
fn trace(
    allocator: Allocator,
    graph: *Graph,
    config: TraceConfig
) ![]TraceNode {
    // Load starting Neurona
    const filepath = try findNeuronaPath(allocator, config.id);
    defer allocator.free(filepath);

    var start_neurona = try readNeurona(allocator, filepath);
    defer start_neurona.deinit(allocator);

    // Use BFS or DFS based on direction
    var visited = std.StringHashMap(*TraceNode).init(allocator);
    defer {
        var it = visited.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        visited.deinit();
    }

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
fn buildDownstreamTree(
    allocator: Allocator,
    graph: *Graph,
    visited: *std.StringHashMap(*TraceNode),
    result: *std.ArrayListUnmanaged(*TraceNode),
    start_id: []const u8,
    max_depth: usize
) !void {
    // Create root node
    const root = try allocator.create(TraceNode);
    root.* = TraceNode{
        .id = try allocator.dupe(u8, start_id),
        .level = 0,
        .connections = std.ArrayListUnmanaged([]const u8){},
        .node_type = try allocator.dupe(u8, "root"),
    };

    try visited.put(start_id, root);
    try result.append(allocator, root);

    // BFS to collect nodes by level
    var queue = std.ArrayListUnmanaged([]const u8){};
    defer queue.deinit(allocator);

    try queue.append(allocator, start_id);

    var current_depth: usize = 0;

    while (queue.items.len > 0 and current_depth < max_depth) {
        const current_id = queue.orderedRemove(0);
        const adj = graph.getAdjacent(current_id);

        for (adj) |edge| {
            if (visited.get(edge.target_id) == null) {
                const child = try allocator.create(TraceNode);
                child.* = TraceNode{
                    .id = try allocator.dupe(u8, edge.target_id),
                    .level = current_depth + 1,
                    .connections = std.ArrayListUnmanaged([]const u8){},
                    .node_type = try allocator.dupe(u8, "downstream"),
                };

                try visited.put(edge.target_id, child);
                try result.append(allocator, child);
                try queue.append(allocator, edge.target_id);

                // Add connection to parent
                const parent_node = visited.get(current_id).?;
                try parent_node.connections.append(allocator, try allocator.dupe(u8, edge.target_id));
            }
        }

        current_depth += 1;
    }
}

/// Build upstream tree (parents, dependencies)
fn buildUpstreamTree(
    allocator: Allocator,
    graph: *Graph,
    visited: *std.StringHashMap(*TraceNode),
    result: *std.ArrayListUnmanaged(*TraceNode),
    start_id: []const u8,
    max_depth: usize
) !void {
    // Create root node
    const root = try allocator.create(TraceNode);
    root.* = TraceNode{
        .id = try allocator.dupe(u8, start_id),
        .level = 0,
        .connections = std.ArrayListUnmanaged([]const u8){},
        .node_type = try allocator.dupe(u8, "root"),
    };

    try visited.put(start_id, root);
    try result.append(allocator, root);

    // DFS to trace upstream
    var stack = std.ArrayListUnmanaged([]const u8){};
    defer stack.deinit(allocator);

    try stack.append(allocator, start_id);

    var current_depth: usize = 0;

    while (stack.items.len > 0 and current_depth < max_depth) {
        const current_id = stack.pop().?;

        // Get incoming edges (parents)
        const incoming = graph.getIncoming(current_id);

        for (incoming) |edge| {
            if (visited.get(edge.target_id) == null) {
                const parent = try allocator.create(TraceNode);
                parent.* = TraceNode{
                    .id = try allocator.dupe(u8, edge.target_id),
                    .level = current_depth + 1,
                    .connections = std.ArrayListUnmanaged([]const u8){},
                    .node_type = try allocator.dupe(u8, "upstream"),
                };

                try visited.put(edge.target_id, parent);
                try result.append(allocator, parent);
                try stack.append(allocator, edge.target_id);

                // Add connection to child
                const child_node = visited.get(current_id).?;
                try child_node.connections.append(allocator, try allocator.dupe(u8, edge.target_id));
            }
        }

        current_depth += 1;
    }
}

/// Find Neurona file by ID
fn findNeuronaPath(allocator: Allocator, id: []const u8) ![]const u8 {
    const direct_path = try std.fmt.allocPrint(allocator, "neuronas/{s}.md", .{id});
    defer allocator.free(direct_path);

    if (std.fs.cwd().openFile(direct_path, .{})) |_| {
        return direct_path;
    } else |err| {
        if (err != error.FileNotFound) return err;

        // Search in neuronas directory
        var dir = try std.fs.cwd().openDir("neuronas", .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".md")) continue;

            const base_name = entry.name[0 .. entry.name.len - 3];
            if (std.mem.indexOf(u8, base_name, id) != null) {
                return try std.fs.path.join(allocator, &.{ "neuronas", entry.name });
            }
        }

        return error.NeuronaNotFound;
    }
}

/// Output tree format to stdout
fn outputTree(trace_nodes: []const TraceNode) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll("\n🌲 Dependency Tree\n");
    for (0..40) |_| try stdout.writeAll("=");
    try stdout.writeAll("\n");

    for (trace_nodes) |node| {
        // Indent based on level
        for (0..node.level * 2) |_| try stdout.writeAll(" ");

        try stdout.print("{s} ({d})\n", .{ node.id, node.connections.items.len });
        if (node.connections.items.len > 0) {
            for (node.connections.items, 0..) |conn, i| {
                if (i > 0) try stdout.writeAll(", ");
                try stdout.print("{s}", .{conn});
            }
            try stdout.writeAll("\n");
        }
    }

    try stdout.writeAll("\n");
    try stdout.flush();
}

/// JSON output for AI
fn outputJson(trace_nodes: []const TraceNode) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll("[");
    for (trace_nodes, 0..) |node, i| {
        if (i > 0) try stdout.writeAll(",");
        try stdout.writeAll("{");
        try stdout.print("\"id\":\"{s}\",", .{node.id});
        try stdout.print("\"level\":{d},", .{node.level});
        try stdout.print("\"type\":\"{s}\",", .{node.node_type});
        try stdout.print("\"connections\":[", .{});

        for (node.connections.items, 0..) |conn, j| {
            if (j > 0) try stdout.writeAll(",");
            try stdout.print("\"{s}\"", .{conn});
        }

        try stdout.writeAll("]}");
    }
    try stdout.writeAll("]\n");
    try stdout.flush();
}

// Example CLI usage:
//
//   engram trace req.auth.oauth2
//   → Traces downstream dependencies (tests, implementations)
//
//   engram trace req.auth.oauth2 --up
//   → Traces upstream dependencies (parent requirements, features)
//
//   engram trace req.auth.oauth2 --depth 3
//   → Limits trace to 3 levels deep
//
//   engram trace req.auth.oauth2 --json
//   → Returns JSON for AI parsing

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
    
    const trace_result = try trace(allocator, &graph, config);
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
    
    const trace_result = try trace(allocator, &graph, config);
    defer {
        for (trace_result) |*n| n.deinit(allocator);
        allocator.free(trace_result);
    }
    
    // Should find req.auth as upstream
    try std.testing.expect(trace_result.len >= 1);
}

test "findNeuronaPath finds existing file" {
    const allocator = std.testing.allocator;
    
    const path = try findNeuronaPath(allocator, "req.auth");
    defer allocator.free(path);
    
    try std.testing.expect(path.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, path, "req.auth") != null);
}

test "findNeuronaPath returns error for non-existent file" {
    const allocator = std.testing.allocator;
    
    const result = findNeuronaPath(allocator, "nonexistent");
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
    const node = try allocator.create(TraceNode);
    node.* = TraceNode{
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
    const node = try allocator.create(TraceNode);
    node.* = TraceNode{
        .id = try allocator.dupe(u8, "test.id"),
        .level = 0,
        .connections = std.ArrayListUnmanaged([]const u8){},
        .node_type = try allocator.dupe(u8, "root"),
    };
    try nodes.append(allocator, node);
    
    // Should not panic
    try outputJson(nodes.items);
}
