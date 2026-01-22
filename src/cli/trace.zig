// File: src/cli/trace.zig
// The `engram trace` command for visualizing dependency trees
// Traces requirements → tests → code, issues → blocked artifacts

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("storage").readNeurona;
const Graph = @import("core").Graph;
const scanNeuronas = @import("storage").scanNeuronas;

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
    connections: std.ArrayList([]const u8),
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
    const neuronas = try scanNeuronas(allocator, "neuronas");
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    var graph = try Graph.init(allocator);
    defer graph.deinit(allocator);

    // Build graph from Neuronas
    for (neuronas) |*neurona| {
        try graph.addNode(neurona.id, neurona.*);

        // Add connections
        var conn_it = neurona.connections.iterator();
        while (conn_it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                try graph.addEdge(neurona.id, conn.target_id, conn.weight);
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

    const start_neurona = try Neurona(allocator, filepath);
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

    var result = std.ArrayList(TraceNode).init(allocator);
    errdefer {
        for (result) |*n| n.deinit(allocator);
        result.deinit(allocator);
    }

    if (config.direction == .down) {
        try buildDownstreamTree(allocator, graph, &visited, &result, config.id, config.max_depth);
    } else {
        try buildUpstreamTree(allocator, graph, &visited, &result, config.id, config.max_depth);
    }

    return result.toOwnedSlice();
}

/// Build downstream tree (children, implementations)
fn buildDownstreamTree(
    allocator: Allocator,
    graph: *Graph,
    visited: *std.StringHashMap(*TraceNode),
    result: *std.ArrayList(TraceNode),
    start_id: []const u8,
    max_depth: usize
) !void {
    // Create root node
    const root = try allocator.create(TraceNode);
    root.* = TraceNode{
        .id = start_id,
        .level = 0,
        .connections = std.ArrayList([]const u8).init(allocator),
        .node_type = try allocator.dupe(u8, "root"),
    };

    try visited.put(start_id, root);
    try result.append(root);

    // BFS to collect nodes by level
    var queue = std.ArrayList([]const u8).init(allocator);
    defer queue.deinit();

    try queue.append(start_id);

    var current_depth: usize = 0;

    while (queue.items.len > 0 and current_depth < max_depth) {
        const current_id = queue.orderedRemove(0);
        const adj = graph.getAdjacent(current_id);

        for (adj) |edge| {
            if (visited.get(edge.target_id) == null) {
                const child = try allocator.create(TraceNode);
                child.* = TraceNode{
                    .id = edge.target_id,
                    .level = current_depth + 1,
                    .connections = std.ArrayList([]const u8).init(allocator),
                    .node_type = try allocator.dupe(u8, "downstream"),
                };

                try visited.put(edge.target_id, child);
                try result.append(child);
                try queue.append(edge.target_id);

                // Add connection to parent
                const parent_node = visited.get(current_id).?;
                try parent_node.connections.append(allocator, edge.target_id);
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
    result: *std.ArrayList(TraceNode),
    start_id: []const u8,
    max_depth: usize
) !void {
    // Create root node
    const root = try allocator.create(TraceNode);
    root.* = TraceNode{
        .id = start_id,
        .level = 0,
        .connections = std.ArrayList([]const u8).init(allocator),
        .node_type = try allocator.dupe(u8, "root"),
    };

    try visited.put(start_id, root);
    try result.append(root);

    // DFS to trace upstream
    var stack = std.ArrayList([]const u8).init(allocator);
    defer stack.deinit();

    try stack.append(start_id);

    var current_depth: usize = 0;

    while (stack.items.len > 0 and current_depth < max_depth) {
        const current_id = stack.pop();

        // Get incoming edges (parents)
        const incoming = graph.getIncoming(current_id);

        for (incoming) |edge| {
            if (visited.get(edge.target_id) == null) {
                const parent = try allocator.create(TraceNode);
                parent.* = TraceNode{
                    .id = edge.target_id,
                    .level = current_depth + 1,
                    .connections = std.ArrayList([]const u8).init(allocator),
                    .node_type = try allocator.dupe(u8, "upstream"),
                };

                try visited.put(edge.target_id, parent);
                try result.append(parent);
                try stack.append(edge.target_id);

                // Add connection to child
                const child_node = visited.get(current_id).?;
                try child_node.connections.append(allocator, edge.target_id);
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
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("\n🌲 Dependency Tree\n");
    try stdout.writeByteNTimes('=', 40);
    try stdout.writeAll("\n");

    for (trace_nodes) |node| {
        // Indent based on level
        try stdout.writeByteNTimes(' ', node.level * 2);

        try stdout.print("{s} ({d})\n", .{ node.id, node.connections.items.len });
        if (node.connections.items.len > 0) {
            for (node.connections.items, 0..) |conn, i| {
                if (i > 0) try stdout.writeAll(", ");
                try stdout.print("{s}", .{conn});
            }
        }
    }

    try stdout.writeAll("\n");
}

/// JSON output for AI
fn outputJson(trace_nodes: []const TraceNode) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("[");
    for (trace_nodes, 0..) |node| {
        if (node.id > 0) try stdout.writeAll(",");
        try stdout.writeAll("{");
        try stdout.print("\"id\":\"{s}", .{node.id});
        try stdout.print("\"level\":{d}", .{node.level});
        try stdout.print("\"type\":\"{s}", .{node.node_type});
        try stdout.print("\"connections\":[", .{});

        for (node.connections.items, 0..) |conn, i| {
            if (i > 0) try stdout.writeAll(",");
            try stdout.print("\"{s}\"", .{conn});
        }

        try stdout.writeAll("]");
    }
    try stdout.writeAll("]\n");
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
