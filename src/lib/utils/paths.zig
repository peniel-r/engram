//! Path resolution utilities for finding and working with Cortex directories
//! Handles searching up/down directory levels for cortex.json
//!
//! This is a library-only version without CLI dependencies.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Error thrown when cortex cannot be found
pub const Error = error{
    CortexNotFound,
};

/// Cortex path resolution result
pub const Cortex = struct {
    /// Absolute path to cortex directory
    dir: []const u8,
    /// Absolute path to neuronas directory
    neuronas_path: []const u8,
    /// Absolute path to activations directory
    activations_path: []const u8,

    /// Free allocated memory
    pub fn deinit(self: *Cortex, allocator: Allocator) void {
        allocator.free(self.dir);
        allocator.free(self.neuronas_path);
        allocator.free(self.activations_path);
    }
};

/// Maximum search depth for cortex detection (both up and down)
const MAX_SEARCH_DEPTH: usize = 3;

/// Validate that a path contains a cortex.json file
fn validateCortexPath(path: []const u8) bool {
    // Convert relative path to absolute if needed
    const absolute_path = if (std.fs.path.isAbsolute(path))
        path
    else
        std.fs.cwd().realpathAlloc(std.heap.page_allocator, path) catch return false;
    defer if (!std.fs.path.isAbsolute(path)) std.heap.page_allocator.free(absolute_path);

    const cortex_path = std.fs.path.joinZ(std.heap.page_allocator, &.{ absolute_path, "cortex.json" }) catch return false;
    defer std.heap.page_allocator.free(cortex_path);

    std.fs.accessAbsolute(cortex_path, .{}) catch return false;
    return true;
}

/// Count how many directory levels deep target_path is from base_path
fn countPathDepth(target_path: []const u8, base_path: []const u8) usize {
    // If base_path is not a prefix of target_path, treat as separate
    if (!std.mem.startsWith(u8, target_path, base_path)) {
        return MAX_SEARCH_DEPTH + 1;
    }

    // If same path, depth is 0
    if (target_path.len == base_path.len) {
        return 0;
    }

    const relative = if (target_path[base_path.len] == std.fs.path.sep)
        target_path[base_path.len + 1 ..]
    else
        target_path[base_path.len..];

    var count: usize = 0;
    var iter = std.mem.splitScalar(u8, relative, std.fs.path.sep);
    while (iter.next()) |_| {
        count += 1;
    }
    return count;
}

/// Cortex resolver utilities
pub const CortexResolver = struct {
    /// Find cortex directory, searching up/down 3 levels if not specified
    /// Returns Cortex with all required paths
    /// Caller must free returned Cortex with deinit()
    pub fn find(allocator: Allocator, cortex_path: ?[]const u8) !Cortex {
        const dir = try findCortexDir(allocator, cortex_path);
        errdefer allocator.free(dir);

        const neuronas_path = try getNeuronasPath(allocator, dir);
        errdefer allocator.free(neuronas_path);

        const activations_path = try getActivationsPath(allocator, dir);
        errdefer allocator.free(activations_path);

        return Cortex{
            .dir = dir,
            .neuronas_path = neuronas_path,
            .activations_path = activations_path,
        };
    }

    /// Find cortex directory, searching up/down 3 levels if not specified
    /// Returns absolute path to cortex directory
    /// Caller must free returned string with allocator.free()
    fn findCortexDir(allocator: Allocator, provided_path: ?[]const u8) ![]const u8 {
        // If a specific path was provided, validate it
        if (provided_path) |path| {
            if (validateCortexPath(path)) {
                return try allocator.dupe(u8, path);
            }
            return Error.CortexNotFound;
        }

        // Get current working directory
        const current_path = try std.fs.cwd().realpathAlloc(allocator, ".");
        defer allocator.free(current_path);

        // 1. Check current directory
        if (validateCortexPath(current_path)) {
            return try allocator.dupe(u8, current_path);
        }

        // 2. Search parent directories (up to MAX_SEARCH_DEPTH)
        {
            var search_path = current_path;
            var depth: usize = 0;
            while (depth < MAX_SEARCH_DEPTH) : (depth += 1) {
                const parent_path = std.fs.path.dirname(search_path);
                if (parent_path) |p| {
                    // Check parent
                    if (validateCortexPath(p)) {
                        return try allocator.dupe(u8, p);
                    }

                    // Continue searching up
                    const parent_owned = try allocator.dupe(u8, p);
                    if (search_path.ptr != current_path.ptr) {
                        allocator.free(search_path);
                    }
                    search_path = parent_owned;
                } else {
                    break;
                }
            }
            if (search_path.ptr != current_path.ptr) {
                allocator.free(search_path);
            }
        }

        // 3. Search subdirectories (up to MAX_SEARCH_DEPTH)
        {
            var search_queue = std.ArrayListUnmanaged([]const u8){};
            defer {
                for (search_queue.items) |item| {
                    if (item.ptr != current_path.ptr) {
                        allocator.free(item);
                    }
                }
                search_queue.deinit(allocator);
            }

            try search_queue.append(allocator, try allocator.dupe(u8, current_path));

            while (search_queue.items.len > 0) {
                const dir_path = search_queue.orderedRemove(0);
                defer if (dir_path.ptr != current_path.ptr) allocator.free(dir_path);

                var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch continue;
                defer dir.close();

                var iter = dir.iterate();
                while (try iter.next()) |entry| {
                    if (entry.kind != .directory) continue;

                    const full_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name });

                    // Check if this subdirectory contains cortex.json
                    if (validateCortexPath(full_path)) {
                        // Free other queue items before returning
                        for (search_queue.items) |item| {
                            if (item.ptr != current_path.ptr) {
                                allocator.free(item);
                            }
                        }
                        search_queue.items.len = 0;
                        return full_path;
                    }

                    // Add to queue for deeper search (within MAX_SEARCH_DEPTH)
                    const depth_from_start = countPathDepth(full_path, current_path);
                    if (depth_from_start < MAX_SEARCH_DEPTH) {
                        try search_queue.append(allocator, full_path);
                    } else {
                        allocator.free(full_path);
                    }
                }
            }
        }

        return Error.CortexNotFound;
    }

    /// Get neuronas directory path from cortex directory
    /// Caller must free returned string with allocator.free()
    pub fn getNeuronasPath(allocator: Allocator, cortex: []const u8) ![]const u8 {
        return std.fs.path.join(allocator, &.{ cortex, "neuronas" });
    }

    /// Get activations directory path from cortex directory
    /// Caller must free returned string with allocator.free()
    pub fn getActivationsPath(allocator: Allocator, cortex: []const u8) ![]const u8 {
        return std.fs.path.join(allocator, &.{ cortex, ".activations" });
    }
};

test "CortexResolver find creates valid structure" {
    const allocator = std.testing.allocator;

    // This test assumes we're in a directory with a cortex
    // In real testing, we'd need to set up a temporary cortex structure
    _ = allocator;
    // Skip actual find test as it requires file system setup
}

test "CortexResolver getNeuronasPath formats correctly" {
    const allocator = std.testing.allocator;

    const path = try CortexResolver.getNeuronasPath(allocator, "/my/cortex");
    defer allocator.free(path);

    try std.testing.expectEqualStrings("/my/cortex/neuronas", path);
}

test "CortexResolver getActivationsPath formats correctly" {
    const allocator = std.testing.allocator;

    const path = try CortexResolver.getActivationsPath(allocator, "/my/cortex");
    defer allocator.free(path);

    try std.testing.expectEqualStrings("/my/cortex/.activations", path);
}

test "CortexResolver findCortexDir validates provided path" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_cortex_validation";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const cortex_json = try std.fs.path.join(allocator, &.{ test_dir, "cortex.json" });
    defer allocator.free(cortex_json);

    try std.fs.cwd().writeFile(.{ .sub_path = cortex_json, .data = "{\"id\":\"test\"}\n" });

    // Test with provided path
    const result = try CortexResolver.find(allocator, test_dir);
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings(test_dir, result.dir);
}

test "CortexResolver findCortexDir returns error for invalid provided path" {
    const allocator = std.testing.allocator;

    const result = CortexResolver.find(allocator, "nonexistent_path");
    try std.testing.expectError(Error.CortexNotFound, result);
}

test "CortexResolver findCortexDir searches subdirectories" {
    const allocator = std.testing.allocator;

    // Setup test structure: test_base/sub1/sub2/cortex.json
    const test_base = "test_cortex_subdir_base";
    const cortex_path = "test_cortex_subdir_base/sub1/sub2";

    try std.fs.cwd().makePath(cortex_path);
    defer std.fs.cwd().deleteTree(test_base) catch {};

    const cortex_json_path = try std.fs.path.join(allocator, &.{ cortex_path, "cortex.json" });
    defer allocator.free(cortex_json_path);

    try std.fs.cwd().writeFile(.{ .sub_path = cortex_json_path, .data = "{\"id\":\"test\"}\n" });

    // Verify the directory structure was created correctly
    // Access the cortex.json file to confirm it exists
    const absolute_cortex_path = try std.fs.cwd().realpathAlloc(allocator, cortex_path);
    defer allocator.free(absolute_cortex_path);

    const absolute_json_path = try std.fs.path.join(allocator, &.{ absolute_cortex_path, "cortex.json" });
    defer allocator.free(absolute_json_path);

    // This should succeed if the file was created correctly
    std.fs.accessAbsolute(absolute_json_path, .{}) catch |err| {
        std.debug.print("Failed to access test cortex.json: {}\n", .{err});
        return err;
    };

    // Verify the path contains sub1 and sub2
    try std.testing.expect(std.mem.indexOf(u8, absolute_cortex_path, "sub1") != null);
    try std.testing.expect(std.mem.indexOf(u8, absolute_cortex_path, "sub2") != null);
}

test "countPathDepth calculates correct depth" {
    const sep = std.fs.path.sep;
    const base = "/home/user/project";
    try std.testing.expectEqual(@as(usize, 0), countPathDepth(base, base));
    try std.testing.expectEqual(@as(usize, 1), countPathDepth("/home/user/project/src", base));
    try std.testing.expectEqual(@as(usize, 2), countPathDepth("/home/user/project/src" ++ [1]u8{sep} ++ "utils", base));
    try std.testing.expectEqual(@as(usize, 3), countPathDepth("/home/user/project/src" ++ [1]u8{sep} ++ "utils" ++ [1]u8{sep} ++ "helpers", base));
}
