//! Argument parsing utilities for CLI commands
//! Provides validation and parsing for command arguments

const std = @import("std");

/// Argument parser with validation
pub const ArgsParser = struct {
    /// Parse command arguments with validation
    pub fn parse(args: []const []const u8, options: ParseOptions) !ParsedArgs {
        if (options.require_command and args.len < 2) {
            return error.MissingCommand;
        }

        if (args.len < options.min_args + 1) {
            return error.MissingArguments;
        }

        const args_slice = args[1..];
        return ParsedArgs{
            .command = args[0],
            .args = args_slice,
        };
    }

    pub const ParseOptions = struct {
        min_args: usize = 0,
        max_args: usize = std.math.maxInt(usize),
        require_command: bool = true,
    };

    pub const ParsedArgs = struct {
        command: []const u8,
        args: []const []const u8,
    };
};

// ==================== Tests ====================

test "parse with command and args" {
    const args = [_][]const u8{ "command", "arg1", "arg2" };
    const options = ArgsParser.ParseOptions{
        .min_args = 2,
        .require_command = false,
    };

    const result = try ArgsParser.parse(&args, options);
    try std.testing.expectEqualStrings("command", result.command);
    try std.testing.expectEqual(@as(usize, 2), result.args.len);
}

test "parse requires command fails without command" {
    const args = [_][]const u8{"arg1"};
    const options = ArgsParser.ParseOptions{
        .require_command = true,
    };

    const result = ArgsParser.parse(&args, options);
    try std.testing.expectError(error.MissingCommand, result);
}

test "parse requires minimum args fails when too few" {
    const args = [_][]const u8{"command"};
    const options = ArgsParser.ParseOptions{
        .min_args = 2,
        .require_command = false,
    };

    const result = ArgsParser.parse(&args, options);
    try std.testing.expectError(error.MissingArguments, result);
}
