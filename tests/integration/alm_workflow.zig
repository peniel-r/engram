// Integration tests for Engram ALM workflows
// Validates end-to-end scenarios from usecase.md

const std = @import("std");
const Allocator = std.mem.Allocator;
const Engram = @import("Engram");
const Neurona = Engram.Neurona;
const NeuronaType = Engram.NeuronaType;

test "ALM Workflow: Create requirement → Link test → Trace dependency" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_alm_workflow";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // 1. Create requirement
    const req_path = try std.fs.path.join(allocator, &.{ test_dir, "req.auth.oauth2.md" });
    try std.fs.cwd().writeFile(.{
        .sub_path = req_path,
        .data =
        \\---
        \\id: req.auth.oauth2
        \\title: Support OAuth 2.0
        \\type: requirement
        \\tags: [auth, oauth, requirement]
        \\---
        \\
        \\# OAuth 2.0 Support
        \\This requirement specifies OAuth 2.0 authentication.
        ,
    });
    defer allocator.free(req_path);

    // 2. Create test case
    const test_path = try std.fs.path.join(allocator, &.{ test_dir, "test.auth.oauth2.001.md" });
    try std.fs.cwd().writeFile(.{
        .sub_path = test_path,
        .data =
        \\---
        \\id: test.auth.oauth2.001
        \\title: OAuth Login Test
        \\type: test_case
        \\connections: ["validates:req.auth.oauth2:90"]
        \\tags: [test, auth, oauth]
        \\---
        \\
        \\# Test OAuth Login
        \\Tests OAuth 2.0 login flow.
        ,
    });
    defer allocator.free(test_path);

    // 3. Load and verify requirement
    var req = try Engram.storage.readNeurona(allocator, req_path);
    defer req.deinit(allocator);

    try std.testing.expectEqualStrings("req.auth.oauth2", req.id);
    try std.testing.expectEqualStrings("Support OAuth 2.0", req.title);
    try std.testing.expectEqual(NeuronaType.requirement, req.type);

    // 4. Load and verify test case
    var test_neurona = try Engram.storage.readNeurona(allocator, test_path);
    defer test_neurona.deinit(allocator);

    try std.testing.expectEqualStrings("test.auth.oauth2.001", test_neurona.id);
    try std.testing.expectEqualStrings("OAuth Login Test", test_neurona.title);
    try std.testing.expectEqual(NeuronaType.test_case, test_neurona.type);

    // 5. Verify connection exists
    const conns = test_neurona.getConnections(.validates);
    try std.testing.expectEqual(@as(usize, 1), conns.len);
    try std.testing.expectEqualStrings("req.auth.oauth2", conns[0].target_id);
    try std.testing.expectEqual(90, conns[0].weight);
}

test "CRUD Workflow: Create → Read → Delete" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_crud_workflow";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // 1. Create neurona
    const path = try std.fs.path.join(allocator, &.{ test_dir, "crud.test.md" });
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data = "---\nid: crud.test\ntitle: CRUD Test\ntags: [test]\n---\n# Test",
    });
    defer allocator.free(path);

    // 2. Read and verify
    var neurona = try Engram.storage.readNeurona(allocator, path);
    defer neurona.deinit(allocator);

    try std.testing.expectEqualStrings("crud.test", neurona.id);
    try std.testing.expectEqualStrings("CRUD Test", neurona.title);

    // 3. Delete
    try std.fs.cwd().deleteFile(path);

    // 4. Verify deleted
    const result = std.fs.cwd().openFile(path, .{});
    try std.testing.expectError(error.FileNotFound, result);

    std.debug.print("✅ CRUD workflow test passed\n", .{});
}

test "Graph Operations: Multiple connections → Sync" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_graph_ops";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create multiple Neuronas with connections
    const node1_path = try std.fs.path.join(allocator, &.{ test_dir, "node1.md" });
    const node2_path = try std.fs.path.join(allocator, &.{ test_dir, "node2.md" });
    const node3_path = try std.fs.path.join(allocator, &.{ test_dir, "node3.md" });

    try std.fs.cwd().writeFile(.{
        .sub_path = node1_path,
        .data = "---\nid: node1\ntitle: Node 1\nconnections: [\"relates_to:node2:50\"]\n---\n",
    });
    try std.fs.cwd().writeFile(.{
        .sub_path = node2_path,
        .data = "---\nid: node2\ntitle: Node 2\nconnections: [\"relates_to:node3:50\"]\n---\n",
    });
    try std.fs.cwd().writeFile(.{
        .sub_path = node3_path,
        .data = "---\nid: node3\ntitle: Node 3\n---\n",
    });

    // Verify all three exist
    var node1 = try Engram.storage.readNeurona(allocator, node1_path);
    defer node1.deinit(allocator);
    var node2 = try Engram.storage.readNeurona(allocator, node2_path);
    defer node2.deinit(allocator);
    var node3 = try Engram.storage.readNeurona(allocator, node3_path);
    defer node3.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), node1.connections.count());

    // Verify connections
    const conns = node1.getConnections(.relates_to);
    try std.testing.expectEqual(@as(usize, 1), conns.len);
    try std.testing.expectEqualStrings("node2", conns[0].target_id);

    allocator.free(node1_path);
    allocator.free(node2_path);
    allocator.free(node3_path);

    std.debug.print("✅ Graph operations test passed\n", .{});
}
