// File: src/cli/metrics.zig
// The `engram metrics` command for displaying project metrics
// Shows statistics about requirements, tests, issues, and completion
// MIGRATED: Now uses Phase 3 CLI utilities (JsonOutput, HumanOutput)

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Graph = @import("../core/graph.zig").Graph;
const scanNeuronas = @import("../storage/filesystem.zig").scanNeuronas;
const uri_parser = @import("../utils/uri_parser.zig");

// Import Phase 3 CLI utilities
const JsonOutput = @import("output/json.zig").JsonOutput;
const HumanOutput = @import("output/human.zig").HumanOutput;

/// Metrics configuration
pub const MetricsConfig = struct {
    since_date: ?[]const u8 = null,
    last_days: ?u32 = null,
    json_output: bool = false,
    verbose: bool = false,
    cortex_dir: ?[]const u8 = null,
};

/// Metrics report
pub const MetricsReport = struct {
    by_type: std.StringHashMap(usize),
    completion_rate: f64,
    test_coverage: f64,
    open_issues: usize,
    closed_issues: usize,
    average_cycle_time: ?f64,
    total_neuronas: usize,

    pub fn deinit(self: *MetricsReport, _: Allocator) void {
        self.by_type.deinit();
    }
};

pub fn execute(allocator: Allocator, config: MetricsConfig) !void {
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

    var report = try computeMetrics(allocator, neuronas, &graph, config);
    defer report.deinit(allocator);

    if (config.json_output) {
        try outputJson(&report);
    } else {
        try outputReport(&report, config.verbose);
    }
}

fn computeMetrics(allocator: Allocator, neuronas: []const Neurona, _: *Graph, _: ?MetricsConfig) !MetricsReport {
    var report = MetricsReport{
        .by_type = std.StringHashMap(usize).init(allocator),
        .completion_rate = 0.0,
        .test_coverage = 0.0,
        .open_issues = 0,
        .closed_issues = 0,
        .average_cycle_time = null,
        .total_neuronas = neuronas.len,
    };
    errdefer report.by_type.deinit();

    for (neuronas) |*neurona| {
        const type_str = @tagName(neurona.type);
        const count = report.by_type.get(type_str) orelse 0;
        try report.by_type.put(type_str, count + 1);

        switch (neurona.context) {
            .requirement => |ctx| {
                if (std.mem.eql(u8, ctx.status, "implemented")) {
                    report.completion_rate += 1.0;
                }
            },
            .test_case => {
                report.test_coverage += 1.0;
            },
            .issue => |ctx| {
                if (std.mem.eql(u8, ctx.status, "open")) {
                    report.open_issues += 1;
                } else if (std.mem.eql(u8, ctx.status, "closed")) {
                    report.closed_issues += 1;
                }
            },
            else => {},
        }
    }

    const requirement_count = report.by_type.get("requirement") orelse 0;
    if (requirement_count > 0) {
        report.completion_rate = (report.completion_rate / @as(f64, @floatFromInt(requirement_count))) * 100.0;
    }

    const neurona_count = report.by_type.get("neurona") orelse 0;
    if (neurona_count > 0) {
        report.test_coverage = (report.test_coverage / @as(f64, @floatFromInt(neurona_count))) * 100.0;
    }

    return report;
}

fn outputReport(report: *const MetricsReport, _: bool) !void {
    try HumanOutput.printHeader("Metrics Dashboard", "📊");

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("  📦 Total Neuronas: {d}\n\n", .{report.total_neuronas});
    try stdout.flush();

    try HumanOutput.printSubheader("Neuronas by Type", "📊");

    var type_it = report.by_type.iterator();
    while (type_it.next()) |entry| {
        try stdout.print("  {s}: {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        try stdout.flush();
    }
    try stdout.print("\n", .{});
    try stdout.flush();

    const completion_emoji = if (report.completion_rate >= 75.0) "✅" else if (report.completion_rate >= 50.0) "🟡" else "🔴";
    try stdout.print("  📈 Requirement Completion: {d:.1}% {s}\n", .{ report.completion_rate, completion_emoji });
    try stdout.flush();

    const coverage_emoji = if (report.test_coverage >= 75.0) "✅" else if (report.test_coverage >= 50.0) "🟡" else "🔴";
    try stdout.print("  🧪 Test Coverage: {d:.1}% {s}\n", .{ report.test_coverage, coverage_emoji });
    try stdout.flush();

    try stdout.print("  🐛 Open Issues: {d}\n", .{report.open_issues});
    try stdout.print("  ✅ Closed Issues: {d}\n", .{report.closed_issues});
    try stdout.flush();

    if (report.average_cycle_time) |cycle_time| {
        const cycle_days = cycle_time / 86400.0;
        try stdout.print("  ⏱️  Average Cycle Time: {d:.1} days\n", .{cycle_days});
        try stdout.flush();
    }
}

fn outputJson(report: *const MetricsReport) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try JsonOutput.beginObject(stdout);
    try JsonOutput.numberField(stdout, "total_neuronas", report.total_neuronas);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "completion_rate", report.completion_rate);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "test_coverage", report.test_coverage);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "open_issues", report.open_issues);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "closed_issues", report.closed_issues);
    try JsonOutput.separator(stdout, true);

    if (report.average_cycle_time) |cycle_time| {
        const cycle_days = cycle_time / 86400.0;
        try JsonOutput.numberField(stdout, "average_cycle_time_days", cycle_days);
        try JsonOutput.separator(stdout, true);
    }

    try JsonOutput.stringField(stdout, "by_type", "");
    try JsonOutput.beginObject(stdout);

    var first = true;
    var type_it = report.by_type.iterator();
    while (type_it.next()) |entry| {
        if (!first) {
            try JsonOutput.separator(stdout, true);
        }
        first = false;
        try JsonOutput.numberField(stdout, entry.key_ptr.*, entry.value_ptr.*);
    }

    try JsonOutput.endObject(stdout);
    try JsonOutput.endObject(stdout);
    try stdout.flush();
}

test "MetricsConfig with default values" {
    const config = MetricsConfig{
        .since_date = null,
        .last_days = null,
        .json_output = false,
        .verbose = false,
        .cortex_dir = "neuronas",
    };

    try std.testing.expectEqual(@as(?[]const u8, null), config.since_date);
    try std.testing.expectEqual(@as(?u32, null), config.last_days);
    try std.testing.expectEqual(false, config.json_output);
}
