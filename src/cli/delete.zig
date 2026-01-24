// File: src/cli/delete.zig
// The `engram delete` command for deleting Neuronas

const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = @import("../storage/filesystem.zig");

/// Configuration for Delete command
pub const DeleteConfig = struct {
    id: []const u8,
    neuronas_dir: []const u8 = "neuronas",
    verbose: bool = false,
};

/// Execute delete command
pub fn execute(allocator: Allocator, config: DeleteConfig) !void {
    // 1. Find Neurona file
    const filepath = fs.findNeuronaPath(allocator, config.neuronas_dir, config.id) catch |err| {
        if (err == error.NeuronaNotFound) {
            std.debug.print("Error: Neurona '{s}' not found in {s}.\n", .{ config.id, config.neuronas_dir });
        }
        return err;
    };
    defer allocator.free(filepath);

    // 2. Delete file
    try std.fs.cwd().deleteFile(filepath);

    if (config.verbose) {
        std.debug.print("Deleted: {s}\n", .{filepath});
    }

    std.debug.print("Successfully deleted Neurona '{s}'.\n", .{config.id});
}

test "execute deletes Neurona file" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_neuronas_delete";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test Neurona
    const path = try std.fs.path.join(allocator, &.{ test_dir, "test.md" });
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = "---\nid: test\ntitle: Test\n---\n" });
    defer allocator.free(path);

    // Execute delete
    const config = DeleteConfig{
        .id = "test",
        .neuronas_dir = test_dir,
        .verbose = true,
    };

    try execute(allocator, config);

    // Verify file is deleted
    const result = std.fs.cwd().openFile(path, .{});
    try std.testing.expectError(error.FileNotFound, result);
}
