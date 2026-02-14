//! ALM Integration Example for Engram Library
//!
//! This example demonstrates Application Lifecycle Management (ALM) workflows:
//! - Creating requirements, test cases, and issues
//! - Linking requirements to tests
//! - Tracking implementation status
//!
//! Run with: zig run examples/alm_integration.zig

const std = @import("std");
const Engram = @import("Engram");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Engram ALM Integration Example ===\n\n", .{});

    // Create a requirement
    var requirement = try Engram.Neurona.init(allocator);
    defer requirement.deinit(allocator);

    requirement.id = try allocator.dupe(u8, "req.auth.oauth2");
    requirement.title = try allocator.dupe(u8, "OAuth 2.0 Authentication");
    requirement.type = .requirement;
    requirement.language = try allocator.dupe(u8, "en");

    // Set requirement context (Tier 3)
    requirement.context = .{
        .requirement = .{
            .status = try allocator.dupe(u8, "approved"),
            .verification_method = try allocator.dupe(u8, "test"),
            .priority = 1,
            .assignee = try allocator.dupe(u8, "alice"),
            .effort_points = 8,
            .sprint = try allocator.dupe(u8, "Sprint 5"),
        },
    };

    std.debug.print("Created Requirement:\n", .{});
    std.debug.print("  ID: {s}\n", .{requirement.id});
    std.debug.print("  Title: {s}\n", .{requirement.title});
    switch (requirement.context) {
        .requirement => |ctx| {
            std.debug.print("  Status: {s}\n", .{ctx.status});
            std.debug.print("  Priority: {d}\n", .{ctx.priority});
            std.debug.print("  Assignee: {s}\n", .{ctx.assignee.?});
            std.debug.print("  Verification: {s}\n", .{ctx.verification_method});
        },
        else => {},
    }
    std.debug.print("\n", .{});

    // Create a test case that validates the requirement
    var test_case = try Engram.Neurona.init(allocator);
    defer test_case.deinit(allocator);

    test_case.id = try allocator.dupe(u8, "test.auth.oauth2");
    test_case.title = try allocator.dupe(u8, "OAuth 2.0 Authentication Test");
    test_case.type = .test_case;
    test_case.language = try allocator.dupe(u8, "en");

    // Set test case context
    test_case.context = .{
        .test_case = .{
            .framework = try allocator.dupe(u8, "ztest"),
            .test_file = try allocator.dupe(u8, "tests/auth/oauth2_test.zig"),
            .status = try allocator.dupe(u8, "pending"),
            .priority = 1,
            .assignee = try allocator.dupe(u8, "bob"),
            .duration = null,
            .last_run = null,
        },
    };

    // Link test to requirement (validates relationship)
    const validates_conn = Engram.Connection{
        .target_id = try allocator.dupe(u8, "req.auth.oauth2"),
        .connection_type = .validates,
        .weight = 100,
    };
    try test_case.addConnection(allocator, validates_conn);

    std.debug.print("Created Test Case:\n", .{});
    std.debug.print("  ID: {s}\n", .{test_case.id});
    std.debug.print("  Title: {s}\n", .{test_case.title});
    switch (test_case.context) {
        .test_case => |ctx| {
            std.debug.print("  Status: {s}\n", .{ctx.status});
            std.debug.print("  Framework: {s}\n", .{ctx.framework});
            std.debug.print("  Test File: {s}\n", .{ctx.test_file.?});
        },
        else => {},
    }
    std.debug.print("  Validates: req.auth.oauth2\n\n", .{});

    // Create an issue blocking the requirement
    var issue = try Engram.Neurona.init(allocator);
    defer issue.deinit(allocator);

    issue.id = try allocator.dupe(u8, "issue.auth.token-expiry");
    issue.title = try allocator.dupe(u8, "Token expiry handling not implemented");
    issue.type = .issue;
    issue.language = try allocator.dupe(u8, "en");

    // Set issue context
    issue.context = .{
        .issue = .{
            .status = try allocator.dupe(u8, "open"),
            .priority = 2,
            .assignee = try allocator.dupe(u8, "charlie"),
            .created = try allocator.dupe(u8, "2026-02-13T10:00:00Z"),
            .resolved = null,
            .closed = null,
            .blocked_by = .{},
            .related_to = .{},
        },
    };

    // Link issue as blocking the requirement
    const blocks_conn = Engram.Connection{
        .target_id = try allocator.dupe(u8, "req.auth.oauth2"),
        .connection_type = .blocks,
        .weight = 80,
    };
    try issue.addConnection(allocator, blocks_conn);

    std.debug.print("Created Issue:\n", .{});
    std.debug.print("  ID: {s}\n", .{issue.id});
    std.debug.print("  Title: {s}\n", .{issue.title});
    switch (issue.context) {
        .issue => |ctx| {
            std.debug.print("  Status: {s}\n", .{ctx.status});
            std.debug.print("  Priority: {d}\n", .{ctx.priority});
            std.debug.print("  Assignee: {s}\n", .{ctx.assignee.?});
        },
        else => {},
    }
    std.debug.print("  Blocks: req.auth.oauth2\n\n", .{});

    // Demonstrate requirement completion calculation
    std.debug.print("=== ALM Metrics ===\n", .{});

    const total_requirements: u32 = 1;
    var approved_requirements: u32 = 0;
    var implemented_requirements: u32 = 0;

    switch (requirement.context) {
        .requirement => |ctx| {
            if (std.mem.eql(u8, ctx.status, "approved")) approved_requirements += 1;
            if (std.mem.eql(u8, ctx.status, "implemented")) implemented_requirements += 1;
        },
        else => {},
    }

    const completion_rate = if (total_requirements > 0)
        @as(f64, @floatFromInt(implemented_requirements)) / @as(f64, @floatFromInt(total_requirements)) * 100.0
    else
        0.0;

    std.debug.print("Total Requirements: {d}\n", .{total_requirements});
    std.debug.print("Approved: {d}\n", .{approved_requirements});
    std.debug.print("Implemented: {d}\n", .{implemented_requirements});
    std.debug.print("Completion Rate: {d:.1}%\n\n", .{completion_rate});

    std.debug.print("=== Example Complete ===\n", .{});
}
