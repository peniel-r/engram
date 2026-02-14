// File: src/cli/release_status.zig
// The `engram release-status` command for release readiness checks
// Validates requirements coverage, test status, blocking issues
// MIGRATED: Now uses Phase 3 CLI utilities (JsonOutput, HumanOutput)

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const ConnectionType = @import("../core/neurona.zig").ConnectionType;
const Graph = @import("../core/graph.zig").Graph;
const scanNeuronas = @import("../storage/filesystem.zig").scanNeuronas;
const uri_parser = @import("../utils/uri_parser.zig");

// Import Phase 3 CLI utilities
const JsonOutput = @import("output/json.zig").JsonOutput;
const HumanOutput = @import("output/human.zig").HumanOutput;

/// Release status configuration
pub const ReleaseStatusConfig = struct {
    requirements_filter: ?[]const u8 = null,
    include_tests: bool = true,
    include_issues: bool = true,
    json_output: bool = false,
    verbose: bool = false,
    cortex_dir: ?[]const u8 = null,
};

/// Release status report
pub const ReleaseStatus = struct {
    requirements: RequirementStatus,
    tests: TestStatus,
    issues: IssueStatus,
    completion: f64,
    recommendations: std.ArrayListUnmanaged(Recommendation),

    pub fn deinit(self: *ReleaseStatus, allocator: Allocator) void {
        self.requirements.deinit(allocator);
        self.tests.deinit(allocator);
        self.issues.deinit(allocator);
        for (self.recommendations.items) |*rec| rec.deinit(allocator);
        self.recommendations.deinit(allocator);
    }
};

/// Requirement status summary
pub const RequirementStatus = struct {
    total: usize,
    implemented: usize,
    tested: usize,
    blocked: usize,
    not_started: usize,
    details: std.ArrayListUnmanaged(RequirementDetail),

    pub fn deinit(self: *RequirementStatus, allocator: Allocator) void {
        for (self.details.items) |*d| d.deinit(allocator);
        self.details.deinit(allocator);
    }
};

/// Individual requirement detail
pub const RequirementDetail = struct {
    id: []const u8,
    title: []const u8,
    status: RequirementStatusEnum,
    blocking_issues: std.ArrayListUnmanaged([]const u8),

    pub fn deinit(self: *RequirementDetail, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.title);
        for (self.blocking_issues.items) |issue| allocator.free(issue);
        self.blocking_issues.deinit(allocator);
    }
};

pub const RequirementStatusEnum = enum {
    completed, // Has implementing artifact and passing tests
    partial, // Has implementing artifact but no/failing tests
    not_started, // No implementing artifact
    blocked, // Has blocking issues
};

/// Test status summary
pub const TestStatus = struct {
    total: usize,
    passing: usize,
    failing: usize,
    not_run: usize,
    details: std.ArrayListUnmanaged(TestDetail),

    pub fn deinit(self: *TestStatus, allocator: Allocator) void {
        for (self.details.items) |*d| d.deinit(allocator);
        self.details.deinit(allocator);
    }
};

/// Individual test detail
pub const TestDetail = struct {
    id: []const u8,
    title: []const u8,
    status: []const u8,

    pub fn deinit(self: *TestDetail, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.title);
        allocator.free(self.status);
    }
};

/// Issue status summary
pub const IssueStatus = struct {
    total: usize,
    open: usize,
    resolved: usize,
    blocking: usize,
    details: std.ArrayListUnmanaged(IssueDetail),

    pub fn deinit(self: *IssueStatus, allocator: Allocator) void {
        for (self.details.items) |*d| d.deinit(allocator);
        self.details.deinit(allocator);
    }
};

/// Individual issue detail
pub const IssueDetail = struct {
    id: []const u8,
    title: []const u8,
    blocks: std.ArrayListUnmanaged([]const u8),

    pub fn deinit(self: *IssueDetail, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.title);
        for (self.blocks.items) |block| allocator.free(block);
        self.blocks.deinit(allocator);
    }
};

/// Release recommendation
pub const Recommendation = struct {
    priority: u8,
    action: []const u8,
    description: []const u8,

    pub fn deinit(self: *Recommendation, allocator: Allocator) void {
        allocator.free(self.action);
        allocator.free(self.description);
    }
};

/// Main command handler
pub fn execute(allocator: Allocator, config: ReleaseStatusConfig) !void {
    // Determine neuronas directory
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

    // Step 1: Load all Neuronas and build graph
    const neuronas = try scanNeuronas(allocator, neuronas_dir);
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

    // Step 2: Compute release status
    var status = try computeReleaseStatus(allocator, neuronas, &graph);
    defer status.deinit(allocator);

    // Step 3: Output
    if (config.json_output) {
        try outputJson(&status);
    } else {
        try outputReport(&status, config.verbose);
    }
}

/// Compute release readiness status
pub fn computeReleaseStatus(allocator: Allocator, neuronas: []const Neurona, graph: *Graph) !ReleaseStatus {
    var status = ReleaseStatus{
        .requirements = undefined,
        .tests = undefined,
        .issues = undefined,
        .completion = 0.0,
        .recommendations = std.ArrayListUnmanaged(Recommendation){},
    };
    errdefer status.recommendations.deinit(allocator);

    // Build type maps
    var req_map = std.StringHashMap(*const Neurona).init(allocator);
    defer req_map.deinit();
    var test_map = std.StringHashMap(*const Neurona).init(allocator);
    defer test_map.deinit();
    var issue_map = std.StringHashMap(*const Neurona).init(allocator);
    defer issue_map.deinit();
    var all_map = std.StringHashMap(*const Neurona).init(allocator);
    defer all_map.deinit();

    for (neuronas) |*neurona| {
        switch (neurona.type) {
            .requirement => try req_map.put(neurona.id, neurona),
            .test_case => try test_map.put(neurona.id, neurona),
            .issue => try issue_map.put(neurona.id, neurona),
            else => {},
        }
        try all_map.put(neurona.id, neurona);
    }

    // Compute requirement status
    status.requirements = try analyzeRequirements(allocator, req_map, all_map, graph);

    // Compute test status
    status.tests = try analyzeTests(allocator, test_map);

    // Compute issue status
    status.issues = try analyzeIssues(allocator, issue_map, graph);

    // Compute completion percentage
    if (status.requirements.total > 0) {
        const completed_count = status.requirements.tested; // Tested requirements are considered completed
        status.completion = @as(f64, @floatFromInt(completed_count)) / @as(f64, @floatFromInt(status.requirements.total)) * 100.0;
    }

    // Generate recommendations
    try generateRecommendations(allocator, &status);

    return status;
}

/// Analyze requirement status
fn analyzeRequirements(allocator: Allocator, req_map: std.StringHashMap(*const Neurona), all_map: std.StringHashMap(*const Neurona), graph: *Graph) !RequirementStatus {
    var result = RequirementStatus{
        .total = req_map.count(),
        .implemented = 0,
        .tested = 0,
        .blocked = 0,
        .not_started = 0,
        .details = std.ArrayListUnmanaged(RequirementDetail){},
    };
    errdefer {
        for (result.details.items) |*d| d.deinit(allocator);
        result.details.deinit(allocator);
    }

    var it = req_map.iterator();
    while (it.next()) |entry| {
        const req = entry.value_ptr.*;

        // Check for implementing artifacts (outgoing "implemented_by" connections)
        const adj = graph.getAdjacent(req.id);
        var has_implementer = false;
        for (adj) |edge| {
            const target_req = all_map.get(edge.target_id) orelse continue;
            if (target_req.type == .artifact) {
                has_implementer = true;
                break;
            }
        }

        // Check for tests (outgoing "validated_by" connections)
        var has_test = false;
        for (adj) |edge| {
            const target_req = all_map.get(edge.target_id) orelse continue;
            if (target_req.type == .test_case) {
                has_test = true;
                break;
            }
        }

        // Check for blocking issues (incoming "blocks" connections)
        var blocking_issues = std.ArrayListUnmanaged([]const u8){};
        const incoming = graph.getIncoming(req.id);
        for (incoming) |edge| {
            // Check if it's an issue
            if (all_map.get(edge.target_id)) |issue| {
                if (issue.type == .issue) {
                    try blocking_issues.append(allocator, try allocator.dupe(u8, edge.target_id));
                }
            }
        }
        defer {
            for (blocking_issues.items) |issue| allocator.free(issue);
            blocking_issues.deinit(allocator);
        }

        // Determine status
        const req_status: RequirementStatusEnum = if (blocking_issues.items.len > 0)
            .blocked
        else if (has_implementer and has_test)
            .completed
        else if (has_implementer)
            .partial
        else
            .not_started;

        // Update counts
        switch (req_status) {
            .completed => {
                result.implemented += 1;
                result.tested += 1;
            },
            .partial => result.implemented += 1,
            .not_started => result.not_started += 1,
            .blocked => result.blocked += 1,
        }

        // Create detail
        var detail = RequirementDetail{
            .id = try allocator.dupe(u8, req.id),
            .title = try allocator.dupe(u8, req.title),
            .status = req_status,
            .blocking_issues = std.ArrayListUnmanaged([]const u8){},
        };
        for (blocking_issues.items) |issue| {
            try detail.blocking_issues.append(allocator, try allocator.dupe(u8, issue));
        }
        try result.details.append(allocator, detail);
    }

    return result;
}

/// Analyze test status
fn analyzeTests(allocator: Allocator, test_map: std.StringHashMap(*const Neurona)) !TestStatus {
    var result = TestStatus{
        .total = test_map.count(),
        .passing = 0,
        .failing = 0,
        .not_run = 0,
        .details = std.ArrayListUnmanaged(TestDetail){},
    };
    errdefer {
        for (result.details.items) |*d| d.deinit(allocator);
        result.details.deinit(allocator);
    }

    var it = test_map.iterator();
    while (it.next()) |entry| {
        const tc = entry.value_ptr.*;

        // Get test status from context
        var test_status: []const u8 = "unknown";
        switch (tc.context) {
            .test_case => |ctx| {
                test_status = ctx.status;
                if (std.mem.eql(u8, ctx.status, "passing")) {
                    result.passing += 1;
                } else if (std.mem.eql(u8, ctx.status, "failing")) {
                    result.failing += 1;
                } else {
                    result.not_run += 1;
                }
            },
            else => {
                result.not_run += 1;
            },
        }

        // Create detail
        const detail = TestDetail{
            .id = try allocator.dupe(u8, tc.id),
            .title = try allocator.dupe(u8, tc.title),
            .status = try allocator.dupe(u8, test_status),
        };
        try result.details.append(allocator, detail);
    }

    return result;
}

/// Analyze issue status
fn analyzeIssues(allocator: Allocator, issue_map: std.StringHashMap(*const Neurona), graph: *Graph) !IssueStatus {
    var result = IssueStatus{
        .total = issue_map.count(),
        .open = 0,
        .resolved = 0,
        .blocking = 0,
        .details = std.ArrayListUnmanaged(IssueDetail){},
    };
    errdefer {
        for (result.details.items) |*d| d.deinit(allocator);
        result.details.deinit(allocator);
    }

    var it = issue_map.iterator();
    while (it.next()) |entry| {
        const issue = entry.value_ptr.*;

        // Check if issue blocks anything (outgoing "blocks" connections)
        const adj = graph.getAdjacent(issue.id);
        var blocks = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (blocks.items) |block| allocator.free(block);
            blocks.deinit(allocator);
        }

        var is_blocking = false;
        for (adj) |edge| {
            try blocks.append(allocator, try allocator.dupe(u8, edge.target_id));
            is_blocking = true;
        }

        if (is_blocking) {
            result.blocking += 1;
            result.open += 1; // Blocking issues are assumed open
        } else {
            result.resolved += 1;
        }

        // Create detail
        var detail = IssueDetail{
            .id = try allocator.dupe(u8, issue.id),
            .title = try allocator.dupe(u8, issue.title),
            .blocks = std.ArrayListUnmanaged([]const u8){},
        };
        for (blocks.items) |block| {
            try detail.blocks.append(allocator, try allocator.dupe(u8, block));
        }
        try result.details.append(allocator, detail);
    }

    return result;
}

/// Generate release recommendations
fn generateRecommendations(allocator: Allocator, status: *ReleaseStatus) !void {
    // Check for blocked requirements
    if (status.requirements.blocked > 0) {
        try status.recommendations.append(allocator, Recommendation{
            .priority = 1,
            .action = try allocator.dupe(u8, "Resolve blocking issues"),
            .description = try std.fmt.allocPrint(allocator, "{d} requirements are blocked by issues", .{status.requirements.blocked}),
        });
    }

    // Check for untested requirements
    const untested = status.requirements.implemented - status.requirements.tested;
    if (untested > 0) {
        try status.recommendations.append(allocator, Recommendation{
            .priority = 2,
            .action = try allocator.dupe(u8, "Add tests for requirements"),
            .description = try std.fmt.allocPrint(allocator, "{d} implemented requirements lack tests", .{untested}),
        });
    }

    // Check for failing tests
    if (status.tests.failing > 0) {
        try status.recommendations.append(allocator, Recommendation{
            .priority = 1,
            .action = try allocator.dupe(u8, "Fix failing tests"),
            .description = try std.fmt.allocPrint(allocator, "{d} tests are failing", .{status.tests.failing}),
        });
    }

    // Check for not started requirements
    if (status.requirements.not_started > 0) {
        try status.recommendations.append(allocator, Recommendation{
            .priority = 3,
            .action = try allocator.dupe(u8, "Implement remaining requirements"),
            .description = try std.fmt.allocPrint(allocator, "{d} requirements have not been started", .{status.requirements.not_started}),
        });
    }
}

/// Output release status report
fn outputReport(status: *const ReleaseStatus, verbose: bool) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("\n🚀 Release Status Report\n", .{});
    for (0..50) |_| try stdout.print("=", .{});
    try stdout.print("\n", .{});

    // Completion percentage
    const completion_str = if (status.completion >= 100.0)
        "100% ✅"
    else if (status.completion >= 75.0)
        try std.fmt.allocPrint(std.heap.page_allocator, "{d:.1}% 🟢", .{status.completion})
    else if (status.completion >= 50.0)
        try std.fmt.allocPrint(std.heap.page_allocator, "{d:.1}% 🟡", .{status.completion})
    else
        try std.fmt.allocPrint(std.heap.page_allocator, "{d:.1}% 🔴", .{status.completion});

    defer if (status.completion < 100.0 and status.completion > 0.0) std.heap.page_allocator.free(completion_str);

    try stdout.print("\n📊 Overall Completion: {s}\n\n", .{completion_str});

    // Requirements
    try stdout.print("📝 Requirements\n", .{});
    for (0..20) |_| try stdout.print("-", .{});
    try stdout.print("\n", .{});
    try stdout.print("  Total: {d}\n", .{status.requirements.total});
    try stdout.print("  Completed: {d}\n", .{status.requirements.tested});
    try stdout.print("  Partial: {d}\n", .{status.requirements.implemented - status.requirements.tested});
    try stdout.print("  Not Started: {d}\n", .{status.requirements.not_started});
    try stdout.print("  Blocked: {d}\n", .{status.requirements.blocked});
    try stdout.print("\n", .{});

    if (verbose) {
        for (status.requirements.details.items) |detail| {
            const status_sym = switch (detail.status) {
                .completed => "✓",
                .partial => "○",
                .not_started => "○",
                .blocked => "⚠",
            };
            try stdout.print("  {s} {s}: {s}\n", .{ status_sym, detail.id, detail.title });
            if (detail.blocking_issues.items.len > 0) {
                try stdout.print("      Blocked by: ", .{});
                for (detail.blocking_issues.items, 0..) |issue, i| {
                    if (i > 0) try stdout.print(", ", .{});
                    try stdout.print("{s}", .{issue});
                }
                try stdout.print("\n", .{});
            }
        }
        try stdout.print("\n", .{});
    }

    // Tests
    try stdout.print("🧪 Tests\n", .{});
    for (0..20) |_| try stdout.print("-", .{});
    try stdout.print("\n", .{});
    try stdout.print("  Total: {d}\n", .{status.tests.total});
    try stdout.print("  Passing: {d}\n", .{status.tests.passing});
    try stdout.print("  Failing: {d}\n", .{status.tests.failing});
    try stdout.print("  Not Run: {d}\n", .{status.tests.not_run});
    try stdout.print("\n", .{});

    if (verbose and status.tests.failing > 0) {
        try stdout.print("  Failing Tests:\n", .{});
        for (status.tests.details.items) |detail| {
            if (std.mem.eql(u8, detail.status, "failing")) {
                try stdout.print("    - {s}: {s}\n", .{ detail.id, detail.title });
            }
        }
        try stdout.print("\n", .{});
    }

    // Issues
    try stdout.print("🐛 Issues\n", .{});
    for (0..20) |_| try stdout.print("-", .{});
    try stdout.print("\n", .{});
    try stdout.print("  Total: {d}\n", .{status.issues.total});
    try stdout.print("  Blocking: {d}\n", .{status.issues.blocking});
    try stdout.print("  Resolved: {d}\n", .{status.issues.resolved});
    try stdout.print("\n", .{});

    // Recommendations
    if (status.recommendations.items.len > 0) {
        try stdout.print("💡 Recommendations\n", .{});
        for (0..20) |_| try stdout.print("-", .{});
        try stdout.print("\n", .{});

        for (status.recommendations.items) |rec| {
            const priority_emoji = switch (rec.priority) {
                1 => "🔴",
                2 => "🟠",
                3 => "🟡",
                else => "⚪",
            };
            try stdout.print("  {s} [{d}] {s}\n", .{ priority_emoji, rec.priority, rec.action });
            try stdout.print("      {s}\n", .{rec.description});
            try stdout.print("\n", .{});
        }
    }
    try stdout.flush();
}

/// JSON output for AI parsing
fn outputJson(status: *const ReleaseStatus) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try JsonOutput.beginObject(stdout);
    try JsonOutput.numberField(stdout, "completion", status.completion);
    try JsonOutput.separator(stdout, true);

    // Requirements
    try stdout.print("\"requirements\":{{", .{});
    try JsonOutput.numberField(stdout, "total", status.requirements.total);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "implemented", status.requirements.implemented);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "tested", status.requirements.tested);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "blocked", status.requirements.blocked);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "not_started", status.requirements.not_started);
    try stdout.writeAll("}");
    try JsonOutput.separator(stdout, true);

    // Tests
    try stdout.print("\"tests\":{{", .{});
    try JsonOutput.numberField(stdout, "total", status.tests.total);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "passing", status.tests.passing);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "failing", status.tests.failing);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "not_run", status.tests.not_run);
    try stdout.writeAll("}");
    try JsonOutput.separator(stdout, true);

    // Issues
    try stdout.print("\"issues\":{{", .{});
    try JsonOutput.numberField(stdout, "total", status.issues.total);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "blocking", status.issues.blocking);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "resolved", status.issues.resolved);
    try stdout.writeAll("}");

    try JsonOutput.endObject(stdout);
    try stdout.print("\n", .{});
    try stdout.flush();
}

// ==================== Tests ====================

test "ReleaseStatusConfig creates correctly" {
    const config = ReleaseStatusConfig{
        .requirements_filter = null,
        .include_tests = true,
        .include_issues = true,
        .json_output = false,
        .verbose = false,
        .cortex_dir = "neuronas",
    };

    try std.testing.expectEqual(@as(?[]const u8, null), config.requirements_filter);
    try std.testing.expectEqual(true, config.include_tests);
}

test "RequirementStatusEnum values" {
    try std.testing.expectEqual(RequirementStatusEnum.completed, RequirementStatusEnum.completed);
    try std.testing.expectEqual(RequirementStatusEnum.partial, RequirementStatusEnum.partial);
    try std.testing.expectEqual(RequirementStatusEnum.not_started, RequirementStatusEnum.not_started);
    try std.testing.expectEqual(RequirementStatusEnum.blocked, RequirementStatusEnum.blocked);
}
