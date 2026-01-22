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
