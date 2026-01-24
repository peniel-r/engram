// State Machine Engine for ALM Neuronas
// Enforces state transitions for issues, tests, and requirements

const std = @import("std");

// ==================== State Enums ====================

/// Issue states: open -> in_progress -> resolved -> closed
pub const IssueState = enum {
    open,
    in_progress,
    resolved,
    closed,

    pub fn fromString(s: []const u8) ?IssueState {
        if (std.mem.eql(u8, s, "open")) return .open;
        if (std.mem.eql(u8, s, "in_progress")) return .in_progress;
        if (std.mem.eql(u8, s, "resolved")) return .resolved;
        if (std.mem.eql(u8, s, "closed")) return .closed;
        return null;
    }

    pub fn toString(self: IssueState) []const u8 {
        return switch (self) {
            .open => "open",
            .in_progress => "in_progress",
            .resolved => "resolved",
            .closed => "closed",
        };
    }
};

/// Test states: not_run -> running -> passing/failing
pub const TestState = enum {
    not_run,
    running,
    passing,
    failing,

    pub fn fromString(s: []const u8) ?TestState {
        if (std.mem.eql(u8, s, "not_run")) return .not_run;
        if (std.mem.eql(u8, s, "running")) return .running;
        if (std.mem.eql(u8, s, "passing")) return .passing;
        if (std.mem.eql(u8, s, "failing")) return .failing;
        return null;
    }

    pub fn toString(self: TestState) []const u8 {
        return switch (self) {
            .not_run => "not_run",
            .running => "running",
            .passing => "passing",
            .failing => "failing",
        };
    }
};

/// Requirement states: draft -> approved -> implemented
pub const RequirementState = enum {
    draft,
    approved,
    implemented,

    pub fn fromString(s: []const u8) ?RequirementState {
        if (std.mem.eql(u8, s, "draft")) return .draft;
        if (std.mem.eql(u8, s, "approved")) return .approved;
        if (std.mem.eql(u8, s, "implemented")) return .implemented;
        return null;
    }

    pub fn toString(self: RequirementState) []const u8 {
        return switch (self) {
            .draft => "draft",
            .approved => "approved",
            .implemented => "implemented",
        };
    }
};

// ==================== State Transitions ====================

/// Check if issue state transition is valid
pub fn isValidIssueTransition(from: IssueState, to: IssueState) bool {
    // Valid transitions:
    // open -> in_progress
    // in_progress -> resolved
    // in_progress -> open (regress)
    // resolved -> closed
    // resolved -> in_progress (reopen)
    return switch (from) {
        .open => to == .in_progress,
        .in_progress => to == .open or to == .resolved,
        .resolved => to == .in_progress or to == .closed,
        .closed => false, // Terminal state
    };
}

/// Check if test state transition is valid
pub fn isValidTestTransition(from: TestState, to: TestState) bool {
    // Valid transitions:
    // not_run -> running
    // running -> passing
    // running -> failing
    // passing -> running (re-run)
    // failing -> running (re-run)
    return switch (from) {
        .not_run => to == .running,
        .running => to == .passing or to == .failing,
        .passing => to == .running,
        .failing => to == .running,
    };
}

/// Check if requirement state transition is valid
pub fn isValidRequirementTransition(from: RequirementState, to: RequirementState) bool {
    // Valid transitions:
    // draft -> approved
    // approved -> draft (reject)
    // approved -> implemented
    // implemented -> approved (revert)
    return switch (from) {
        .draft => to == .approved,
        .approved => to == .draft or to == .implemented,
        .implemented => to == .approved,
    };
}

/// Get next valid states for an issue
/// Returns array of valid next states (caller should check length)
pub fn getNextIssueStates(current: IssueState) struct { states: [2]IssueState, count: usize } {
    return switch (current) {
        .open => .{ .states = [_]IssueState{ .in_progress, .closed }, .count = 1 },
        .in_progress => .{ .states = [_]IssueState{ .open, .resolved }, .count = 2 },
        .resolved => .{ .states = [_]IssueState{ .in_progress, .closed }, .count = 2 },
        .closed => .{ .states = [_]IssueState{ .open, .closed }, .count = 0 },
    };
}

/// Get next valid states for a test
/// Returns array of valid next states (caller should check length)
pub fn getNextTestStates(current: TestState) struct { states: [2]TestState, count: usize } {
    return switch (current) {
        .not_run => .{ .states = [_]TestState{ .running, .passing }, .count = 1 },
        .running => .{ .states = [_]TestState{ .passing, .failing }, .count = 2 },
        .passing => .{ .states = [_]TestState{ .running, .passing }, .count = 1 },
        .failing => .{ .states = [_]TestState{ .running, .failing }, .count = 1 },
    };
}

/// Get next valid states for a requirement
/// Returns array of valid next states (caller should check length)
pub fn getNextRequirementStates(current: RequirementState) struct { states: [2]RequirementState, count: usize } {
    return switch (current) {
        .draft => .{ .states = [_]RequirementState{ .approved, .implemented }, .count = 1 },
        .approved => .{ .states = [_]RequirementState{ .draft, .implemented }, .count = 2 },
        .implemented => .{ .states = [_]RequirementState{ .approved, .draft }, .count = 1 },
    };
}

// ==================== Generic State Validation ====================

/// Validate state transition by type
pub fn isValidTransitionByType(neurona_type: []const u8, from_str: []const u8, to_str: []const u8) bool {
    if (std.mem.eql(u8, neurona_type, "issue")) {
        const from = IssueState.fromString(from_str) orelse return false;
        const to = IssueState.fromString(to_str) orelse return false;
        return isValidIssueTransition(from, to);
    }

    if (std.mem.eql(u8, neurona_type, "test_case")) {
        const from = TestState.fromString(from_str) orelse return false;
        const to = TestState.fromString(to_str) orelse return false;
        return isValidTestTransition(from, to);
    }

    if (std.mem.eql(u8, neurona_type, "requirement")) {
        const from = RequirementState.fromString(from_str) orelse return false;
        const to = RequirementState.fromString(to_str) orelse return false;
        return isValidRequirementTransition(from, to);
    }

    // No state validation for other types
    return true;
}

/// Get state validation error message
pub fn getTransitionError(neurona_type: []const u8, from: []const u8, to: []const u8) []const u8 {
    _ = from;
    _ = to;
    if (std.mem.eql(u8, neurona_type, "issue")) {
        return "Invalid issue state transition. Valid: open->in_progress->resolved->closed";
    }
    if (std.mem.eql(u8, neurona_type, "test_case")) {
        return "Invalid test state transition. Valid: not_run->running->passing/failing";
    }
    if (std.mem.eql(u8, neurona_type, "requirement")) {
        return "Invalid requirement state transition. Valid: draft->approved->implemented";
    }
    return "Invalid state transition";
}

// ==================== Tests ====================

test "IssueState fromString parses all states" {
    try std.testing.expectEqual(.open, IssueState.fromString("open").?);
    try std.testing.expectEqual(.in_progress, IssueState.fromString("in_progress").?);
    try std.testing.expectEqual(.resolved, IssueState.fromString("resolved").?);
    try std.testing.expectEqual(.closed, IssueState.fromString("closed").?);
    try std.testing.expectEqual(@as(?IssueState, null), IssueState.fromString("invalid"));
}

test "TestState fromString parses all states" {
    try std.testing.expectEqual(.not_run, TestState.fromString("not_run").?);
    try std.testing.expectEqual(.running, TestState.fromString("running").?);
    try std.testing.expectEqual(.passing, TestState.fromString("passing").?);
    try std.testing.expectEqual(.failing, TestState.fromString("failing").?);
}

test "RequirementState fromString parses all states" {
    try std.testing.expectEqual(.draft, RequirementState.fromString("draft").?);
    try std.testing.expectEqual(.approved, RequirementState.fromString("approved").?);
    try std.testing.expectEqual(.implemented, RequirementState.fromString("implemented").?);
}

test "isValidIssueTransition validates forward transitions" {
    try std.testing.expect(isValidIssueTransition(.open, .in_progress));
    try std.testing.expect(isValidIssueTransition(.in_progress, .resolved));
    try std.testing.expect(isValidIssueTransition(.resolved, .closed));
}

test "isValidIssueTransition validates backward transitions" {
    try std.testing.expect(isValidIssueTransition(.in_progress, .open));
    try std.testing.expect(isValidIssueTransition(.resolved, .in_progress));
}

test "isValidIssueTransition rejects invalid transitions" {
    try std.testing.expect(!isValidIssueTransition(.open, .resolved));
    try std.testing.expect(!isValidIssueTransition(.open, .closed));
    try std.testing.expect(!isValidIssueTransition(.closed, .open));
    try std.testing.expect(!isValidIssueTransition(.closed, .resolved));
}

test "isValidTestTransition validates forward transitions" {
    try std.testing.expect(isValidTestTransition(.not_run, .running));
    try std.testing.expect(isValidTestTransition(.running, .passing));
    try std.testing.expect(isValidTestTransition(.running, .failing));
}

test "isValidTestTransition validates re-run transitions" {
    try std.testing.expect(isValidTestTransition(.passing, .running));
    try std.testing.expect(isValidTestTransition(.failing, .running));
}

test "isValidTestTransition rejects invalid transitions" {
    try std.testing.expect(!isValidTestTransition(.not_run, .passing));
    try std.testing.expect(!isValidTestTransition(.not_run, .failing));
    try std.testing.expect(!isValidTestTransition(.passing, .failing));
    try std.testing.expect(!isValidTestTransition(.failing, .passing));
}

test "isValidRequirementTransition validates transitions" {
    try std.testing.expect(isValidRequirementTransition(.draft, .approved));
    try std.testing.expect(isValidRequirementTransition(.approved, .implemented));
    try std.testing.expect(isValidRequirementTransition(.approved, .draft));
    try std.testing.expect(isValidRequirementTransition(.implemented, .approved));
}

test "isValidRequirementTransition rejects invalid transitions" {
    try std.testing.expect(!isValidRequirementTransition(.draft, .implemented));
    try std.testing.expect(!isValidRequirementTransition(.implemented, .draft));
}

test "getNextIssueStates returns valid transitions" {
    const next = getNextIssueStates(.open);
    try std.testing.expectEqual(@as(usize, 1), next.count);
    try std.testing.expectEqual(.in_progress, next.states[0]);

    const next2 = getNextIssueStates(.resolved);
    try std.testing.expectEqual(@as(usize, 2), next2.count);
}

test "isValidTransitionByType validates by type string" {
    try std.testing.expect(isValidTransitionByType("issue", "open", "in_progress"));
    try std.testing.expect(isValidTransitionByType("test_case", "not_run", "running"));
    try std.testing.expect(isValidTransitionByType("requirement", "draft", "approved"));

    try std.testing.expect(!isValidTransitionByType("issue", "open", "closed"));
    try std.testing.expect(!isValidTransitionByType("test_case", "not_run", "passing"));
}

test "toString returns correct strings" {
    try std.testing.expectEqualStrings("open", IssueState.open.toString());
    try std.testing.expectEqualStrings("in_progress", IssueState.in_progress.toString());
    try std.testing.expectEqualStrings("passing", TestState.passing.toString());
    try std.testing.expectEqualStrings("approved", RequirementState.approved.toString());
}
