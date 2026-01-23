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
        // Add forward edge
        const entry = try self.adjacency_list.getOrPut(allocator, from_id);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.ArrayListUnmanaged(Edge){};
            entry.key_ptr.* = try allocator.dupe(u8, from_id);
        }

        const edge = Edge{
            .target_id = try allocator.dupe(u8, to_id),
            .weight = weight,
        };
        try entry.value_ptr.append(allocator, edge);

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
        return self.adjacency_list.count();
    }

    /// Count total edges
    pub fn edgeCount(self: *const Graph) usize {
        var count: usize = 0;
        var it = self.adjacency_list.iterator();
        while (it.next()) |entry| {
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

// ==================== Tests ====================

test "Edge format returns correct string" {
    const graph_mod = @import("graph_header.zig");
    const allocator = std.testing.allocator;
    
    const edge = graph_mod.Edge{
        .target_id = "node.002",
        .weight = 75,
    };
    
    const formatted = try edge.format(allocator);
    defer allocator.free(formatted);
    
    try std.testing.expect(formatted.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "node.002") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "weight: 75") != null);
}

test "Graph init creates empty graph" {
    const graph_mod = @import("graph_header.zig");
    const allocator = std.testing.allocator;
    
    var graph = graph_mod.Graph.init();
    defer graph.deinit(allocator);
    
    try std.testing.expectEqual(@as(usize, 0), graph.nodeCount());
    try std.testing.expectEqual(@as(usize, 0), graph.edgeCount());
}

test "Graph addEdge creates forward and reverse edges" {
    const graph_mod = @import("graph_header.zig");
    const allocator = std.testing.allocator;
    
    var graph = graph_mod.Graph.init();
    defer graph.deinit(allocator);
    
    try graph.addEdge(allocator, "node1", "node2", 50);
    
    // Check forward edge
    const adj = graph.getAdjacent("node1");
    try std.testing.expectEqual(@as(usize, 1), adj.len);
    try std.testing.expectEqualStrings("node2", adj[0].target_id);
    
    // Check reverse edge
    const incoming = graph.getIncoming("node2");
    try std.testing.expectEqual(@as(usize, 1), incoming.len);
    try std.testing.expectEqualStrings("node1", incoming[0].target_id);
}

test "Graph getAdjacent returns O(1) lookup" {
    const graph_mod = @import("graph_header.zig");
    const allocator = std.testing.allocator;
    
    var graph = graph_mod.Graph.init();
    defer graph.deinit(allocator);
    
    try graph.addEdge(allocator, "node1", "node2", 50);
    
    // Get adjacent for node1 (should return node2)
    const adj1 = graph.getAdjacent("node1");
    try std.testing.expectEqual(@as(usize, 1), adj1.len);
    
    // Get adjacent for node2 (should return empty)
    const adj2 = graph.getAdjacent("node2");
    try std.testing.expectEqual(@as(usize, 0), adj2.len);
}

test "Graph hasEdge correctly detects edge existence" {
    const graph_mod = @import("graph_header.zig");
    const allocator = std.testing.allocator;
    
    var graph = graph_mod.Graph.init();
    defer graph.deinit(allocator);
    
    try graph.addEdge(allocator, "node1", "node2", 50);
    
    // Edge should exist
    try std.testing.expectEqual(true, graph.hasEdge("node1", "node2"));
    
    // Reverse edge should also exist (bidirectional)
    try std.testing.expectEqual(true, graph.hasEdge("node2", "node1"));
    
    // Edge should not exist
    try std.testing.expectEqual(false, graph.hasEdge("node1", "node3"));
}

test "Graph degree counts edges correctly" {
    const graph_mod = @import("graph_header.zig");
    const allocator = std.testing.allocator;
    
    var graph = graph_mod.Graph.init();
    defer graph.deinit(allocator);
    
    try graph.addEdge(allocator, "node1", "node2", 50);
    try graph.addEdge(allocator, "node1", "node3", 75);
    
    // node1 has 2 outgoing edges
    try std.testing.expectEqual(@as(usize, 2), graph.degree("node1"));
    
    // node2 has 1 incoming edge
    try std.testing.expectEqual(@as(usize, 1), graph.inDegree("node2"));
}
