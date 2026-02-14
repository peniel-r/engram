// File: src/cli/delete.zig
// The `engram delete` command for deleting Neuronas
// MIGRATED: Now uses Phase 3 CLI utilities (HumanOutput)

const std = @import("std");
const Allocator = std.mem.Allocator;
const FileOps = @import("../utils/file_ops.zig").FileOps;
const ErrorReporter = @import("../utils/error_reporter.zig").ErrorReporter;
const uri_parser = @import("../utils/uri_parser.zig");

// Import Phase 3 CLI utilities
const HumanOutput = @import("output/human.zig").HumanOutput;

/// Configuration for Delete command
pub const DeleteConfig = struct {
    id: []const u8,
    cortex_dir: ?[]const u8 = null,
    verbose: bool = false,
};

/// Execute delete command
pub fn execute(allocator: Allocator, config: DeleteConfig) !void {
    // Determine cortex directory
    const cortex_dir = uri_parser.findCortexDir(allocator, config.cortex_dir) catch |err| {
        if (err == error.CortexNotFound) {
            ErrorReporter.cortexNotFound();
            std.process.exit(1);
        }
        return err;
    };
    defer allocator.free(cortex_dir);

    const neuronas_dir = try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex_dir});
    defer allocator.free(neuronas_dir);

    // Delete neurona using unified API
    try FileOps.deleteNeuronaById(allocator, neuronas_dir, config.id, config.verbose);

    ErrorReporter.success("deleted", config.id);
}

test "execute deletes Neurona file" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_cortex_delete";
    const neuronas_dir = "test_cortex_delete/neuronas";
    try std.fs.cwd().makePath(neuronas_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create cortex.json
    const cortex_json_path = try std.fs.path.join(allocator, &.{ test_dir, "cortex.json" });
    defer allocator.free(cortex_json_path);
    try std.fs.cwd().writeFile(.{
        .sub_path = cortex_json_path,
        .data = "{\"name\":\"test\",\"type\":\"alm\"}",
    });

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
