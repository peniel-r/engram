// File: src/cli/impact.zig
// The `engram impact` command for impact analysis on code changes
// Traces upstream and downstream dependencies to identify affected tests, requirements
// MIGRATED: Now uses Phase 3 CLI utilities (JsonOutput, HumanOutput)
// MIGRATED: Now uses lib types via root.zig

const std = @import("std");
const Allocator = std.mem.Allocator;
// Use lib types via root.zig (Phase 4 migration)
const Neurona = @import("../root.zig").Neurona;
const NeuronaType = @import("../root.zig").NeuronaType;
const ConnectionType = @import("../root.zig").ConnectionType;
const Graph = @import("../core/graph.zig").Graph;
const scanNeuronas = @import("../storage/filesystem.zig").scanNeuronas;
const readNeurona = @import("../storage/filesystem.zig").readNeurona;
const uri_parser = @import("../utils/uri_parser.zig");

// Import Phase 3 CLI utilities
const JsonOutput = @import("output/json.zig").JsonOutput;
const HumanOutput = @import("output/human.zig").HumanOutput;

pub const ImpactConfig = struct {
    id: []const u8,
    direction: ImpactDirection = .both,
    max_depth: usize = 10,
    include_recommendations: bool = true,
    json_output: bool = false,
    cortex_dir: ?[]const u8 = null,
};

pub const ImpactDirection = enum {
    upstream,
    downstream,
    both,
};

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

pub const Recommendation = struct {
    action: RecommendationAction,
    priority: u8,
    reason: []const u8,

    pub fn deinit(self: *Recommendation, allocator: Allocator) void {
        allocator.free(self.reason);
    }
};

pub const RecommendationAction = enum {
    run_test,
    review,
    update,
    investigate,
    none,
};

pub fn execute(allocator: Allocator, config: ImpactConfig) !void {
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

    const neuronas = try scanNeuronas(allocator, neuronas_dir);
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

    const results = try analyzeImpact(allocator, &graph, neuronas, config);
    defer {
        for (results) |*r| r.deinit(allocator);
        allocator.free(results);
    }

    if (config.json_output) {
        try outputJson(results);
    } else {
        try outputImpact(results, config);
    }
}

fn analyzeImpact(allocator: Allocator, graph: *Graph, neuronas: []const Neurona, config: ImpactConfig) ![]ImpactResult {
    var result = std.ArrayListUnmanaged(ImpactResult){};
    errdefer {
        for (result.items) |*r| r.deinit(allocator);
        result.deinit(allocator);
    }

    if (config.direction == .upstream or config.direction == .both) {
        try traceImpact(allocator, graph, neuronas, &result, config.id, 0, config.max_depth, .upstream, config.include_recommendations);
    }

    if (config.direction == .downstream or config.direction == .both) {
        try traceImpact(allocator, graph, neuronas, &result, config.id, 0, config.max_depth, .downstream, config.include_recommendations);
    }

    return result.toOwnedSlice(allocator);
}

fn traceImpact(
    allocator: Allocator,
    graph: *Graph,
    neuronas: []const Neurona,
    result: *std.ArrayListUnmanaged(ImpactResult),
    node_id: []const u8,
    level: usize,
    max_depth: usize,
    direction: ImpactDirection,
    include_recommendations: bool,
) !void {
    if (level >= max_depth) return;

    const edges = switch (direction) {
        .upstream => graph.getIncoming(node_id),
        .downstream => graph.getAdjacent(node_id),
        .both => unreachable,
    };

    for (edges) |edge| {
        const neurona = findNeurona(neuronas, edge.target_id) orelse continue;

        const rec = if (include_recommendations)
            generateRecommendation(allocator, neurona, direction) catch null
        else
            null;

        try result.append(allocator, ImpactResult{
            .neurona_id = try allocator.dupe(u8, edge.target_id),
            .neurona_type = neurona.type,
            .title = try allocator.dupe(u8, neurona.title),
            .level = level + 1,
            .direction = direction,
            .connection_type = null,
            .recommendation = rec,
        });

        try traceImpact(allocator, graph, neuronas, result, edge.target_id, level + 1, max_depth, direction, include_recommendations);
    }
}

fn findNeurona(neuronas: []const Neurona, id: []const u8) ?*const Neurona {
    for (neuronas) |*n| {
        if (std.mem.eql(u8, n.id, id)) return n;
    }
    return null;
}

fn generateRecommendation(allocator: Allocator, neurona: *const Neurona, direction: ImpactDirection) !?Recommendation {
    switch (neurona.type) {
        .test_case => {
            if (direction == .upstream) {
                return Recommendation{
                    .action = .run_test,
                    .priority = 1,
                    .reason = try allocator.dupe(u8, "Test may need to be re-run due to upstream changes"),
                };
            }
        },
        .requirement => {
            if (direction == .downstream) {
                return Recommendation{
                    .action = .review,
                    .priority = 2,
                    .reason = try allocator.dupe(u8, "Requirement may need review for completeness"),
                };
            }
        },
        .issue => {
            if (direction == .downstream) {
                return Recommendation{
                    .action = .investigate,
                    .priority = 3,
                    .reason = try allocator.dupe(u8, "Issue may be affected by changes"),
                };
            }
        },
        else => {},
    }
    return null;
}

fn outputImpact(results: []const ImpactResult, config: ImpactConfig) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try HumanOutput.printHeader("Impact Analysis", "🎯");
    try stdout.print("  ID: {s}\n", .{config.id});
    try stdout.flush();

    if (results.len == 0) {
        try HumanOutput.printWarning("No affected items found.");
        return;
    }

    var upstream_count: usize = 0;
    var downstream_count: usize = 0;

    for (results) |r| {
        if (r.direction == .upstream) upstream_count += 1 else downstream_count += 1;
    }

    try HumanOutput.printSubheader("Summary", "📊");
    try stdout.print("  Upstream dependencies: {d}\n", .{upstream_count});
    try stdout.print("  Downstream dependents: {d}\n", .{downstream_count});
    try stdout.print("  Total affected: {d}\n", .{results.len});
    try stdout.flush();

    try HumanOutput.printSubheader("Affected Items", "📋");

    for (results) |r| {
        const dir_sym = if (r.direction == .upstream) "↑" else "↓";
        const type_sym = getTypeSymbol(r.neurona_type);

        try stdout.print("  {s} [{s}] {s} (level {d})\n", .{ dir_sym, type_sym, r.neurona_id, r.level });
        try stdout.print("      Title: {s}\n", .{r.title});
        try stdout.print("      Type: {s}\n", .{@tagName(r.neurona_type)});
        try stdout.flush();

        if (r.recommendation) |rec| {
            try stdout.print("      Action: {s} (priority {d})\n", .{ @tagName(rec.action), rec.priority });
            try stdout.print("      Reason: {s}\n", .{rec.reason});
            try stdout.flush();
        }

        try stdout.print("\n", .{});
    }
}

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

fn outputJson(results: []const ImpactResult) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try JsonOutput.beginArray(stdout);
    for (results, 0..) |r, i| {
        if (i > 0) {
            try JsonOutput.separator(stdout, true);
        }
        try JsonOutput.beginObject(stdout);
        try JsonOutput.stringField(stdout, "id", r.neurona_id);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.enumField(stdout, "type", r.neurona_type);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.stringField(stdout, "title", r.title);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.numberField(stdout, "level", r.level);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.enumField(stdout, "direction", r.direction);
        try JsonOutput.separator(stdout, true);

        if (r.recommendation) |rec| {
            try JsonOutput.stringField(stdout, "recommendation", "");
            try JsonOutput.beginObject(stdout);
            try JsonOutput.enumField(stdout, "action", rec.action);
            try JsonOutput.separator(stdout, true);
            try JsonOutput.numberField(stdout, "priority", rec.priority);
            try JsonOutput.separator(stdout, true);
            try JsonOutput.stringField(stdout, "reason", rec.reason);
            try JsonOutput.endObject(stdout);
            try JsonOutput.separator(stdout, true);
        }

        try JsonOutput.endObject(stdout);
    }
    try JsonOutput.endArray(stdout);
    try stdout.flush();
}

test "ImpactConfig with default values" {
    const config = ImpactConfig{
        .id = "test.001",
        .direction = .both,
        .max_depth = 10,
        .include_recommendations = true,
        .json_output = false,
        .cortex_dir = null,
    };

    try std.testing.expectEqualStrings("test.001", config.id);
    try std.testing.expectEqual(ImpactDirection.both, config.direction);
}
