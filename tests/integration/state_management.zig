// Integration Tests for State Management
// Tests state transitions, validation, and orphan detection end-to-end

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../../src/core/neurona.zig").Neurona;
const NeuronaType = @import("../../src/core/neurona.zig").NeuronaType;
const Connection = @import("../../src/core/neurona.zig").Connection;
const ConnectionType = @import("../../src/core/neurona.zig").ConnectionType;
const Graph = @import("../../src/core/graph.zig").Graph;
const state_machine = @import("../../src/core/state_machine.zig");
const validator = @import("../../src/core/validator.zig");

// ==================== ALM Workflow Tests ====================

test "Complete ALM workflow with state transitions" {
    const allocator = std.testing.allocator;

    // Create requirement
    var requirement = try Neurona.init(allocator);
    defer requirement.deinit(allocator);
    requirement.type = .requirement;
    requirement.id = try allocator.dupe(u8, "req.auth.001");
    requirement.title = try allocator.dupe(u8, "OAuth2 Authentication");

    // Create test_case
    var test_case = try Neurona.init(allocator);
    defer test_case.deinit(allocator);
    test_case.type = .test_case;
    test_case.id = try allocator.dupe(u8, "test.auth.001");
    test_case.title = try allocator.dupe(u8, "OAuth2 Test");

    // Build graph
    var graph = Graph.init();
    defer graph.deinit(allocator);

    // Link requirement -> test_case (validates)
    try requirement.addConnection(allocator, .{
        .target_id = try allocator.dupe(u8, "test.auth.001"),
        .connection_type = .validates,
        .weight = 100,
    });

    try graph.addEdge(allocator, "req.auth.001", "test.auth.001", 100);

    // Verify connection is valid
    try validator.validateConnection(&requirement, &test_case, .validates);

    try std.testing.expectEqual(.requirement, requirement.type);
    try std.testing.expectEqual(.test_case, test_case.type);
}

test "Issue state transitions are enforced" {
    const allocator = std.testing.allocator;

    var issue = try Neurona.init(allocator);
    defer issue.deinit(allocator);
    issue.type = .issue;
    issue.id = try allocator.dupe(u8, "issue.bug.001");
    issue.title = try allocator.dupe(u8, "Login Bug");

    // Test valid transitions: open -> in_progress -> resolved -> closed
    const open = state_machine.IssueState.open;
    const in_progress = state_machine.IssueState.in_progress;
    const resolved = state_machine.IssueState.resolved;
    const closed = state_machine.IssueState.closed;

    try std.testing.expect(state_machine.isValidIssueTransition(open, in_progress));
    try std.testing.expect(state_machine.isValidIssueTransition(in_progress, resolved));
    try std.testing.expect(state_machine.isValidIssueTransition(resolved, closed));

    // Test invalid transitions
    const invalid_transition = !state_machine.isValidIssueTransition(closed, open);
    try std.testing.expect(invalid_transition);

    // Test via string API
    try std.testing.expect(state_machine.isValidTransitionByType("issue", "open", "in_progress"));
    try std.testing.expect(!state_machine.isValidTransitionByType("issue", "open", "closed"));
}

test "Test case state transitions are enforced" {
    const allocator = std.testing.allocator;

    var test_case = try Neurona.init(allocator);
    defer test_case.deinit(allocator);
    test_case.type = .test_case;
    test_case.id = try allocator.dupe(u8, "test.auth.001");
    test_case.title = try allocator.dupe(u8, "OAuth2 Test");

    // Test valid transitions: not_run -> running -> passing/failing
    const not_run = state_machine.TestState.not_run;
    const running = state_machine.TestState.running;
    const passing = state_machine.TestState.passing;
    const failing = state_machine.TestState.failing;

    try std.testing.expect(state_machine.isValidTestTransition(not_run, running));
    try std.testing.expect(state_machine.isValidTestTransition(running, passing));
    try std.testing.expect(state_machine.isValidTestTransition(running, failing));

    // Test re-run: passing -> running
    try std.testing.expect(state_machine.isValidTestTransition(passing, running));

    // Test via string API
    try std.testing.expect(state_machine.isValidTransitionByType("test_case", "not_run", "running"));
    try std.testing.expect(!state_machine.isValidTransitionByType("test_case", "not_run", "passing"));
}

test "Requirement state transitions are enforced" {
    const allocator = std.testing.allocator;

    var requirement = try Neurona.init(allocator);
    defer requirement.deinit(allocator);
    requirement.type = .requirement;
    requirement.id = try allocator.dupe(u8, "req.auth.001");
    requirement.title = try allocator.dupe(u8, "OAuth2 Auth");

    // Test valid transitions: draft -> approved -> implemented
    const draft = state_machine.RequirementState.draft;
    const approved = state_machine.RequirementState.approved;
    const implemented = state_machine.RequirementState.implemented;

    try std.testing.expect(state_machine.isValidRequirementTransition(draft, approved));
    try std.testing.expect(state_machine.isValidRequirementTransition(approved, implemented));

    // Test rejection: approved -> draft
    try std.testing.expect(state_machine.isValidRequirementTransition(approved, draft));

    // Test via string API
    try std.testing.expect(state_machine.isValidTransitionByType("requirement", "draft", "approved"));
    try std.testing.expect(!state_machine.isValidTransitionByType("requirement", "draft", "implemented"));
}

// ==================== Validation Tests ====================

test "Connection validation rejects invalid types" {
    const allocator = std.testing.allocator;

    var requirement = try Neurona.init(allocator);
    defer requirement.deinit(allocator);
    requirement.type = .requirement;

    var test_case = try Neurona.init(allocator);
    defer test_case.deinit(allocator);
    test_case.type = .test_case;

    var artifact = try Neurona.init(allocator);
    defer artifact.deinit(allocator);
    artifact.type = .artifact;

    // Valid: requirement implements artifact
    try validator.validateConnection(&requirement, &artifact, .implements);

    // Invalid: test_case implements artifact (should be tested_by)
    const test_result = validator.validateConnection(&test_case, &artifact, .implements);
    try std.testing.expectError(error.ConnectionTypeNotAllowed, test_result);
}

test "Cycle detection finds circular dependencies" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    // Create cycle: A -> B -> C -> A
    try graph.addEdge(allocator, "A", "B", 50);
    try graph.addEdge(allocator, "B", "C", 50);
    try graph.addEdge(allocator, "C", "A", 50);

    const cycles = try validator.detectCycles(&graph, allocator);
    defer {
        for (cycles) |c| allocator.free(c);
        allocator.free(cycles);
    }

    try std.testing.expect(cycles.len > 0);
}

test "Orphan detection finds unconnected nodes" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    // Add connected nodes
    try graph.addEdge(allocator, "A", "B", 50);

    // Create unconnected neurona
    var orphan = try Neurona.init(allocator);
    defer orphan.deinit(allocator);
    orphan.id = try allocator.dupe(u8, "orphan.001");
    orphan.title = try allocator.dupe(u8, "Orphaned Node");
    orphan.type = .concept;

    const neuronas = [_]Neurona{orphan};

    const orphans = try validator.findOrphans(&neuronas, &graph, allocator);
    defer {
        for (orphans) |o| allocator.free(o);
        allocator.free(orphans);
    }

    // The orphan node should be detected
    try std.testing.expect(orphans.len > 0);
}

test "Graph bidirectional indexing works correctly" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    try graph.addEdge(allocator, "A", "B", 50);

    // Check forward edge
    const adj = graph.getAdjacent("A");
    try std.testing.expectEqual(@as(usize, 1), adj.len);
    try std.testing.expectEqualStrings("B", adj[0].target_id);

    // Check reverse edge
    const incoming = graph.getIncoming("B");
    try std.testing.expectEqual(@as(usize, 1), incoming.len);
    try std.testing.expectEqualStrings("A", incoming[0].target_id);
}

test "Graph statistics are accurate" {
    const allocator = std.testing.allocator;

    var graph = Graph.init();
    defer graph.deinit(allocator);

    try graph.addEdge(allocator, "A", "B", 50);
    try graph.addEdge(allocator, "B", "C", 50);

    try std.testing.expectEqual(@as(usize, 3), graph.nodeCount());
    try std.testing.expectEqual(@as(usize, 4), graph.edgeCount()); // 2 forward + 2 reverse
}

// ==================== End-to-End Workflow Tests ====================

test "Full ALM workflow: requirement -> test -> artifact" {
    const allocator = std.testing.allocator;

    // Create requirement
    var requirement = try Neurona.init(allocator);
    defer requirement.deinit(allocator);
    requirement.type = .requirement;
    requirement.id = try allocator.dupe(u8, "req.oauth2");
    requirement.title = try allocator.dupe(u8, "OAuth2 Requirement");

    // Create test case
    var test_case = try Neurona.init(allocator);
    defer test_case.deinit(allocator);
    test_case.type = .test_case;
    test_case.id = try allocator.dupe(u8, "test.oauth2");
    test_case.title = try allocator.dupe(u8, "OAuth2 Test");

    // Create artifact
    var artifact = try Neurona.init(allocator);
    defer artifact.deinit(allocator);
    artifact.type = .artifact;
    artifact.id = try allocator.dupe(u8, "auth.oauth2.impl");
    artifact.title = try allocator.dupe(u8, "OAuth2 Implementation");

    // Build graph
    var graph = Graph.init();
    defer graph.deinit(allocator);

    // Link requirement -> test_case (validates)
    try graph.addEdge(allocator, "req.oauth2", "test.oauth2", 100);

    // Link artifact -> requirement (implements)
    try graph.addEdge(allocator, "auth.oauth2.impl", "req.oauth2", 100);

    // Verify no cycles
    const cycles = try validator.detectCycles(&graph, allocator);
    defer {
        for (cycles) |c| allocator.free(c);
        allocator.free(cycles);
    }
    try std.testing.expectEqual(@as(usize, 0), cycles.len);

    // Verify no orphans (all nodes connected)
    const neuronas = [_]Neurona{ requirement, test_case, artifact };
    const orphans = try validator.findOrphans(&neuronas, &graph, allocator);
    defer {
        for (orphans) |o| allocator.free(o);
        allocator.free(orphans);
    }
    try std.testing.expectEqual(@as(usize, 0), orphans.len);
}
