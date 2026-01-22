
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
    fn dfsRecursive(allocator: Allocator, graph: *const Graph, node_id: []const u8, visited: *std.StringHashMap(void), result: *std.ArrayList([]const u8)) !void {
        const adj = self.getAdjacent(node_id);
        for (adj) |edge| {
            if (visited.get(edge.target_id) == null) {
                try visited.put(edge.target_id, {});
                try result.append(edge.target_id);
                try self.dfsRecursive(allocator, edge.target_id, visited, result);
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
            const current_entry = visited.get(current_id).?;

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
                i += 1;
                j -= 1;
            }

            return path;
        } else {
            return error.PathNotFound;
        }
    }
};

test "Graph init creates empty graph" {
    const allocator = std.testing.allocator;

    const graph = Graph.init();
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
    try std.testing.expectEqual(@as(usize, 1), graph.inDegree("node2"));
}
