//! Context extensions for Tier 3 Neuronas
//! Allows custom context based on neurona type (state_machine, artifact, test_case, issue, requirement)

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Context extensions (Tier 3)
/// Allows custom context based on neurona type
/// Each variant contains type-specific metadata
pub const Context = union(enum) {
    /// State machine context with triggers and actions
    state_machine: StateMachineContext,

    /// Artifact context (code snippets, scripts, tools)
    artifact: ArtifactContext,

    /// Test case context
    test_case: TestCaseContext,

    /// Issue context (ALM)
    issue: IssueContext,

    /// Requirement context (ALM)
    requirement: RequirementContext,

    /// Custom context (any key-value pairs)
    custom: std.StringHashMapUnmanaged([]const u8),

    /// No context (Tier 1/2 default)
    none,

    /// Free allocated memory for Context
    pub fn deinit(self: *Context, allocator: Allocator) void {
        switch (self.*) {
            .state_machine => |*ctx| ctx.deinit(allocator),
            .artifact => |*ctx| ctx.deinit(allocator),
            .test_case => |*ctx| ctx.deinit(allocator),
            .issue => |*ctx| ctx.deinit(allocator),
            .requirement => |*ctx| ctx.deinit(allocator),
            .custom => |*ctx| {
                var it = ctx.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    allocator.free(entry.value_ptr.*);
                }
                ctx.deinit(allocator);
            },
            .none => {},
        }
    }
};

/// State machine context
pub const StateMachineContext = struct {
    triggers: std.ArrayListUnmanaged([]const u8),
    entry_action: []const u8,
    exit_action: []const u8,
    allowed_roles: std.ArrayListUnmanaged([]const u8),

    /// Free allocated memory
    pub fn deinit(self: *StateMachineContext, allocator: Allocator) void {
        for (self.triggers.items) |t| allocator.free(t);
        self.triggers.deinit(allocator);
        allocator.free(self.entry_action);
        allocator.free(self.exit_action);
        for (self.allowed_roles.items) |r| allocator.free(r);
        self.allowed_roles.deinit(allocator);
    }
};

/// Artifact context (code snippets, scripts, tools)
pub const ArtifactContext = struct {
    runtime: []const u8,
    file_path: []const u8,
    safe_to_exec: bool,
    language_version: ?[]const u8,
    last_modified: ?[]const u8,

    /// Free allocated memory
    pub fn deinit(self: *ArtifactContext, allocator: Allocator) void {
        allocator.free(self.runtime);
        allocator.free(self.file_path);
        if (self.language_version) |v| allocator.free(v);
        if (self.last_modified) |v| allocator.free(v);
    }
};

/// Test case context
pub const TestCaseContext = struct {
    framework: []const u8,
    test_file: ?[]const u8,
    status: []const u8,
    priority: u8,
    assignee: ?[]const u8,
    duration: ?[]const u8,
    last_run: ?[]const u8,

    /// Free allocated memory
    pub fn deinit(self: *TestCaseContext, allocator: Allocator) void {
        allocator.free(self.framework);
        if (self.test_file) |f| allocator.free(f);
        allocator.free(self.status);
        if (self.assignee) |a| allocator.free(a);
        if (self.duration) |d| allocator.free(d);
        if (self.last_run) |v| allocator.free(v);
    }
};

/// Issue context (ALM)
pub const IssueContext = struct {
    status: []const u8, // open, in_progress, resolved, closed
    priority: u8, // 1-5 (1=highest)
    assignee: ?[]const u8,
    created: []const u8,
    resolved: ?[]const u8,
    closed: ?[]const u8,
    blocked_by: std.ArrayListUnmanaged([]const u8),
    related_to: std.ArrayListUnmanaged([]const u8),

    /// Free allocated memory
    pub fn deinit(self: *IssueContext, allocator: Allocator) void {
        allocator.free(self.status);
        allocator.free(self.created);
        if (self.assignee) |a| allocator.free(a);
        if (self.resolved) |r| allocator.free(r);
        if (self.closed) |c| allocator.free(c);
        for (self.blocked_by.items) |b| allocator.free(b);
        self.blocked_by.deinit(allocator);
        for (self.related_to.items) |r| allocator.free(r);
        self.related_to.deinit(allocator);
    }
};

/// Requirement context (ALM)
pub const RequirementContext = struct {
    status: []const u8, // draft, approved, implemented
    verification_method: []const u8, // test, analysis, inspection
    priority: u8, // 1-5 (1=highest)
    assignee: ?[]const u8,
    effort_points: ?u16,
    sprint: ?[]const u8,

    /// Free allocated memory
    pub fn deinit(self: *RequirementContext, allocator: Allocator) void {
        allocator.free(self.status);
        allocator.free(self.verification_method);
        if (self.assignee) |a| allocator.free(a);
        if (self.sprint) |s| allocator.free(s);
    }
};

test "Context deinit handles all variants" {
    const allocator = std.testing.allocator;

    // Test state_machine
    var ctx1: Context = .{ .state_machine = .{
        .triggers = .{},
        .entry_action = try allocator.dupe(u8, "enter"),
        .exit_action = try allocator.dupe(u8, "exit"),
        .allowed_roles = .{},
    } };
    ctx1.deinit(allocator);

    // Test artifact
    var ctx2: Context = .{ .artifact = .{
        .runtime = try allocator.dupe(u8, "zig"),
        .file_path = try allocator.dupe(u8, "/path/to/file"),
        .safe_to_exec = true,
        .language_version = null,
        .last_modified = null,
    } };
    ctx2.deinit(allocator);

    // Test none (should not crash)
    var ctx3: Context = .none;
    ctx3.deinit(allocator);

    // Test custom - use allocated strings, not literals
    var ctx4: Context = .{ .custom = std.StringHashMapUnmanaged([]const u8){} };
    try ctx4.custom.put(allocator, try allocator.dupe(u8, "key"), try allocator.dupe(u8, "value"));
    ctx4.deinit(allocator);
}
