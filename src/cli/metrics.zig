// File: src/cli/metrics.zig
// The `engram metrics` command for displaying project metrics
// Shows statistics about requirements, tests, issues, and completion

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Graph = @import("../core/graph.zig").Graph;
const scanNeuronas = @import("../storage/filesystem.zig").scanNeuronas;
const uri_parser = @import("../utils/uri_parser.zig");

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

/// Main command handler
pub fn execute(allocator: Allocator, config: MetricsConfig) !void {
    // Determine neuronas directory
    const cortex_dir = uri_parser.findCortexDir(allocator, config.cortex_dir) catch |err| {
        if (err == error.CortexNotFound) {
            std.debug.print("Error: No cortex found in current directory or within 3 directory levels.\n", .{});
            std.debug.print("\nHint: Navigate to a cortex directory or use --cortex <path> to specify location.\n", .{});
            std.debug.print("Run 'engram init <name>' to create a new cortex.\n", .{});
            std.process.exit(1);
        }
        return err;
    };
    defer if (config.cortex_dir == null) allocator.free(cortex_dir);

    const neuronas_dir = try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex_dir});
    defer allocator.free(neuronas_dir);

    // Step 1: Load all Neuronas
    const neuronas = try scanNeuronas(allocator, neuronas_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Step 2: Build graph for relationship analysis
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

    // Step 3: Compute metrics
    var report = try computeMetrics(allocator, neuronas, &graph, config);
    defer report.deinit(allocator);

    // Step 4: Output
    if (config.json_output) {
        try outputJson(&report);
    } else {
        try outputReport(&report, config.verbose);
    }
}

/// Compute all metrics
fn computeMetrics(allocator: Allocator, neuronas: []const Neurona, graph: *Graph, _: ?MetricsConfig) !MetricsReport {
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

    // Count by type
    for (neuronas) |*neurona| {
        const type_name = @tagName(neurona.type);
        const entry = try report.by_type.getOrPut(type_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        }
        entry.value_ptr.* += 1;
    }

    // Count requirements and tests for completion rate
    var total_requirements: usize = 0;
    var completed_requirements: usize = 0;
    var total_tests: usize = 0;
    var passing_tests: usize = 0;
    var total_cycle_time: f64 = 0.0;
    var resolved_issues: usize = 0;

    for (neuronas) |*neurona| {
        switch (neurona.type) {
            .requirement => {
                total_requirements += 1;

                // Check if requirement has tests (validates connections)
                const adj = graph.getAdjacent(neurona.id);
                for (adj) |edge| {
                    // Find target neurona
                    var found_test = false;
                    for (neuronas) |*n| {
                        if (std.mem.eql(u8, n.id, edge.target_id) and n.type == .test_case) {
                            found_test = true;
                            // Check test status
                            if (n.context == .test_case) {
                                const test_ctx = n.context.test_case;
                                if (std.mem.eql(u8, test_ctx.status, "passing")) {
                                    completed_requirements += 1;
                                }
                            }
                            break;
                        }
                    }
                    if (found_test) break;
                }
            },
            .test_case => {
                total_tests += 1;
                if (neurona.context == .test_case) {
                    const test_ctx = neurona.context.test_case;
                    if (std.mem.eql(u8, test_ctx.status, "passing")) {
                        passing_tests += 1;
                    }
                }
            },
            .issue => {
                if (neurona.context == .issue) {
                    const issue_ctx = neurona.context.issue;
                    if (std.mem.eql(u8, issue_ctx.status, "open") or std.mem.eql(u8, issue_ctx.status, "in_progress")) {
                        report.open_issues += 1;
                    } else {
                        report.closed_issues += 1;

                        // Calculate cycle time if resolved/closed date available
                        if (issue_ctx.resolved) |resolved_date| {
                            if (parseDate(resolved_date)) |resolved| {
                                if (parseDate(issue_ctx.created)) |created| {
                                    const cycle_seconds = @as(f64, @floatFromInt(resolved - created));
                                    total_cycle_time += cycle_seconds;
                                    resolved_issues += 1;
                                } else |_| {}
                            } else |_| {}
                        }
                    }
                }
            },
            else => {},
        }
    }

    // Calculate rates
    if (total_requirements > 0) {
        report.completion_rate = @as(f64, @floatFromInt(completed_requirements)) / @as(f64, @floatFromInt(total_requirements)) * 100.0;
    }

    if (total_tests > 0) {
        report.test_coverage = @as(f64, @floatFromInt(passing_tests)) / @as(f64, @floatFromInt(total_tests)) * 100.0;
    }

    if (resolved_issues > 0) {
        report.average_cycle_time = total_cycle_time / @as(f64, @floatFromInt(resolved_issues));
    }

    return report;
}

/// Parse date string to Unix timestamp (simplified)
fn parseDate(date_str: []const u8) !i64 {
    // Expected format: YYYY-MM-DD
    if (date_str.len < 10) return error.InvalidFormat;

    const year_str = date_str[0..4];
    const month_str = date_str[5..7];
    const day_str = date_str[8..10];

    const year = try std.fmt.parseInt(i32, year_str, 10);
    const month = try std.fmt.parseInt(i32, month_str, 10);
    const day = try std.fmt.parseInt(i32, day_str, 10);

    // Simplified date calculation (approximate)
    // For production, use proper datetime library
    const days_since_epoch = (year - 1970) * 365 + (month - 1) * 30 + (day - 1);
    return days_since_epoch * 86400;
}

/// Output human-readable report
fn outputReport(report: *const MetricsReport, _: bool) !void {
    std.debug.print("\n📊 Metrics Dashboard\n", .{});
    for (0..50) |_| std.debug.print("=", .{});
    std.debug.print("\n", .{});

    // Total Neuronas
    std.debug.print("📦 Total Neuronas: {d}\n\n", .{report.total_neuronas});

    // By type
    std.debug.print("📊 Neuronas by Type\n", .{});
    for (0..25) |_| std.debug.print("-", .{});
    std.debug.print("\n", .{});

    var type_it = report.by_type.iterator();
    while (type_it.next()) |entry| {
        std.debug.print("  {s}: {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    std.debug.print("\n", .{});

    // Completion rate
    const completion_emoji = if (report.completion_rate >= 75.0) "✅" else if (report.completion_rate >= 50.0) "🟡" else "🔴";
    std.debug.print("📈 Requirement Completion: {d:.1}% {s}\n", .{ report.completion_rate, completion_emoji });

    // Test coverage
    const coverage_emoji = if (report.test_coverage >= 75.0) "✅" else if (report.test_coverage >= 50.0) "🟡" else "🔴";
    std.debug.print("🧪 Test Coverage: {d:.1}% {s}\n", .{ report.test_coverage, coverage_emoji });

    // Issue status
    std.debug.print("🐛 Open Issues: {d}\n", .{report.open_issues});
    std.debug.print("✅ Closed Issues: {d}\n", .{report.closed_issues});

    // Average cycle time
    if (report.average_cycle_time) |cycle_time| {
        const cycle_days = cycle_time / 86400.0;
        std.debug.print("⏱️  Average Cycle Time: {d:.1} days\n", .{cycle_days});
    }

    std.debug.print("\n", .{});
}

/// JSON output for AI parsing
fn outputJson(report: *const MetricsReport) !void {
    std.debug.print("{{", .{});
    std.debug.print("\"total_neuronas\":{d},", .{report.total_neuronas});
    std.debug.print("\"completion_rate\":{d:.1},", .{report.completion_rate});
    std.debug.print("\"test_coverage\":{d:.1},", .{report.test_coverage});
    std.debug.print("\"open_issues\":{d},", .{report.open_issues});
    std.debug.print("\"closed_issues\":{d},", .{report.closed_issues});
    if (report.average_cycle_time) |cycle_time| {
        const cycle_days = cycle_time / 86400.0;
        std.debug.print("\"average_cycle_time_days\":{d:.1},", .{cycle_days});
    }
    std.debug.print("\"by_type\":{{", .{});

    var first = true;
    var type_it = report.by_type.iterator();
    while (type_it.next()) |entry| {
        if (!first) {
            std.debug.print(",", .{});
        }
        first = false;
        std.debug.print("\"{s}\":{d}", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    std.debug.print("}}", .{});
    std.debug.print("}}\n", .{});
}

// ==================== Tests ====================

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

test "MetricsReport initializes correctly" {
    const allocator = std.testing.allocator;

    var report = MetricsReport{
        .by_type = std.StringHashMap(usize).init(allocator),
        .completion_rate = 0.0,
        .test_coverage = 0.0,
        .open_issues = 0,
        .closed_issues = 0,
        .average_cycle_time = null,
        .total_neuronas = 0,
    };
    defer report.by_type.deinit();

    try std.testing.expectEqual(@as(usize, 0), report.total_neuronas);
    try std.testing.expectEqual(@as(?f64, null), report.average_cycle_time);
}

test "parseDate handles valid date" {
    const result = try parseDate("2026-01-30");
    try std.testing.expect(result > 0);
}

test "parseDate rejects invalid format" {
    const result = parseDate("invalid");
    try std.testing.expectError(error.InvalidFormat, result);
}
