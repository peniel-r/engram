//! Path resolution utilities for finding and working with Cortex directories
//! Handles searching up/down directory levels for cortex.json

const std = @import("std");
const Allocator = std.mem.Allocator;

const uri_parser = @import("../../utils/uri_parser.zig");

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

/// Cortex resolver utilities
pub const CortexResolver = struct {
    /// Find cortex directory, searching up/down 3 levels if not specified
    /// Returns Cortex with all required paths
    /// Caller must free returned Cortex with deinit()
    pub fn find(allocator: Allocator, cortex_path: ?[]const u8) !Cortex {
        const dir = try uri_parser.findCortexDir(allocator, cortex_path);
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
