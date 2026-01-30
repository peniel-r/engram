// Graph data structure for Neurona System
// Provides O(1) adjacency lookup with bidirectional indexing
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Graph edge with weight
pub const Edge = struct {
    target_id: []const u8,
    weight: u8, // 0-100

    pub fn format(self: Edge, allocator: Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s} (weight: {d})", .{ self.target_id, self.weight });
    }
};

/// Graph adjacency list with bidirectional indexing
pub const Graph = struct {
    /// Forward edges: source -> [edges]
    adjacency_list: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(Edge)),
    /// Reverse edges: target -> [incoming edges]
    reverse_index: std.StringHashMapUnmanaged(std.ArrayListUnmanaged(Edge)),

    /// Initialize empty graph
    pub fn init() Graph {
        return Graph{
            .adjacency_list = .{},
            .reverse_index = .{},
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *Graph, allocator: Allocator) void {
        // Free forward edges
        var adj_it = self.adjacency_list.iterator();
        while (adj_it.next()) |entry| {
            for (entry.value_ptr.items) |*edge| {
                allocator.free(edge.target_id);
            }
            entry.value_ptr.deinit(allocator);
            allocator.free(entry.key_ptr.*);
        }
        self.adjacency_list.deinit(allocator);

        // Free reverse edges
        var rev_it = self.reverse_index.iterator();
        while (rev_it.next()) |entry| {
            for (entry.value_ptr.items) |*edge| {
                allocator.free(edge.target_id);
            }
            entry.value_ptr.deinit(allocator);
            allocator.free(entry.key_ptr.*);
        }
        self.reverse_index.deinit(allocator);
    }

    /// Add edge to graph (bidirectional)
    pub fn addEdge(self: *Graph, allocator: Allocator, from_id: []const u8, to_id: []const u8, weight: u8) !void {
        // Ensure both nodes exist in adjacency list (even if no outgoing edges)
        if (!self.adjacency_list.contains(from_id)) {
            try self.adjacency_list.put(allocator, try allocator.dupe(u8, from_id), .{});
        }
        if (!self.adjacency_list.contains(to_id)) {
            try self.adjacency_list.put(allocator, try allocator.dupe(u8, to_id), .{});
        }

        // Add forward edge
        const entry = self.adjacency_list.getPtr(from_id).?;
        const edge = Edge{
            .target_id = try allocator.dupe(u8, to_id),
            .weight = weight,
        };
        try entry.append(allocator, edge);

        // Add reverse edge
        {
            const entry_rev = try self.reverse_index.getOrPut(allocator, to_id);
            if (!entry_rev.found_existing) {
                entry_rev.value_ptr.* = std.ArrayListUnmanaged(Edge){};
                entry_rev.key_ptr.* = try allocator.dupe(u8, to_id);
            }

            const edge_rev = Edge{
                .target_id = try allocator.dupe(u8, from_id),
                .weight = weight,
            };
            try entry_rev.value_ptr.append(allocator, edge_rev);
        }
    }

    /// Get all edges from a node (O(1))
    pub fn getAdjacent(self: *const Graph, node_id: []const u8) []const Edge {
        const entry = self.adjacency_list.get(node_id) orelse return &[0]Edge{};
        return entry.items;
    }

    /// Get all incoming edges to a node (O(1))
    pub fn getIncoming(self: *const Graph, node_id: []const u8) []const Edge {
        const entry = self.reverse_index.get(node_id) orelse return &[0]Edge{};
        return entry.items;
    }

    /// Check if edge exists
    pub fn hasEdge(self: *const Graph, from_id: []const u8, to_id: []const u8) bool {
        const adj = self.getAdjacent(from_id);
        for (adj) |edge| {
            if (std.mem.eql(u8, edge.target_id, to_id)) {
                return true;
            }
        }
        return false;
    }

    /// Count edges from a node
    pub fn degree(self: *const Graph, node_id: []const u8) usize {
        const entry = self.adjacency_list.get(node_id) orelse return 0;
        return entry.items.len;
    }

    /// Count incoming edges to a node
    pub fn inDegree(self: *const Graph, node_id: []const u8) usize {
        const entry = self.reverse_index.get(node_id) orelse return 0;
        return entry.items.len;
    }

    /// Count total nodes
    pub fn nodeCount(self: *const Graph) usize {
        // This is still not perfect if a node only exists in one map,
        // but with our new addEdge it should be fine.
        return self.adjacency_list.count();
    }

    /// Count total edges (forward + reverse)
    pub fn edgeCount(self: *const Graph) usize {
        var count: usize = 0;
        var it = self.adjacency_list.iterator();
        while (it.next()) |entry| {
            count += entry.value_ptr.items.len;
        }
        var it_rev = self.reverse_index.iterator();
        while (it_rev.next()) |entry| {
            count += entry.value_ptr.items.len;
        }
        return count;
    }

    // ==================== Traversal Algorithms ====================

    /// BFS traversal with level tracking
    pub const BFSResult = struct {
        node_id: []const u8,
        level: usize,
        path: std.ArrayList([]const u8),
    };

    /// Breadth-First Search traversal
    /// Returns nodes by level (depth) from starting node
    pub fn bfs(self: *const Graph, allocator: Allocator, start_id: []const u8) ![]BFSResult {
        var visited = std.StringHashMap(void).init(allocator);
        defer visited.deinit();

        var queue = std.ArrayList([]const u8).init(allocator);
        defer queue.deinit();

        var levels = std.StringHashMap(usize).init(allocator);
        defer levels.deinit();

        var result = std.ArrayList(BFSResult).init(allocator);
        errdefer {
            for (result.items) |*r| {
                r.path.deinit(allocator);
            }
            result.deinit(allocator);
        }

        // Start with initial node
        try visited.put(start_id, {});
        try queue.append(start_id);
        try levels.put(start_id, 0);

        while (queue.items.len > 0) {
            const current_id = queue.orderedRemove(0);
            const current_level = levels.get(current_id).?;

            // Get adjacent nodes
            const adj = self.getAdjacent(current_id);

            for (adj) |edge| {
                if (visited.get(edge.target_id) == null) {
                    try visited.put(edge.target_id, {});
                    try queue.append(edge.target_id);
                    try levels.put(edge.target_id, current_level + 1);

                    // Build path from start to current
                    var path = std.ArrayList([]const u8).init(allocator);
                    try path.append(start_id);
                    // Reconstruct path from previous BFS results
                    for (result.items) |r| {
                        if (r.level == current_level and
                            std.mem.eql(u8, r.node_id, current_id))
                        {
                            for (r.path.items) |p| {
                                try path.append(p);
                            }
                        }
                        break;
                    }
                    try path.append(edge.target_id);

                    try result.append(.{
                        .node_id = edge.target_id,
                        .level = current_level + 1,
                        .path = try path.toOwnedSlice(),
                    });
                }
            }
        }

        return result.toOwnedSlice();
    }

    /// DFS traversal
    /// Visit all reachable nodes using depth-first search
    pub fn dfs(self: *const Graph, allocator: Allocator, start_id: []const u8) !std.ArrayList([]const u8) {
        var visited = std.StringHashMap(void).init(allocator);
        defer visited.deinit();

        var result = std.ArrayList([]const u8).init(allocator);
        defer result.deinit();

        try visited.put(start_id, {});
        try dfsRecursive(allocator, self, start_id, &visited, &result);

        return result;
    }

    /// Recursive DFS helper (called from DFS traversal)
    fn dfsRecursive(allocator: Allocator, graph: *const Graph, node_id: []const u8, visited: *std.StringHashMap(void), result: *std.ArrayList([]const u8)) !void {
        const adj = graph.getAdjacent(node_id);
        for (adj) |edge| {
            if (visited.get(edge.target_id) == null) {
                try visited.put(edge.target_id, {});
                try result.append(edge.target_id);
                try dfsRecursive(allocator, graph, edge.target_id, visited, result);
            }
        }
    }

    /// Shortest path finding (BFS-based, unweighted)
    /// Returns list of node IDs in shortest path from start to end
    pub fn shortestPath(self: *const Graph, allocator: Allocator, start_id: []const u8, end_id: []const u8) !std.ArrayList([]const u8) {
        var visited = std.StringHashMap(struct { prev: ?[]const u8 }).init(allocator);
        defer {
            var it = visited.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
            }
            visited.deinit();
        }

        var queue = std.ArrayList([]const u8).init(allocator);
        defer queue.deinit();

        // Start BFS
        try visited.put(start_id, .{ .prev = null });
        try queue.append(start_id);

        while (queue.items.len > 0) {
            const current_id = queue.orderedRemove(0);

            // Found target node
            if (std.mem.eql(u8, current_id, end_id)) {
                break;
            }

            // Explore neighbors
            const adj = self.getAdjacent(current_id);
            _ = visited.get(current_id);

            for (adj) |edge| {
                if (visited.get(edge.target_id) == null) {
                    try visited.put(edge.target_id, .{ .prev = current_id });
                    try queue.append(edge.target_id);
                }
            }
        }

        // Check if path was found
        if (visited.get(end_id)) |_| {
            // Reconstruct path backwards
            var path = std.ArrayList([]const u8).init(allocator);
            defer path.deinit();

            var current_id: []const u8 = end_id;
            while (true) {
                const entry = visited.get(current_id).?;
                try path.append(current_id);

                if (entry.prev) |prev| {
                    current_id = prev;
                } else {
                    break; // Reached start node
                }
            }

            // Reverse to get path from start -> end
            var i: usize = 0;
            var j: usize = path.items.len - 1;
            while (i < j) {
                const tmp = path.items[i];
                path.items[i] = path.items[j];
                path.items[j] = tmp;
                i += 1;
                j -= 1;
            }

            return path;
        } else {
            return error.PathNotFound;
        }
    }

    // ==================== Serialization ====================

    /// Serialize graph to binary format
    /// Format:
    /// [magic: 4 bytes "ENGI"]
    /// [version: 4 bytes u32]
    /// [node_count: 8 bytes u64]
    /// [nodes: node_count * (id_len: u16, id: data, out_degree: u16)]
    /// [edges: for each node, out_degree * (target_id_len: u16, target_id: data, weight: u8)]
    pub fn serialize(self: *const Graph, allocator: Allocator) ![]u8 {
        var buffer = std.ArrayListUnmanaged(u8){};
        errdefer buffer.deinit(allocator);

        const writer = buffer.writer(allocator);

        // 1. Header
        try writer.writeAll("ENGI");
        try writer.writeInt(u32, 1, .little); // Version
        try writer.writeInt(u64, @as(u64, self.nodeCount()), .little);

        // 2. Nodes Metadata
        var it = self.adjacency_list.iterator();
        while (it.next()) |entry| {
            const id = entry.key_ptr.*;
            const edges = entry.value_ptr.items;

            try writer.writeInt(u16, @as(u16, @intCast(id.len)), .little);
            try writer.writeAll(id);
            try writer.writeInt(u16, @as(u16, @intCast(edges.len)), .little);
        }

        // 3. Edges Data
        it = self.adjacency_list.iterator();
        while (it.next()) |entry| {
            const edges = entry.value_ptr.items;
            for (edges) |edge| {
                try writer.writeInt(u16, @as(u16, @intCast(edge.target_id.len)), .little);
                try writer.writeAll(edge.target_id);
                try writer.writeInt(u8, edge.weight, .little);
            }
        }

        return buffer.toOwnedSlice(allocator);
    }

    /// Deserialize graph from binary format
    pub fn deserialize(data: []const u8, allocator: Allocator) !Graph {
        var fbs = std.io.fixedBufferStream(data);
        const reader = fbs.reader();

        // 1. Header
        var magic: [4]u8 = undefined;
        try reader.readNoEof(&magic);
        if (!std.mem.eql(u8, &magic, "ENGI")) return error.InvalidMagic;

        const version = try reader.readInt(u32, .little);
        if (version != 1) return error.UnsupportedVersion;

        const node_count = try reader.readInt(u64, .little);

        var graph = Graph.init();
        errdefer graph.deinit(allocator);

        // Pre-allocate nodes to avoid reallocations
        try graph.adjacency_list.ensureTotalCapacity(allocator, @intCast(node_count));

        // 2. Temporary storage for node metadata to build edges later
        const NodeMeta = struct {
            id: []const u8,
            out_degree: u16,
        };
        var nodes_meta = try allocator.alloc(NodeMeta, @intCast(node_count));
        defer {
            // We only free the array, but NOT the IDs inside if they were dupped?
            // Wait, we need to be careful with memory ownership here.
            allocator.free(nodes_meta);
        }

        // Read all node IDs and degrees
        for (0..node_count) |i| {
            const id_len = try reader.readInt(u16, .little);
            const id = try allocator.alloc(u8, id_len);
            errdefer allocator.free(id);
            try reader.readNoEof(id);
            const out_degree = try reader.readInt(u16, .little);

            nodes_meta[i] = .{ .id = id, .out_degree = out_degree };
            // Initialize entry in adjacency list
            try graph.adjacency_list.put(allocator, id, .{});
        }

        // 3. Read edges and populate graph (forward and reverse)
        for (nodes_meta) |meta| {
            for (0..meta.out_degree) |_| {
                const target_id_len = try reader.readInt(u16, .little);
                const target_id = try allocator.alloc(u8, target_id_len);
                errdefer allocator.free(target_id);
                try reader.readNoEof(target_id);
                const weight = try reader.readInt(u8, .little);

                // Add to forward adjacency list
                const adj_entry = graph.adjacency_list.getPtr(meta.id).?;
                try adj_entry.append(allocator, .{
                    .target_id = target_id,
                    .weight = weight,
                });

                // Add to reverse index
                const rev_entry = try graph.reverse_index.getOrPut(allocator, target_id);
                if (!rev_entry.found_existing) {
                    rev_entry.value_ptr.* = std.ArrayListUnmanaged(Edge){};
                    rev_entry.key_ptr.* = try allocator.dupe(u8, target_id);
                }
                try rev_entry.value_ptr.append(allocator, .{
                    .target_id = try allocator.dupe(u8, meta.id),
                    .weight = weight,
                });
            }
        }

        return graph;
    }
};

test "Graph init creates empty graph" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), graph.nodeCount());
    try std.testing.expectEqual(@as(usize, 0), graph.edgeCount());
}

test "Graph addEdge adds bidirectional" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    try graph.addEdge(allocator, "node1", "node2", 90);

    try std.testing.expectEqual(@as(usize, 2), graph.nodeCount());
    try std.testing.expectEqual(@as(usize, 2), graph.edgeCount());

    const adj = graph.getAdjacent("node1");
    try std.testing.expectEqual(@as(usize, 1), adj.len);
    try std.testing.expectEqualStrings("node2", adj[0].target_id);

    const incoming = graph.getIncoming("node2");
    try std.testing.expectEqual(@as(usize, 1), incoming.len);
    try std.testing.expectEqualStrings("node1", incoming[0].target_id);
}

test "Graph getAdjacent returns all edges" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    try graph.addEdge(allocator, "node1", "node2", 50);
    try graph.addEdge(allocator, "node1", "node3", 70);

    const adj = graph.getAdjacent("node1");
    try std.testing.expectEqual(@as(usize, 2), adj.len);
}

test "Graph hasEdge checks existence" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    try graph.addEdge(allocator, "node1", "node2", 50);

    try std.testing.expect(graph.hasEdge("node1", "node2"));
    try std.testing.expect(!graph.hasEdge("node1", "node3"));
}

test "Graph degree counts edges" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    try graph.addEdge(allocator, "node1", "node2", 50);
    try graph.addEdge(allocator, "node1", "node2", 50);

    try std.testing.expectEqual(@as(usize, 2), graph.degree("node1"));
    try std.testing.expectEqual(@as(usize, 2), graph.inDegree("node2"));
}

test "Graph serialize/deserialize" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    try graph.addEdge(allocator, "node1", "node2", 90);
    try graph.addEdge(allocator, "node2", "node3", 50);
    try graph.addEdge(allocator, "node3", "node1", 70);

    const data = try graph.serialize(allocator);
    defer allocator.free(data);

    var loaded = try Graph.deserialize(data, allocator);
    defer loaded.deinit(allocator);

    try std.testing.expectEqual(graph.nodeCount(), loaded.nodeCount());
    try std.testing.expectEqual(graph.edgeCount(), loaded.edgeCount());

    try std.testing.expect(loaded.hasEdge("node1", "node2"));
    try std.testing.expect(loaded.hasEdge("node2", "node3"));
    try std.testing.expect(loaded.hasEdge("node3", "node1"));

    const adj = loaded.getAdjacent("node1");
    try std.testing.expectEqual(@as(u8, 90), adj[0].weight);

    const incoming = loaded.getIncoming("node1");
    try std.testing.expectEqual(@as(u8, 70), incoming[0].weight);
}
