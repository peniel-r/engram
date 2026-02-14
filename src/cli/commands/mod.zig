//! Command registry for CLI
//! Centralizes command metadata and provides lookup functionality

const std = @import("std");
const Allocator = std.mem.Allocator;
const App = @import("../app.zig").App;

/// Command category
pub const CommandCategory = enum {
    core,
    query,
    management,
    output,
};

/// Command definition
pub const Command = struct {
    name: []const u8,
    description: []const u8,
    category: CommandCategory,
    execute: *const fn (app: *App, args: []const []const u8) anyerror!void,
    min_args: usize = 0,
    flags: []const []const u8 = &[0][]const u8{},
};

/// Command registry
pub const Registry = struct {
    commands: []const Command,

    /// Initialize command registry
    pub fn init(cmds: []const Command) Registry {
        return Registry{
            .commands = cmds,
        };
    }

    /// Find command by name
    pub fn find(self: *const Registry, name: []const u8) ?Command {
        for (self.commands) |cmd| {
            if (std.mem.eql(u8, cmd.name, name)) {
                return cmd;
            }
        }
        return null;
    }

    /// List all commands
    pub fn list(self: *const Registry) []const Command {
        return self.commands;
    }

    /// Get commands by category
    pub fn getByCategory(self: *const Registry, category: CommandCategory) []const Command {
        var result = std.ArrayList(Command).init(std.heap.page_allocator);
        defer result.deinit();

        for (self.commands) |cmd| {
            if (cmd.category == category) {
                result.append(cmd) catch {};
            }
        }

        return result.toOwnedSlice() catch &[0]Command{};
    }
};

// ==================== Tests ====================

test "find returns command when found" {
    const test_cmd = Command{
        .name = "test",
        .description = "Test command",
        .category = .core,
        .execute = struct {
            fn fnImpl(_: *App, _: []const []const u8) !void {}
        }.fnImpl,
    };

    const commands = [_]Command{test_cmd};
    const registry = Registry.init(&commands);

    const result = registry.find("test");

    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("test", result.?.name);
}

test "find returns null when not found" {
    const test_cmd = Command{
        .name = "test",
        .description = "Test command",
        .category = .core,
        .execute = struct {
            fn fnImpl(_: *App, _: []const []const u8) !void {}
        }.fnImpl,
    };

    const commands = [_]Command{test_cmd};
    const registry = Registry.init(&commands);

    const result = registry.find("nonexistent");

    try std.testing.expect(result == null);
}

test "list returns all commands" {
    const cmd1 = Command{
        .name = "cmd1",
        .description = "Command 1",
        .category = .core,
        .execute = struct {
            fn fnImpl(_: *App, _: []const []const u8) !void {}
        }.fnImpl,
    };

    const cmd2 = Command{
        .name = "cmd2",
        .description = "Command 2",
        .category = .query,
        .execute = struct {
            fn fnImpl(_: *App, _: []const []const u8) !void {}
        }.fnImpl,
    };

    const commands = [_]Command{ cmd1, cmd2 };
    const registry = Registry.init(&commands);

    const result = registry.list();

    try std.testing.expectEqual(@as(usize, 2), result.len);
}
