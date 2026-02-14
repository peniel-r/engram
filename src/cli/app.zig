//! Application context for CLI commands
//! Provides shared cortex resolution and configuration management
//! Uses lib/utils/paths.zig.CortexResolver from Phase 1-2 library

const std = @import("std");
const Allocator = std.mem.Allocator;
const CortexResolver = @import("../../lib/root.zig").utils.CortexResolver;

/// Application configuration
pub const AppConfig = struct {
    verbose: bool = false,
    json_output: bool = false,
    editor: []const u8 = "hx",
};

/// Application context for CLI commands
pub const App = struct {
    allocator: Allocator,
    cortex_dir: ?[]const u8 = null,
    neuronas_dir: ?[]const u8 = null,
    config: AppConfig,

    /// Initialize application
    pub fn init(allocator: Allocator) !App {
        return App{
            .allocator = allocator,
            .cortex_dir = null,
            .neuronas_dir = null,
            .config = AppConfig{},
        };
    }

    /// Clean up resources
    pub fn deinit(self: *App) void {
        if (self.cortex_dir) |dir| self.allocator.free(dir);
        if (self.neuronas_dir) |dir| self.allocator.free(dir);
    }

    /// Resolve cortex directory
    pub fn resolveCortex(self: *App) !void {
        if (self.cortex_dir == null) {
            self.cortex_dir = try CortexResolver.find(self.allocator, null);
        }
    }

    /// Get neuronas directory
    pub fn getNeuronasDir(self: *App) ![]const u8 {
        if (self.neuronas_dir == null) {
            _ = try self.resolveCortex();
        }
        return try std.fmt.allocPrint(self.allocator, "{s}/neuronas", .{self.cortex_dir.?});
    }

    /// Get activations directory
    pub fn getActivationsDir(self: *App) ![]const u8 {
        _ = try self.resolveCortex();
        return try std.fmt.allocPrint(self.allocator, "{s}/activations", .{self.cortex_dir.?});
    }

    /// Initialize storage (placeholder - actual storage init is in storage module)
    pub fn initStorage(self: *App) !void {
        _ = try self.resolveCortex();
    }

    /// Clean up storage (placeholder)
    pub fn deinitStorage(self: *App) void {
        _ = self;
    }
};

// ==================== Tests ====================

test "App init creates default config" {
    const allocator = std.testing.allocator;

    const app = try App.init(allocator);
    defer app.deinit();

    try std.testing.expectEqual(allocator, app.allocator);
    try std.testing.expectEqual(@as(?[]const u8, null), app.cortex_dir);
    try std.testing.expectEqual(@as(?[]const u8, null), app.neuronas_dir);
    try std.testing.expectEqual(AppConfig{}, app.config);
}

test "App deinit frees resources" {
    const allocator = std.testing.allocator;

    const app = try App.init(allocator);

    const test_dir = try allocator.dupe(u8, "test_cortex");
    app.cortex_dir = test_dir;
    app.neuronas_dir = try allocator.dupe(u8, "test_neuronas");
    app.config = AppConfig{ .verbose = true, .json_output = true, .editor = "vi" };

    app.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), app.cortex_dir);
    try std.testing.expectEqual(@as(?[]const u8, null), app.neuronas_dir);
}
