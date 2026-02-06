// File: src/cli/delete.zig
// The `engram delete` command for deleting Neuronas

const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = @import("../storage/filesystem.zig");
const uri_parser = @import("../utils/uri_parser.zig");

/// Configuration for Delete command
pub const DeleteConfig = struct {
    id: []const u8,
    cortex_dir: ?[]const u8 = null,
    verbose: bool = false,
};

/// Execute delete command
pub fn execute(allocator: Allocator, config: DeleteConfig) !void {
    // Determine neuronas directory
    const cortex_dir = config.cortex_dir orelse blk: {
        const cd = uri_parser.findCortexDir(allocator) catch |err| {
            if (err == error.CortexNotFound) {
                std.debug.print("Error: No cortex found in current directory or parent directories.\n", .{});
                std.debug.print("\nHint: Navigate to a cortex directory or use --cortex <path> to specify location.\n", .{});
                std.debug.print("Run 'engram init <name>' to create a new cortex.\n", .{});
                std.process.exit(1);
            }
            return err;
        };
        break :blk cd;
    };
    defer if (config.cortex_dir == null) allocator.free(cortex_dir);

    const neuronas_dir = try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex_dir});
    defer allocator.free(neuronas_dir);

    // 1. Find Neurona file
    const filepath = try fs.findNeuronaPath(allocator, neuronas_dir, config.id);
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
    const test_dir = "test_cortex_delete";
    const neuronas_dir = "test_cortex_delete/neuronas";
    try std.fs.cwd().makePath(neuronas_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test Neurona
    const path = try std.fs.path.join(allocator, &.{ neuronas_dir, "test.md" });
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = "---\nid: test\ntitle: Test\n---\n" });
    defer allocator.free(path);

    // Execute delete
    const config = DeleteConfig{
        .id = "test",
        .cortex_dir = test_dir,
        .verbose = true,
    };

    try execute(allocator, config);

    // Verify file is deleted
    const result = std.fs.cwd().access(path, .{});
    try std.testing.expectError(error.FileNotFound, result);
}
