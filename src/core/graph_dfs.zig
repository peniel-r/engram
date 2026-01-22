
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

    /// Recursive DFS helper
    fn dfsRecursive(
        allocator: Allocator,
        graph: *const Graph,
        node_id: []const u8,
        visited: *std.StringHashMap(void),
        result: *std.ArrayList([]const u8)
    ) !void {
        const adj = graph.getAdjacent(node_id);
        for (adj) |edge| {
            if (visited.get(edge.target_id) == null) {
                try visited.put(edge.target_id, {});
                try result.append(edge.target_id);
                try dfsRecursive(allocator, graph, edge.target_id, visited, result);
            }
        }
    }
