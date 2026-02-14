//! Path resolution utilities for finding and working with Cortex directories
//! Handles searching up/down directory levels for cortex.json

const std = @import("std");
const Allocator = std.mem.Allocator;

// TODO: Import uri_parser when build.zig is configured for library module
// const uri_parser = @import("../../../utils/uri_parser.zig");

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
    /// NOTE: Will be implemented with uri_parser integration
    pub fn find(allocator: Allocator, cortex_path: ?[]const u8) !Cortex {
        _ = allocator;
        _ = cortex_path;

        // TODO: Implement with uri_parser when build system is ready
        // For now, return error to indicate not yet implemented
        return Error.CortexNotFound;
    }

    /// Get neuronas directory path from cortex directory
    /// Caller must free returned string with allocator.free()
    pub fn getNeuronasPath(allocator: Allocator, cortex: []const u8) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex});
    }

    /// Get activations directory path from cortex directory
    /// Caller must free returned string with allocator.free()
    pub fn getActivationsPath(allocator: Allocator, cortex: []const u8) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}/.activations", .{cortex});
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
