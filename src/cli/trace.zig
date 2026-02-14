// File: src/cli/trace.zig
// The `engram trace` command for visualizing dependency trees
// Traces requirements → tests → code, issues → blocked artifacts
// MIGRATED: Now uses Phase 3 CLI utilities (JsonOutput, HumanOutput)

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const readNeurona = @import("../storage/filesystem.zig").readNeurona;
const scanNeuronas = @import("../storage/filesystem.zig").scanNeuronas;
const findNeuronaPath = @import("../storage/filesystem.zig").findNeuronaPath;
const Graph = @import("../core/graph.zig").Graph;
const uri_parser = @import("../utils/uri_parser.zig");

// Import Phase 3 CLI utilities
const JsonOutput = @import("output/json.zig").JsonOutput;
const HumanOutput = @import("output/human.zig").HumanOutput;

pub const TraceConfig = struct {
    id: []const u8,
    direction: Direction = .down,
    max_depth: usize = 10,
    format: OutputFormat = .tree,
    json_output: bool = false,
    cortex_dir: ?[]const u8 = null,
};

pub const Direction = enum {
    up,
    down,
};

pub const OutputFormat = enum {
    tree,
    list,
};

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

pub fn execute(allocator: Allocator, config: TraceConfig) !void {
    const cortex_dir = uri_parser.findCortexDir(allocator, config.cortex_dir) catch |err| {
        if (err == error.CortexNotFound) {
            try HumanOutput.printError("No cortex found in current directory or within 3 directory levels.");
            try HumanOutput.printInfo("Navigate to a cortex directory or use --cortex <path> to specify location.");
            try HumanOutput.printInfo("Run 'engram init <name>' to create a new cortex.");
            std.process.exit(1);
        }
        return err;
    };
    defer if (config.cortex_dir == null) allocator.free(cortex_dir);

    const neuronas_dir = try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex_dir});
    defer allocator.free(neuronas_dir);

    const neuronas = scanNeuronas(allocator, neuronas_dir) catch |err| {
        switch (err) {
            error.FileNotFound => {
                try HumanOutput.printError("No neuronas directory found. Please run 'engram init' first or ensure you're in a Cortex directory.");
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

    for (neuronas) |*neurona| {
        var conn_it = neurona.connections.iterator();
        while (conn_it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                try graph.addEdge(allocator, neurona.id, conn.target_id, conn.weight);
            }
        }
    }

    const trace_result = try trace(allocator, &graph, neuronas_dir, config);
    defer {
        for (trace_result) |*n| n.deinit(allocator);
        allocator.free(trace_result);
    }

    if (config.json_output) {
        try outputJson(trace_result);
    } else {
        try outputTree(trace_result);
    }
}

fn trace(allocator: Allocator, graph: *Graph, neuronas_dir: []const u8, config: TraceConfig) ![]TraceNode {
    var result = std.ArrayListUnmanaged(TraceNode){};
    errdefer {
        for (result.items) |*n| n.deinit(allocator);
        result.deinit(allocator);
    }

    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    try traceRecursive(allocator, graph, &result, &visited, config.id, 0, config.max_depth, config.direction);

    for (result.items) |*node| {
        const filepath = try findNeuronaPath(allocator, node.id, neuronas_dir);
        defer allocator.free(filepath);

        var node_neurona = readNeurona(allocator, filepath) catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };
        defer node_neurona.deinit(allocator);

        node.node_type = try allocator.dupe(u8, @tagName(node_neurona.type));
    }

    return result.toOwnedSlice(allocator);
}

fn traceRecursive(
    allocator: Allocator,
    graph: *Graph,
    result: *std.ArrayListUnmanaged(TraceNode),
    visited: *std.StringHashMap(void),
    node_id: []const u8,
    level: usize,
    max_depth: usize,
    direction: Direction,
) !void {
    if (level >= max_depth) return;

    if (visited.contains(node_id)) return;
    try visited.put(node_id, {});

    const edges = switch (direction) {
        .down => graph.getAdjacent(node_id),
        .up => graph.getIncoming(node_id),
    };

    var node = TraceNode{
        .id = try allocator.dupe(u8, node_id),
        .level = level,
        .connections = std.ArrayListUnmanaged([]const u8){},
        .node_type = "unknown",
    };
    errdefer {
        node.deinit(allocator);
    }

    for (edges) |edge| {
        try node.connections.append(allocator, try allocator.dupe(u8, edge.target_id));
        try traceRecursive(allocator, graph, result, visited, edge.target_id, level + 1, max_depth, direction);
    }

    try result.append(allocator, node);
}

fn outputTree(trace_nodes: []const TraceNode) !void {
    try HumanOutput.printHeader("Dependency Tree", "🌲");

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    for (trace_nodes) |node| {
        for (0..node.level * 2) |_| {
            try stdout.writeByte(' ');
        }

        try stdout.print("{s} ({d})\n", .{ node.id, node.connections.items.len });

        if (node.connections.items.len > 0) {
            for (node.connections.items, 0..) |conn, i| {
                if (i > 0) {
                    try stdout.print(", ", .{});
                }
                try stdout.print("{s}", .{conn});
            }
            try stdout.print("\n", .{});
        }
    }

    try stdout.print("\n", .{});
    try stdout.flush();
}

fn outputJson(trace_nodes: []const TraceNode) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try JsonOutput.beginArray(stdout);
    for (trace_nodes, 0..) |node, i| {
        if (i > 0) {
            try JsonOutput.separator(stdout, true);
        }
        try JsonOutput.beginObject(stdout);
        try JsonOutput.stringField(stdout, "id", node.id);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.numberField(stdout, "level", node.level);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.stringField(stdout, "type", node.node_type);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.stringField(stdout, "connections", "");
        try JsonOutput.beginArray(stdout);

        for (node.connections.items, 0..) |conn, j| {
            if (j > 0) {
                try JsonOutput.separator(stdout, true);
            }
            try JsonOutput.stringField(stdout, "", conn);
        }

        try JsonOutput.endArray(stdout);
        try JsonOutput.endObject(stdout);
    }
    try JsonOutput.endArray(stdout);
    try stdout.flush();
}

test "trace command loads neuronas and builds graph" {
    const allocator = std.testing.allocator;

    const neuronas = try scanNeuronas(allocator, "tests/fixtures/trace");
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    try std.testing.expectEqual(@as(usize, 4), neuronas.len);

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

    try std.testing.expectEqual(@as(usize, 4), graph.nodeCount());

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
        .cortex_dir = null,
    };

    const result = try trace(allocator, &graph, "tests/fixtures/trace", config);
    defer {
        for (result) |*n| n.deinit(allocator);
        allocator.free(result);
    }

    try std.testing.expect(result.len > 0);
}
