//! Help generation utilities for CLI
//! Auto-generates help text from command metadata

const std = @import("std");
const Registry = @import("../commands/mod.zig").Registry;
const Command = @import("../commands/mod.zig").Command;

/// Help generator
pub const HelpGenerator = struct {
    /// Print command help
    pub fn printCommandHelp(command: Command) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("\n{s}\n\n", .{command.description});
        try stdout.print("Usage: engram {s}", .{command.name});

        if (command.min_args > 0) {
            try stdout.print(" <args>", .{});
        }

        for (command.flags) |flag| {
            try stdout.print(" [{s}]", .{flag});
        }

        try stdout.print("\n\n", .{});
        try stdout.flush();
    }

    /// Print general usage
    pub fn printUsage(registry: *const Registry) !void {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("\nEngram - ALM Tool\n", .{});
        try stdout.print("Usage: engram <command> [options]\n\n", .{});
        try stdout.print("Commands:\n", .{});

        for (registry.list()) |cmd| {
            try stdout.print("  {s:<20} {s}\n", .{ cmd.name, cmd.description });
        }

        try stdout.print("\nFor more information on a specific command, run:\n", .{});
        try stdout.print("  engram <command> --help\n\n", .{});
        try stdout.flush();
    }

    /// Print help for all commands
    pub fn printAllCommands(registry: *const Registry) !void {
        const commands = registry.list();

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("\nEngram Command Reference\n", .{});
        try stdout.print("={s}\n\n", .{"=" ** 23});

        for (commands) |cmd| {
            try stdout.print("{s}\n", .{cmd.name});
            try stdout.print("{s}\n", .{"-" ** cmd.name.len});
            try stdout.print("{s}\n\n", .{cmd.description});
            try stdout.print("Usage: engram {s}\n\n", .{cmd.name});
        }

        try stdout.flush();
    }
};

// ==================== Tests ====================

test "printCommandHelp prints formatted help" {
    const test_cmd = Command{
        .name = "test",
        .description = "Test command for help",
        .category = .core,
        .execute = struct {
            fn fnImpl(_: *anyopaque, _: []const []const u8) !void {}
        }.fnImpl,
        .min_args = 1,
        .flags = &[_][]const u8{"--verbose"},
    };

    try HelpGenerator.printCommandHelp(test_cmd);

    try std.testing.expect(true);
}

test "printUsage prints general help" {
    const cmd1 = Command{
        .name = "cmd1",
        .description = "Command 1",
        .category = .core,
        .execute = struct {
            fn fnImpl(_: *anyopaque, _: []const []const u8) !void {}
        }.fnImpl,
    };

    const cmd2 = Command{
        .name = "cmd2",
        .description = "Command 2",
        .category = .query,
        .execute = struct {
            fn fnImpl(_: *anyopaque, _: []const []const u8) !void {}
        }.fnImpl,
    };

    const commands = [_]Command{ cmd1, cmd2 };
    const registry = Registry.init(&commands);

    try HelpGenerator.printUsage(&registry);

    try std.testing.expect(true);
}
