// Editor integration for opening files in external editors
// Cross-platform support for Windows, Linux, macOS
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Open file in system's default editor
/// Uses $EDITOR environment variable if set, otherwise uses platform default
pub fn open(allocator: Allocator, path: []const u8) !void {
    const editor = try getEditorCommand(allocator);
    defer allocator.free(editor);

    const command = try buildCommand(allocator, editor, path);
    defer allocator.free(command);

    return runCommand(allocator, command);
}

/// Get editor command from environment or platform default
fn getEditorCommand(allocator: Allocator) ![]const u8 {
    // Check environment variable first
    if (std.process.getEnvVarOwned(allocator, "EDITOR")) |editor_env| {
        return editor_env;
    } else |_| {
        // Use platform default (allocator will dup if needed)
        const default_editor = getPlatformDefault();
        return allocator.dupe(u8, default_editor);
    }
}

/// Get platform-specific default editor (string literal)
fn getPlatformDefault() []const u8 {
    const os_tag = builtin.os.tag;

    return switch (os_tag) {
        .windows => "notepad",
        .linux => "vim",
        .macos => "vim",
        else => "unknown",
    };
}

/// Build command string for execution
fn buildCommand(allocator: Allocator, editor: []const u8, path: []const u8) ![]const u8 {
    // Escape path with spaces
    const escaped_path = if (std.mem.indexOfScalar(u8, path, ' ') != null)
        try std.fmt.allocPrint(allocator, "\"{s}\"", .{path})
    else
        try allocator.dupe(u8, path);
    defer allocator.free(escaped_path);

    return std.fmt.allocPrint(allocator, "{s} {s}", .{ editor, escaped_path });
}

/// Run command and wait for completion
fn runCommand(allocator: Allocator, command: []const u8) !void {
    const os_tag = builtin.os.tag;

    return switch (os_tag) {
        .windows => runWindows(allocator, command),
        .linux, .macos => runUnix(allocator, command),
        else => error.UnsupportedPlatform,
    };
}

/// Run command on Windows
fn runWindows(allocator: Allocator, command: []const u8) !void {
    const argv = try parseCommandArgs(allocator, command);
    defer {
        for (argv) |arg| allocator.free(arg);
        allocator.free(argv);
    }

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    _ = result.term; // Wait for completion
}

/// Run command on Unix (Linux, macOS)
fn runUnix(allocator: Allocator, command: []const u8) !void {
    // Use sh -c to execute command
    const argv = [_][]const u8{ "sh", "-c", command };

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &argv,
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    _ = result.term; // Wait for completion
}

/// Parse command string into argv array
fn parseCommandArgs(allocator: Allocator, command: []const u8) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8){};
    defer result.deinit(allocator);

    var in_quotes = false;
    var start_idx: usize = 0;

    for (command, 0..) |c, i| {
        if (c == '"') {
            in_quotes = !in_quotes;
        } else if (std.ascii.isWhitespace(c) and !in_quotes) {
            if (start_idx < i) {
                const arg = try allocator.dupe(u8, command[start_idx..i]);
                try result.append(allocator, arg);
            }
            start_idx = i + 1;
        }
    }

    // Add last arg
    if (start_idx < command.len) {
        const arg = try allocator.dupe(u8, command[start_idx..]);
        try result.append(allocator, arg);
    }

    return result.toOwnedSlice(allocator);
}

const builtin = @import("builtin");

test "getPlatformDefault returns editor for OS" {
    const allocator = std.testing.allocator;

    const default_editor = getPlatformDefault();
    const editor = try allocator.dupe(u8, default_editor);
    defer allocator.free(editor);

    // Should return a valid editor name
    try std.testing.expect(editor.len > 0);
}

test "parseCommandArgs splits command correctly" {
    const allocator = std.testing.allocator;

    const command = "notepad \"C:\\test file.txt\"";
    const argv = try parseCommandArgs(allocator, command);
    defer {
        for (argv) |arg| allocator.free(arg);
        allocator.free(argv);
    }

    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings("notepad", argv[0]);
    // With quotes, the quotes are preserved
    try std.testing.expectEqualStrings("\"C:\\test file.txt\"", argv[1]);
}

test "parseCommandArgs handles simple command" {
    const allocator = std.testing.allocator;

    const command = "vim test.txt";
    const argv = try parseCommandArgs(allocator, command);
    defer {
        for (argv) |arg| allocator.free(arg);
        allocator.free(argv);
    }

    try std.testing.expectEqual(@as(usize, 2), argv.len);
    try std.testing.expectEqualStrings("vim", argv[0]);
    try std.testing.expectEqualStrings("test.txt", argv[1]);
}

test "parseCommandArgs handles multiple args" {
    const allocator = std.testing.allocator;

    const command = "code -r --wait test.txt";
    const argv = try parseCommandArgs(allocator, command);
    defer {
        for (argv) |arg| allocator.free(arg);
        allocator.free(argv);
    }

    try std.testing.expectEqual(@as(usize, 4), argv.len);
    try std.testing.expectEqualStrings("code", argv[0]);
    try std.testing.expectEqualStrings("-r", argv[1]);
    try std.testing.expectEqualStrings("--wait", argv[2]);
    try std.testing.expectEqualStrings("test.txt", argv[3]);
}

test "buildCommand escapes paths with spaces" {
    const allocator = std.testing.allocator;

    const command = try buildCommand(allocator, "vim", "C:\\test file.txt");
    defer allocator.free(command);

    try std.testing.expectEqualStrings("vim \"C:\\test file.txt\"", command);
}

test "buildCommand handles paths without spaces" {
    const allocator = std.testing.allocator;

    const command = try buildCommand(allocator, "vim", "test.txt");
    defer allocator.free(command);

    try std.testing.expectEqualStrings("vim test.txt", command);
}
