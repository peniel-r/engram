// File: src/utils/cli_parser.zig
// Generic CLI argument parser with helper functions

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Result of parsing arguments
pub fn ParseResult(comptime Config: type) type {
    return struct {
        /// The parsed config struct
        config: Config,
        /// Number of arguments consumed (including positionals)
        consumed_args: usize,
        /// Positional arguments (non-flag arguments)
        positionals: [][]const u8,
    };
}

/// Simple flag parser with helper functions for common patterns
pub const CliParser = struct {
    allocator: Allocator,
    command_name: []const u8,
    args: []const []const u8,
    start_idx: usize,

    /// Create a new CLI parser
    pub fn init(allocator: Allocator, command_name: []const u8, args: []const []const u8, start_idx: usize) CliParser {
        return CliParser{
            .allocator = allocator,
            .command_name = command_name,
            .args = args,
            .start_idx = start_idx,
        };
    }

    /// Parse and collect positional arguments
    pub fn parsePositionals(self: *CliParser) ![][]const u8 {
        var positionals = std.ArrayListUnmanaged([]const u8){};

        var i: usize = self.start_idx;
        while (i < self.args.len) : (i += 1) {
            const arg = self.args[i];

            // Skip flags
            if (std.mem.startsWith(u8, arg, "-")) {
                // Check if this flag takes a value (doesn't have '=' syntax)
                if (!std.mem.containsAtLeast(u8, arg, 1, "=")) {
                    // Skip the next argument if it exists and doesn't start with '-'
                    if (i + 1 < self.args.len and !std.mem.startsWith(u8, self.args[i + 1], "-")) {
                        i += 1; // Skip the flag's value
                    }
                }
                continue;
            }

            // Collect positional argument
            try positionals.append(self.allocator, arg);
        }

        return positionals.toOwnedSlice(self.allocator);
    }

    /// Check if a flag is present (boolean flags)
    pub fn hasFlag(self: *const CliParser, flag: []const u8, short: ?[]const u8) bool {
        var i: usize = self.start_idx;
        while (i < self.args.len) : (i += 1) {
            const arg = self.args[i];

            if (std.mem.eql(u8, arg, flag) or (short != null and std.mem.eql(u8, arg, short.?))) {
                return true;
            }
        }
        return false;
    }

    /// Get string value for a flag
    pub fn getStringFlag(self: *const CliParser, flag: []const u8, short: ?[]const u8) !?[]const u8 {
        var i: usize = self.start_idx;
        while (i < self.args.len) : (i += 1) {
            const arg = self.args[i];

            if (std.mem.eql(u8, arg, flag) or (short != null and std.mem.eql(u8, arg, short.?))) {
                i += 1;
                if (i >= self.args.len) {
                    std.debug.print("Error: Flag '{s}' requires a value\n", .{arg});
                    return error.MissingFlagValue;
                }
                return self.args[i];
            }

            // Check for --flag=value syntax
            if (std.mem.startsWith(u8, arg, flag) and arg.len > flag.len and arg[flag.len] == '=') {
                return arg[flag.len + 1 ..];
            }
        }
        return null;
    }

    /// Get numeric value for a flag
    pub fn getNumericFlag(self: *const CliParser, flag: []const u8, short: ?[]const u8, comptime T: type) !?T {
        const value_str = (try self.getStringFlag(flag, short)) orelse return null;
        return std.fmt.parseInt(T, value_str, 10) catch |err| {
            std.debug.print("Error: Invalid numeric value '{s}' for flag '{s}': {}\n", .{ value_str, flag, err });
            return err;
        };
    }

    /// Get enum value for a flag
    pub fn getEnumFlag(self: *const CliParser, flag: []const u8, short: ?[]const u8, comptime Enum: type, fromStringFn: fn ([]const u8) ?Enum) !?Enum {
        const value_str = (try self.getStringFlag(flag, short)) orelse return null;
        return fromStringFn(value_str) orelse {
            std.debug.print("Error: Invalid enum value '{s}' for flag '{s}'\n", .{ value_str, flag });
            return error.InvalidEnumValue;
        };
    }

    /// Validate argument count
    pub fn validateArgs(self: *const CliParser, min: usize, max: usize) !void {
        const count = self.args.len - self.start_idx;
        if (count < min) {
            std.debug.print("Error: Missing required arguments\n", .{});
            std.debug.print("Usage: {s}\n", .{self.command_name});
            std.process.exit(1);
        }
        if (max > 0 and count > max) {
            std.debug.print("Error: Too many arguments\n", .{});
            std.debug.print("Usage: {s}\n", .{self.command_name});
            std.process.exit(1);
        }
    }

    /// Report unknown flag
    pub fn reportUnknownFlag(self: *const CliParser, flag: []const u8) void {
        std.debug.print("Error: Unknown flag '{s}' for command '{s}'\n", .{ flag, self.command_name });
        std.debug.print("Use '{s} --help' for more information\n", .{self.command_name});
        std.process.exit(1);
    }
};

// ==================== Tests ====================
// Note: Due to Zig's type system limitations (cannot use @field with runtime strings),
// full generic parsing is not feasible.
//
// Future enhancement: When Zig 1.0+ adds better reflection support, we could
// create a more compact flag parsing approach using inline for loops to iterate
// over config struct fields.
//

test "CliParser - hasFlag" {
    const allocator = std.testing.allocator;

    var args = [_][]const u8{ "test", "subcommand", "--verbose", "--force" };
    var parser = CliParser.init(allocator, "test", &args, 2);

    try std.testing.expectEqual(true, parser.hasFlag("--verbose", "-v"));
    try std.testing.expectEqual(true, parser.hasFlag("--force", "-f"));
    try std.testing.expectEqual(false, parser.hasFlag("--output", "-o"));
}

test "CliParser - getStringFlag" {
    const allocator = std.testing.allocator;

    var args1 = [_][]const u8{ "test", "subcommand", "--output", "result.txt" };
    var parser1 = CliParser.init(allocator, "test", &args1, 2);

    const value1 = try parser1.getStringFlag("--output", "-o");
    try std.testing.expect(value1 != null);
    try std.testing.expectEqualStrings("result.txt", value1.?);

    // Test --flag=value syntax
    var args2 = [_][]const u8{ "test", "subcommand", "--output=result.txt" };
    var parser2 = CliParser.init(allocator, "test", &args2, 2);

    const value2 = try parser2.getStringFlag("--output", "-o");
    try std.testing.expect(value2 != null);
    try std.testing.expectEqualStrings("result.txt", value2.?);
}

test "CliParser - getNumericFlag" {
    const allocator = std.testing.allocator;

    var args = [_][]const u8{ "test", "subcommand", "--count", "42" };
    var parser = CliParser.init(allocator, "test", &args, 2);

    const value = try parser.getNumericFlag("--count", "-c", u8);
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(u8, 42), value.?);
}

test "CliParser - parsePositionals" {
    const allocator = std.testing.allocator;

    var args = [_][]const u8{ "test", "subcommand", "--verbose", "arg1", "arg2", "--force", "arg3" };
    var parser = CliParser.init(allocator, "test", &args, 2);

    const positionals = try parser.parsePositionals();
    defer allocator.free(positionals);

    try std.testing.expectEqual(@as(usize, 3), positionals.len);
    try std.testing.expectEqualStrings("arg1", positionals[0]);
    try std.testing.expectEqualStrings("arg2", positionals[1]);
    try std.testing.expectEqualStrings("arg3", positionals[2]);
}
