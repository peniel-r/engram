// Test for memory leak fix in scanNeuronas
// This test verifies that scanNeuronas properly handles
// memory when loading multiple Neurona files
const std = @import("std");
const Allocator = std.mem.Allocator;
const storage = @import("src/storage/filesystem.zig");

test "scanNeuronas does not leak memory when loading multiple neuronas" {
    const allocator = std.testing.allocator;

    // Create test directory
    const test_dir = "test_memory_leak_dir";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create multiple test Neurona files
    const path1 = try std.fs.path.join(allocator, &.{ test_dir, "test1.md" });
    defer allocator.free(path1);
    const path2 = try std.fs.path.join(allocator, &.{ test_dir, "test2.md" });
    defer allocator.free(path2);
    const path3 = try std.fs.path.join(allocator, &.{ test_dir, "invalid.md" });
    defer allocator.free(path3);

    try std.fs.cwd().writeFile(.{ .sub_path = path1, .data = 
        \\---
        \\id: test.001
        \\title: Test One
        \\tags: [test]
        \\---
        \\# Content One
    });
    try std.fs.cwd().writeFile(.{ .sub_path = path2, .data = 
        \\---
        \\id: test.002
        \\title: Test Two
        \\updated: "2026-01-25"
        \\language: "en"
        \\tags: [test]
        \\---
        \\# Content Two
    });
    // Invalid file (no frontmatter)
    try std.fs.cwd().writeFile(.{ .sub_path = path3, .data = "No frontmatter here" });

    // Scan directory - this should load only 2 valid neuronas without leaks
    const neuronas = try storage.scanNeuronas(allocator, test_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    // Verify correct count (invalid file should be skipped)
    try std.testing.expectEqual(@as(usize, 2), neuronas.len);

    // Verify loaded neuronas have correct values
    try std.testing.expectEqualStrings("test.001", neuronas[0].id);
    try std.testing.expectEqualStrings("Test One", neuronas[0].title);
    try std.testing.expectEqual(@as(usize, 1), neuronas[0].tags.items.len);

    try std.testing.expectEqualStrings("test.002", neuronas[1].id);
    try std.testing.expectEqualStrings("Test Two", neuronas[1].title);
    try std.testing.expectEqualStrings("2026-01-25", neuronas[1].updated);
    try std.testing.expectEqualStrings("en", neuronas[1].language);
}

test "scanNeuronas handles string replacement correctly" {
    const allocator = std.testing.allocator;

    // Create test directory
    const test_dir = "test_string_replace_dir";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create Neurona with optional fields
    const path = try std.fs.path.join(allocator, &.{ test_dir, "with_optional.md" });
    defer allocator.free(path);

    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = 
        \\---
        \\id: test.003
        \\title: With Optional
        \\updated: "2026-01-25"
        \\language: "fr"
        \\hash: "sha256:abc123"
        \\tags: [test]
        \\---
        \\# Content
    });

    // Scan and verify
    const neuronas = try storage.scanNeuronas(allocator, test_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    try std.testing.expectEqual(@as(usize, 1), neuronas.len);
    const n = &neuronas[0];

    // Verify all fields were set correctly without leaks
    try std.testing.expectEqualStrings("test.003", n.id);
    try std.testing.expectEqualStrings("With Optional", n.title);
    try std.testing.expectEqualStrings("2026-01-25", n.updated);
    try std.testing.expectEqualStrings("fr", n.language);
    try std.testing.expectEqualStrings("sha256:abc123", n.hash.?);
}
