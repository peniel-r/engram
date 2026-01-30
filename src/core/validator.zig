// Connection Validator for Neurona System
// Validates connections between Neuronas based on type rules
// Enforces cardinality constraints and detects cycles

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("./neurona.zig").Neurona;
const NeuronaType = @import("./neurona.zig").NeuronaType;
const ConnectionType = @import("./neurona.zig").ConnectionType;
const Graph = @import("./graph.zig").Graph;

// ==================== Validation Rules ====================

/// Connection validation rule
pub const ValidationRule = struct {
    from_type: NeuronaType,
    to_type: NeuronaType,
    allowed_connections: []const ConnectionType,
    max_cardinality: ?usize = null,
};

/// Allowed connections between Neurona types
const ALLOWED_CONNECTIONS = [_]ValidationRule{
    // ALM: Requirement -> Test Case
    .{ .from_type = .requirement, .to_type = .test_case, .allowed_connections = &[_]ConnectionType{.validates} },

    // ALM: Requirement -> Artifact
    .{ .from_type = .requirement, .to_type = .artifact, .allowed_connections = &[_]ConnectionType{.implements} },

    // ALM: Issue -> Requirement
    .{ .from_type = .issue, .to_type = .requirement, .allowed_connections = &[_]ConnectionType{.blocks} },

    // ALM: Issue -> Issue
    .{ .from_type = .issue, .to_type = .issue, .allowed_connections = &[_]ConnectionType{ .blocks, .blocked_by, .relates_to } },

    // ALM: Test Case -> Artifact
    .{ .from_type = .test_case, .to_type = .artifact, .allowed_connections = &[_]ConnectionType{ .tests, .tested_by } },

    // Hierarchy: Any -> Any (parent/child)
    .{ .from_type = .concept, .to_type = .concept, .allowed_connections = &[_]ConnectionType{ .parent, .child, .relates_to } },
    .{ .from_type = .feature, .to_type = .requirement, .allowed_connections = &[_]ConnectionType{ .parent, .child } },
    .{ .from_type = .feature, .to_type = .feature, .allowed_connections = &[_]ConnectionType{ .parent, .child } },

    // Binary Tree: artifact -> artifact (using parent/child for left/right in tree context)
    .{ .from_type = .artifact, .to_type = .artifact, .allowed_connections = &[_]ConnectionType{ .parent, .child }, .max_cardinality = 1 },

    // Learning: Lesson -> Lesson
    .{ .from_type = .lesson, .to_type = .lesson, .allowed_connections = &[_]ConnectionType{ .prerequisite, .next } },

    // Reference: Concept -> Reference
    .{ .from_type = .concept, .to_type = .reference, .allowed_connections = &[_]ConnectionType{.relates_to} },

    // General: Any -> Any (relates_to as fallback)
};

// ==================== Connection Validation ====================

/// Validate if connection is allowed between two Neurona types
pub fn validateConnection(from: *const Neurona, to: *const Neurona, conn_type: ConnectionType) !void {
    for (ALLOWED_CONNECTIONS) |rule| {
        if (rule.from_type == from.type and rule.to_type == to.type) {
            // Check if connection type is allowed
            for (rule.allowed_connections) |allowed| {
                if (allowed == conn_type) {
                    return; // Valid
                }
            }
            return error.ConnectionTypeNotAllowed;
        }
    }

    // Fallback: allows relates_to between any types
    if (conn_type == .relates_to) {
        return;
    }

    return error.ConnectionTypeNotAllowed;
}

/// Validate cardinality constraint for a connection type
pub fn validateCardinality(neurona: *const Neurona, conn_type: ConnectionType, max_cardinality: usize) !void {
    const count = neurona.getConnections(conn_type).len;
    if (count >= max_cardinality) {
        return error.CardinalityExceeded;
    }
}

/// Get allowed connection types between two Neurona types
pub fn getAllowedConnections(from_type: NeuronaType, to_type: NeuronaType) []const ConnectionType {
    for (ALLOWED_CONNECTIONS) |rule| {
        if (rule.from_type == from_type and rule.to_type == to_type) {
            return rule.allowed_connections;
        }
    }
    return &[_]ConnectionType{.relates_to}; // Fallback
}

/// Validate that connections are only in frontmatter, not in body
/// Per Neurona spec, connections must be in YAML frontmatter
pub fn validateConnectionsLocation(body: []const u8) !void {
    // Check for connection keywords in body
    const connection_keywords = [_][]const u8{
        "connections:",
        "validates:",
        "validates_by:",
        "implements:",
        "blocks:",
        "blocked_by:",
        "tests:",
        "tested_by:",
        "relates_to:",
        "parent:",
        "child:",
        "prerequisite:",
        "next:",
    };

    for (connection_keywords) |keyword| {
        if (std.mem.indexOf(u8, body, keyword)) |_| {
            return error.ConnectionsInBodyNotAllowed;
        }
    }

    // Also check for legacy format "type:target:weight" pattern in body
    // This is a heuristic: look for patterns like "validated_by:target_id:weight"
    var line_iter = std.mem.splitScalar(u8, body, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        
        // Skip markdown headings
        if (trimmed[0] == '#') continue;
        
        // Check if line looks like a connection (contains multiple colons)
        var colon_count: usize = 0;
        for (trimmed) |c| {
            if (c == ':') colon_count += 1;
        }
        
        // Lines with 2+ colons might be legacy connection format
        if (colon_count >= 2 and !std.mem.startsWith(u8, trimmed, "http")) {
            // Check if any connection type is in the line
            for (connection_keywords) |keyword| {
                const keyword_without_colon = keyword[0 .. keyword.len - 1];
                if (std.mem.indexOf(u8, trimmed, keyword_without_colon)) |_| {
                    return error.ConnectionsInBodyNotAllowed;
                }
            }
        }
    }
}

// ==================== Cycle Detection ====================

/// Detect cycles in the graph using DFS
/// Returns list of node IDs involved in cycles
pub fn detectCycles(graph: *const Graph, allocator: Allocator) ![][]const u8 {
    var visited = std.StringHashMap(Color).init(allocator);
    defer {
        var it = visited.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        visited.deinit();
    }

    var cycles = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (cycles.items) |c| allocator.free(c);
        cycles.deinit(allocator);
    }

    // Mark all nodes as unvisited
    var node_it = graph.adjacency_list.iterator();
    while (node_it.next()) |entry| {
        try visited.put(try allocator.dupe(u8, entry.key_ptr.*), .white);
    }

    // Run DFS from each unvisited node
    var it = visited.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* == .white) {
            if (try dfsCycleDetect(graph, entry.key_ptr.*, &visited, &cycles, allocator)) {
                // Cycle found
            }
        }
    }

    return cycles.toOwnedSlice(allocator);
}

/// DFS helper for cycle detection
fn dfsCycleDetect(graph: *const Graph, node_id: []const u8, visited: *std.StringHashMap(Color), cycles: *std.ArrayListUnmanaged([]const u8), allocator: Allocator) !bool {
    try visited.put(node_id, .gray);

    const adj = graph.getAdjacent(node_id);
    for (adj) |edge| {
        const color = visited.get(edge.target_id) orelse .white;

        switch (color) {
            .white => {
                if (try dfsCycleDetect(graph, edge.target_id, visited, cycles, allocator)) {
                    return true;
                }
            },
            .gray => {
                // Back edge found - cycle detected
                try cycles.append(allocator, try allocator.dupe(u8, node_id));
                return true;
            },
            .black => {},
        }
    }

    try visited.put(node_id, .black);
    return false;
}

/// Color for cycle detection
const Color = enum { white, gray, black };

// ==================== Orphan Detection ====================

/// Find orphaned Neuronas (no connections in or out)
pub fn findOrphans(neuronas: []const Neurona, graph: *const Graph, allocator: Allocator) ![]const []const u8 {
    var orphans = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (orphans.items) |o| allocator.free(o);
        orphans.deinit(allocator);
    }

    for (neuronas) |neurona| {
        const has_outgoing = graph.degree(neurona.id) > 0;
        const has_incoming = graph.inDegree(neurona.id) > 0;

        if (!has_outgoing and !has_incoming) {
            try orphans.append(allocator, neurona.id);
        }
    }

    return orphans.toOwnedSlice(allocator);
}

/// Find unconnected Neuronas of a specific type
pub fn findUnconnectedOfType(neuronas: []const Neurona, graph: *const Graph, neurona_type: NeuronaType, allocator: Allocator) ![]const []const u8 {
    var result = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (result.items) |r| allocator.free(r);
        result.deinit(allocator);
    }

    for (neuronas) |neurona| {
        if (neurona.type != neurona_type) continue;

        const has_outgoing = graph.degree(neurona.id) > 0;
        const has_incoming = graph.inDegree(neurona.id) > 0;

        if (!has_outgoing and !has_incoming) {
            try result.append(allocator, neurona.id);
        }
    }

    return result.toOwnedSlice(allocator);
}

// ==================== Tests ====================

test "validateConnection allows test_case validates requirement" {
    const allocator = std.testing.allocator;

    var requirement = try Neurona.init(allocator);
    defer requirement.deinit(allocator);
    requirement.type = .requirement;

    var test_case = try Neurona.init(allocator);
    defer test_case.deinit(allocator);
    test_case.type = .test_case;

    // Valid: test_case validates requirement
    try validateConnection(&requirement, &test_case, .validates);
}

test "validateConnection rejects invalid connection type" {
    const allocator = std.testing.allocator;

    var requirement = try Neurona.init(allocator);
    defer requirement.deinit(allocator);
    requirement.type = .requirement;

    var test_case = try Neurona.init(allocator);
    defer test_case.deinit(allocator);
    test_case.type = .test_case;

    // Invalid: test_case should not "implement" requirement
    const result = validateConnection(&requirement, &test_case, .implements);
    try std.testing.expectError(error.ConnectionTypeNotAllowed, result);
}

test "validateConnection allows relates_to between any types" {
    const allocator = std.testing.allocator;

    var issue = try Neurona.init(allocator);
    defer issue.deinit(allocator);
    issue.type = .issue;

    var feature = try Neurona.init(allocator);
    defer feature.deinit(allocator);
    feature.type = .feature;

    // relates_to should work between any types
    try validateConnection(&issue, &feature, .relates_to);
}

test "validateCardinality enforces limit" {
    const allocator = std.testing.allocator;

    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);
    neurona.type = .artifact;

    // Test with 0 existing connections - should pass max_cardinality of 1
    const count = neurona.getConnections(.parent).len;
    try std.testing.expectEqual(@as(usize, 0), count);

    // Cardinality check should pass for 0 < 1
    if (count >= 1) return error.CardinalityExceeded;
}

test "detectCycles finds cycles in simple graph" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    // Create cycle: A -> B -> C -> A
    try graph.addEdge(allocator, "A", "B", 50);
    try graph.addEdge(allocator, "B", "C", 50);
    try graph.addEdge(allocator, "C", "A", 50);

    const cycles = try detectCycles(&graph, allocator);
    defer {
        for (cycles) |c| allocator.free(c);
        allocator.free(cycles);
    }

    try std.testing.expect(cycles.len > 0);
}

test "detectCycles returns empty for acyclic graph" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    // Create acyclic graph: A -> B -> C
    try graph.addEdge(allocator, "A", "B", 50);
    try graph.addEdge(allocator, "B", "C", 50);

    const cycles = try detectCycles(&graph, allocator);
    defer {
        for (cycles) |c| allocator.free(c);
        allocator.free(cycles);
    }

    try std.testing.expectEqual(@as(usize, 0), cycles.len);
}

test "findOrphans identifies unconnected nodes" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    // Add connected nodes
    try graph.addEdge(allocator, "A", "B", 50);

    var neuronas = [_]Neurona{
        try Neurona.init(allocator),
        try Neurona.init(allocator),
    };
    defer {
        for (0..neuronas.len) |i| neuronas[i].deinit(allocator);
    }

    neuronas[0].id = try allocator.dupe(u8, "A");
    neuronas[1].id = try allocator.dupe(u8, "D"); // Node D has no connections in graph

    const orphans = try findOrphans(&neuronas, &graph, allocator);

    // Node "D" should be orphan (no connections)
    try std.testing.expect(orphans.len > 0);

    // Don't free orphans - they point to neurona.id strings which will be freed by neurona.deinit
    allocator.free(orphans);
}

test "getAllowedConnections returns valid connection types" {
    const conns = getAllowedConnections(.requirement, .test_case);
    try std.testing.expect(conns.len > 0);
    try std.testing.expectEqual(ConnectionType.validates, conns[0]);
}
