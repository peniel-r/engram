// File: src/utils/file_ops.zig
// Unified file operations for CLI commands
// MIGRATED: Now uses lib types via root.zig

const std = @import("std");
const Allocator = std.mem.Allocator;
// Use lib types via root.zig (Phase 4 migration)
const Neurona = @import("../root.zig").Neurona;
const fs = @import("../storage/filesystem.zig");

/// Result structure for readNeuronaWithBody
pub const NeuronaWithBody = struct {
    neurona: Neurona,
    body: []const u8,
    filepath: []const u8,

    /// Clean up allocated resources
    pub fn deinit(self: *NeuronaWithBody, allocator: Allocator) void {
        self.neurona.deinit(allocator);
        allocator.free(self.body);
        allocator.free(self.filepath);
    }
};

/// Unified file operations for CLI commands
pub const FileOps = struct {
    /// Find neurona file with smart search (wrapper for fs.findNeuronaPath)
    pub fn findNeuronaFile(allocator: Allocator, neuronas_dir: []const u8, id: []const u8) ![]const u8 {
        return fs.findNeuronaPath(allocator, neuronas_dir, id);
    }

    /// Read neurona with body content in one call
    /// Returns a NeuronaWithBody structure that must be deinit'ed
    pub fn readNeuronaWithBody(allocator: Allocator, neuronas_dir: []const u8, id: []const u8) !NeuronaWithBody {
        const filepath = try fs.findNeuronaPath(allocator, neuronas_dir, id);
        errdefer allocator.free(filepath);

        const neurona = try fs.readNeurona(allocator, filepath);
        const body = try fs.readBodyContent(allocator, filepath);
        errdefer allocator.free(body);

        return .{
            .neurona = neurona,
            .body = body,
            .filepath = filepath,
        };
    }

    /// Read neurona with body content from direct filepath
    pub fn readNeuronaWithBodyFromPath(allocator: Allocator, filepath: []const u8) !NeuronaWithBody {
        const neurona = try fs.readNeurona(allocator, filepath);
        const body = try fs.readBodyContent(allocator, filepath);
        errdefer allocator.free(body);

        return .{
            .neurona = neurona,
            .body = body,
            .filepath = try allocator.dupe(u8, filepath),
        };
    }

    /// Write neurona with validation and body preservation
    /// Wraps fs.writeNeurona with sensible defaults
    pub fn writeNeurona(allocator: Allocator, neurona: *const Neurona, filepath: []const u8) !void {
        // Default behavior: preserve body content
        try fs.writeNeurona(allocator, neurona.*, filepath, false);
    }

    /// Write neurona without preserving existing body content
    pub fn writeNeuronaForce(allocator: Allocator, neurona: *const Neurona, filepath: []const u8) !void {
        try fs.writeNeurona(allocator, neurona.*, filepath, true);
    }

    /// Delete neurona file with optional confirmation
    /// Returns error if file not found or cannot be deleted
    pub fn deleteNeurona(filepath: []const u8, verbose: bool) !void {
        // Delete the file
        try std.fs.cwd().deleteFile(filepath);

        if (verbose) {
            std.debug.print("Deleted: {s}\n", .{filepath});
        }
    }

    /// Delete neurona by ID (finds and deletes)
    pub fn deleteNeuronaById(allocator: Allocator, neuronas_dir: []const u8, id: []const u8, verbose: bool) !void {
        const filepath = try fs.findNeuronaPath(allocator, neuronas_dir, id);
        defer allocator.free(filepath);

        try deleteNeurona(filepath, verbose);
    }

    /// Check if a neurona file exists
    pub fn neuronaExists(allocator: Allocator, neuronas_dir: []const u8, id: []const u8) bool {
        const filepath = fs.findNeuronaPath(allocator, neuronas_dir, id) catch return false;
        defer allocator.free(filepath);

        return true;
    }

    /// List all neurona files in a directory
    pub fn listNeuronaFiles(allocator: Allocator, directory: []const u8) ![][]const u8 {
        return fs.listNeuronaFiles(allocator, directory);
    }

    /// Scan all neuronas in a directory
    pub fn scanNeuronas(allocator: Allocator, directory: []const u8) ![]Neurona {
        return fs.scanNeuronas(allocator, directory);
    }
};

// Tests
test "FileOps - readNeuronaWithBody" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_cortex_fileops";
    const neuronas_dir = "test_cortex_fileops/neuronas";
    try std.fs.cwd().makePath(neuronas_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test Neurona file
    const test_content =
        \\---
        \\id: test.001
        \\title: Test Neurona
        \\type: requirement
        \\tags:
        \\  - test
        \\---
        \\This is the body content.
        \\It can have multiple lines.
    ;
    const path = try std.fs.path.join(allocator, &.{ neuronas_dir, "test.001.md" });
    defer allocator.free(path);

    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = test_content });

    // Read with FileOps
    var result = try FileOps.readNeuronaWithBody(allocator, neuronas_dir, "test.001");
    defer result.deinit(allocator);

    // Verify results
    try std.testing.expectEqualStrings("test.001", result.neurona.id);
    try std.testing.expectEqualStrings("Test Neurona", result.neurona.title);
    try std.testing.expectEqualStrings("This is the body content.\nIt can have multiple lines.", result.body);
}

test "FileOps - readNeuronaWithBodyFromPath" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_cortex_fileops_path";
    const neuronas_dir = "test_cortex_fileops_path/neuronas";
    try std.fs.cwd().makePath(neuronas_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test Neurona file
    const test_content =
        \\---
        \\id: test.002
        \\title: Test 002
        \\type: issue
        \\---
        \\Body content here.
    ;
    const path = try std.fs.path.join(allocator, &.{ neuronas_dir, "test.002.md" });
    defer allocator.free(path);

    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = test_content });

    // Read from path
    var result = try FileOps.readNeuronaWithBodyFromPath(allocator, path);
    defer result.deinit(allocator);

    // Verify results
    try std.testing.expectEqualStrings("test.002", result.neurona.id);
    try std.testing.expectEqualStrings("Test 002", result.neurona.title);
    try std.testing.expectEqualStrings("Body content here.", result.body);
}

test "FileOps - deleteNeurona" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_cortex_delete_ops";
    const neuronas_dir = "test_cortex_delete_ops/neuronas";
    try std.fs.cwd().makePath(neuronas_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test Neurona file
    const test_content =
        \\---
        \\id: test.delete
        \\title: Test Delete
        \\type: requirement
        \\---
        \\Delete me.
    ;
    const path = try std.fs.path.join(allocator, &.{ neuronas_dir, "test.delete.md" });
    defer allocator.free(path);

    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = test_content });

    // Delete with FileOps
    try FileOps.deleteNeurona(path, true);

    // Verify file is deleted
    const result = std.fs.cwd().access(path, .{});
    try std.testing.expectError(error.FileNotFound, result);
}

test "FileOps - deleteNeuronaById" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_cortex_delete_by_id";
    const neuronas_dir = "test_cortex_delete_by_id/neuronas";
    try std.fs.cwd().makePath(neuronas_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test Neurona file
    const test_content =
        \\---
        \\id: test.deleteById
        \\title: Test Delete By ID
        \\type: requirement
        \\---
        \\Delete me by ID.
    ;
    const path = try std.fs.path.join(allocator, &.{ neuronas_dir, "test.deleteById.md" });
    defer allocator.free(path);

    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = test_content });

    // Delete by ID
    try FileOps.deleteNeuronaById(allocator, neuronas_dir, "test.deleteById", true);

    // Verify file is deleted
    const result = std.fs.cwd().access(path, .{});
    try std.testing.expectError(error.FileNotFound, result);
}

test "FileOps - neuronaExists" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_cortex_exists";
    const neuronas_dir = "test_cortex_exists/neuronas";
    try std.fs.cwd().makePath(neuronas_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test Neurona file
    const test_content =
        \\---
        \\id: test.exists
        \\title: Test Exists
        \\type: requirement
        \\---
        \\I exist.
    ;
    const path = try std.fs.path.join(allocator, &.{ neuronas_dir, "test.exists.md" });
    defer allocator.free(path);

    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = test_content });

    // Test existing neurona
    try std.testing.expectEqual(true, FileOps.neuronaExists(allocator, neuronas_dir, "test.exists"));

    // Test non-existent neurona
    try std.testing.expectEqual(false, FileOps.neuronaExists(allocator, neuronas_dir, "test.notexists"));
}
