// File: src/cli/impact.zig
// The `engram impact` command for impact analysis on code changes
// Traces upstream and downstream dependencies to identify affected tests, requirements

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const ConnectionType = @import("../core/neurona.zig").ConnectionType;
const Graph = @import("../core/graph.zig").Graph;
const scanNeuronas = @import("../storage/filesystem.zig").scanNeuronas;
const readNeurona = @import("../storage/filesystem.zig").readNeurona;

/// Impact configuration
pub const ImpactConfig = struct {
    id: []const u8,
    direction: ImpactDirection = .both,
    max_depth: usize = 10,
    include_recommendations: bool = true,
    json_output: bool = false,
    neuronas_dir: []const u8 = "neuronas",
};

pub const ImpactDirection = enum {
    upstream, // Trace dependencies (requirements, features)
    downstream, // Trace dependents (tests, artifacts)
    both, // Both directions
};

/// Impact analysis result
pub const ImpactResult = struct {
    neurona_id: []const u8,
    neurona_type: NeuronaType,
    title: []const u8,
    level: usize,
    direction: ImpactDirection,
    connection_type: ?ConnectionType,
    recommendation: ?Recommendation,

    pub fn deinit(self: *ImpactResult, allocator: Allocator) void {
        allocator.free(self.neurona_id);
        allocator.free(self.title);
        if (self.recommendation) |*rec| rec.deinit(allocator);
    }
};

/// Test recommendation
pub const Recommendation = struct {
    action: RecommendationAction,
    priority: u8, // 1-5
    reason: []const u8,

    pub fn deinit(self: *Recommendation, allocator: Allocator) void {
        allocator.free(self.reason);
    }
};

pub const RecommendationAction = enum {
    run_test, // Re-run the test
    review, // Manual review needed
    update, // Update documentation or code
    investigate, // Investigate potential issues
    none, // No action needed
};

/// Main command handler
pub fn execute(allocator: Allocator, config: ImpactConfig) !void {
    // Step 1: Load all Neuronas and build graph
    const neuronas = try scanNeuronas(allocator, config.neuronas_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    var graph = Graph.init();
    defer graph.deinit(allocator);

    // Build graph from Neuronas
    for (neuronas) |*neurona| {
        var conn_it = neurona.connections.iterator();
        while (conn_it.next()) |entry| {
            for (entry.value_ptr.connections.items) |conn| {
                try graph.addEdge(allocator, neurona.id, conn.target_id, conn.weight);
            }
        }
    }

    // Step 2: Perform impact analysis
    const results = try analyzeImpact(allocator, &graph, neuronas, config);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    // Step 3: Output results
    if (config.json_output) {
        try outputJson(results);
    } else {
        try outputImpact(allocator, results, config);
    }
}

/// Analyze impact of changes to a Neurona
pub fn analyzeImpact(allocator: Allocator, graph: *Graph, neuronas: []const Neurona, config: ImpactConfig) ![]ImpactResult {
    var result = std.ArrayListUnmanaged(ImpactResult){};
    errdefer {
        for (result.items) |*r| r.deinit(allocator);
        result.deinit(allocator);
    }

    // Build ID -> Neurona map for lookups
    var neurona_map = std.StringHashMap(*const Neurona).init(allocator);
    defer neurona_map.deinit();
    for (neuronas) |*neurona| {
        try neurona_map.put(neurona.id, neurona);
    }

    // Trace upstream dependencies
    if (config.direction == .upstream or config.direction == .both) {
        const upstream = try traceDirection(allocator, graph, config.id, config.max_depth, .upstream);
        defer {
            for (upstream.items) |item| allocator.free(item);
            var upstream_mut = upstream;
            upstream_mut.deinit(allocator);
        }

        for (upstream.items) |node_id| {
            if (std.mem.eql(u8, node_id, config.id)) continue;

            const neurona_ptr = neurona_map.get(node_id) orelse continue;
            const conn_type = getConnectionType(graph, config.id, node_id);
            const level = getLevel(graph, config.id, node_id);

            const rec = if (config.include_recommendations)
                try generateRecommendation(allocator, neurona_ptr.*, conn_type, level)
            else
                null;

            try result.append(allocator, .{
                .neurona_id = try allocator.dupe(u8, node_id),
                .neurona_type = neurona_ptr.type,
                .title = try allocator.dupe(u8, neurona_ptr.title),
                .level = level,
                .direction = .upstream,
                .connection_type = conn_type,
                .recommendation = rec,
            });
        }
    }

    // Trace downstream dependents
    if (config.direction == .downstream or config.direction == .both) {
        var downstream = try traceDirection(allocator, graph, config.id, config.max_depth, .downstream);
        defer {
            for (downstream.items) |item| allocator.free(item);
            downstream.deinit(allocator);
        }

        for (downstream.items) |node_id| {
            if (std.mem.eql(u8, node_id, config.id)) continue;

            const neurona_ptr = neurona_map.get(node_id) orelse continue;
            const conn_type = getConnectionType(graph, config.id, node_id);
            const level = getLevel(graph, config.id, node_id);

            const rec = if (config.include_recommendations)
                try generateRecommendation(allocator, neurona_ptr.*, conn_type, level)
            else
                null;

            try result.append(allocator, .{
                .neurona_id = try allocator.dupe(u8, node_id),
                .neurona_type = neurona_ptr.type,
                .title = try allocator.dupe(u8, neurona_ptr.title),
                .level = level,
                .direction = .downstream,
                .connection_type = conn_type,
                .recommendation = rec,
            });
        }
    }

    // Sort by level, then by type (tests first)
    const sorted = try result.toOwnedSlice(allocator);
    sortResults(allocator, sorted);

    return sorted;
}

/// Trace nodes in a direction from start node
fn traceDirection(allocator: Allocator, graph: *Graph, start_id: []const u8, max_depth: usize, direction: ImpactDirection) !std.ArrayListUnmanaged([]const u8) {
    var result = std.ArrayListUnmanaged([]const u8){};
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    var queue = std.ArrayListUnmanaged(struct { id: []const u8, depth: usize }){};
    defer queue.deinit(allocator);

    try visited.put(start_id, {});
    try queue.append(allocator, .{ .id = start_id, .depth = 0 });

    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);
        if (current.depth >= max_depth) continue;

        const edges = if (direction == .upstream)
            graph.getIncoming(current.id)
        else
            graph.getAdjacent(current.id);

        for (edges) |edge| {
            if (visited.get(edge.target_id) == null) {
                try visited.put(edge.target_id, {});
                try result.append(allocator, try allocator.dupe(u8, edge.target_id));
                try queue.append(allocator, .{ .id = edge.target_id, .depth = current.depth + 1 });
            }
        }
    }

    return result;
}

/// Get connection type between two nodes
fn getConnectionType(graph: *Graph, from_id: []const u8, to_id: []const u8) ?ConnectionType {
    const adj = graph.getAdjacent(from_id);
    for (adj) |edge| {
        if (std.mem.eql(u8, edge.target_id, to_id)) {
            // We don't store connection type in graph edges
            // Return null for now
            return null;
        }
    }
    return null;
}

/// Get BFS level from start to end node
fn getLevel(graph: *Graph, start_id: []const u8, end_id: []const u8) usize {
    _ = graph;
    _ = start_id;
    _ = end_id;
    // Simplified - would need BFS to calculate actual level
    return 1;
}

/// Generate recommendation for affected Neurona
fn generateRecommendation(allocator: Allocator, neurona: Neurona, conn_type: ?ConnectionType, level: usize) !?Recommendation {
    _ = conn_type;

    switch (neurona.type) {
        .test_case => {
            // Tests should be re-run
            return Recommendation{
                .action = .run_test,
                .priority = @intCast(@min(5, level)),
                .reason = try allocator.dupe(u8, "Test affected by code changes"),
            };
        },
        .requirement => {
            // Requirements may need review
            return Recommendation{
                .action = .review,
                .priority = @intCast(@min(3, level)),
                .reason = try allocator.dupe(u8, "Requirement may need verification"),
            };
        },
        .issue => {
            // Issues might be resolved
            return Recommendation{
                .action = .investigate,
                .priority = @intCast(@min(4, level)),
                .reason = try allocator.dupe(u8, "Issue may be resolved by changes"),
            };
        },
        .artifact => {
            return Recommendation{
                .action = .investigate,
                .priority = @intCast(@min(2, level)),
                .reason = try allocator.dupe(u8, "Artifact affected by dependencies"),
            };
        },
        else => {
            return Recommendation{
                .action = .none,
                .priority = 0,
                .reason = try allocator.dupe(u8, "No action required"),
            };
        },
    }
}

/// Sort results by level (ascending) and type priority
fn sortResults(allocator: Allocator, results: []ImpactResult) void {
    _ = allocator;
    // Simple bubble sort
    for (0..results.len - 1) |i| {
        for (0..results.len - i - 1) |j| {
            if (results[j].level > results[j + 1].level or
                (results[j].level == results[j + 1].level and
                    getTypePriority(results[j].neurona_type) > getTypePriority(results[j + 1].neurona_type)))
            {
                const tmp = results[j];
                results[j] = results[j + 1];
                results[j + 1] = tmp;
            }
        }
    }
}

/// Get priority for sorting by type
fn getTypePriority(t: NeuronaType) u8 {
    return switch (t) {
        .test_case => 1, // Tests first
        .issue => 2,
        .requirement => 3,
        .artifact => 4,
        .feature => 5,
        else => 6,
    };
}

/// Output impact analysis in readable format
fn outputImpact(allocator: Allocator, results: []const ImpactResult, config: ImpactConfig) !void {
    _ = allocator;

    std.debug.print("\n🎯 Impact Analysis for {s}\n", .{config.id});
    for (0..50) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});

    if (results.len == 0) {
        std.debug.print("No affected items found.\n", .{});
        return;
    }

    // Group by direction
    var upstream_count: usize = 0;
    var downstream_count: usize = 0;

    for (results) |r| {
        if (r.direction == .upstream) upstream_count += 1 else downstream_count += 1;
    }

    std.debug.print("\n📊 Summary\n", .{});
    for (0..20) |_| std.debug.print("-", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Upstream dependencies: {d}\n", .{upstream_count});
    std.debug.print("  Downstream dependents: {d}\n", .{downstream_count});
    std.debug.print("  Total affected: {d}\n", .{results.len});

    // List affected items
    std.debug.print("\n📋 Affected Items\n", .{});
    for (0..20) |_| std.debug.print("-", .{});
    std.debug.print("\n", .{});

    for (results) |r| {
        const dir_sym = if (r.direction == .upstream) "↑" else "↓";
        const type_sym = getTypeSymbol(r.neurona_type);

        std.debug.print("  {s} [{s}] {s} (level {d})\n", .{ dir_sym, type_sym, r.neurona_id, r.level });
        std.debug.print("      Title: {s}\n", .{r.title});
        std.debug.print("      Type: {s}\n", .{@tagName(r.neurona_type)});

        if (r.recommendation) |rec| {
            std.debug.print("      Action: {s} (priority {d})\n", .{ @tagName(rec.action), rec.priority });
            std.debug.print("      Reason: {s}\n", .{rec.reason});
        }

        std.debug.print("\n", .{});
    }
}

/// Get symbol for Neurona type
fn getTypeSymbol(t: NeuronaType) []const u8 {
    return switch (t) {
        .test_case => "🧪",
        .issue => "🐛",
        .requirement => "📝",
        .artifact => "📦",
        .feature => "✨",
        .concept => "💡",
        .reference => "📚",
        .lesson => "🎓",
        .state_machine => "🔄",
    };
}

/// JSON output for AI parsing
fn outputJson(results: []const ImpactResult) !void {
    std.debug.print("[", .{});
    for (results, 0..) |r, i| {
        if (i > 0) std.debug.print(",", .{});
        std.debug.print("{{", .{});
        std.debug.print("\"id\":\"{s}\",", .{r.neurona_id});
        std.debug.print("\"type\":\"{s}\",", .{@tagName(r.neurona_type)});
        std.debug.print("\"title\":\"{s}\",", .{r.title});
        std.debug.print("\"level\":{d},", .{r.level});
        std.debug.print("\"direction\":\"{s}\"", .{@tagName(r.direction)});

        if (r.recommendation) |rec| {
            std.debug.print(",\"recommendation\":{{", .{});
            std.debug.print("\"action\":\"{s}\",", .{@tagName(rec.action)});
            std.debug.print("\"priority\":{d},", .{rec.priority});
            std.debug.print("\"reason\":\"{s}\"", .{rec.reason});
            std.debug.print("}}", .{});
        }

        std.debug.print("}}", .{});
    }
    std.debug.print("]\n", .{});
}

// ==================== Tests ====================

test "ImpactConfig with default values" {
    const config = ImpactConfig{
        .id = "test.001",
        .direction = .both,
        .max_depth = 10,
        .include_recommendations = true,
        .json_output = false,
        .neuronas_dir = "neuronas",
    };

    try std.testing.expectEqualStrings("test.001", config.id);
    try std.testing.expectEqual(ImpactDirection.both, config.direction);
    try std.testing.expectEqual(@as(usize, 10), config.max_depth);
}

test "ImpactDirection enum values" {
    try std.testing.expectEqual(ImpactDirection.upstream, ImpactDirection.upstream);
    try std.testing.expectEqual(ImpactDirection.downstream, ImpactDirection.downstream);
    try std.testing.expectEqual(ImpactDirection.both, ImpactDirection.both);
}

test "getTypePriority returns correct priority" {
    try std.testing.expectEqual(@as(u8, 1), getTypePriority(.test_case));
    try std.testing.expectEqual(@as(u8, 2), getTypePriority(.issue));
    try std.testing.expectEqual(@as(u8, 3), getTypePriority(.requirement));
    try std.testing.expectEqual(@as(u8, 6), getTypePriority(.concept));
}

test "generateRecommendation returns correct action" {
    const allocator = std.testing.allocator;

    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);
    neurona.type = .test_case;

    const rec = try generateRecommendation(allocator, neurona, null, 1);
    try std.testing.expect(rec != null);
    defer if (rec) |*r| r.deinit(allocator);

    try std.testing.expectEqual(RecommendationAction.run_test, rec.?.action);
    try std.testing.expectEqual(@as(u8, 1), rec.?.priority);
}
