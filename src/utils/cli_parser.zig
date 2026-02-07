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

/// Parse flags using the legacy manual approach (for backward compatibility)
/// This is used during migration to the new parser
pub const LegacyParser = struct {
    args: []const []const u8,
    idx: *usize,

    pub fn parseFlag(args: []const []const u8, flag: []const u8, short: ?[]const u8, start: *usize) bool {
        if (start.* >= args.len) return false;

        const arg = args[start.*];

        if (std.mem.eql(u8, arg, flag) or (short != null and std.mem.eql(u8, arg, short.?))) {
            start.* += 1;
            return true;
        }
        return false;
    }

    pub fn parseStringFlag(allocator: Allocator, args: []const []const u8, flag: []const u8, short: ?[]const u8, start: *usize) !?[]const u8 {
        if (start.* >= args.len) return null;

        const arg = args[start.*];

        // Check for --flag=value syntax
        if (std.mem.startsWith(u8, arg, flag) and arg.len > flag.len and arg[flag.len] == '=') {
            start.* += 1;
            return try allocator.dupe(u8, arg[flag.len + 1 ..]);
        }

        if (std.mem.eql(u8, arg, flag) or (short != null and std.mem.eql(u8, arg, short.?))) {
            start.* += 1;
            if (start.* >= args.len) {
                std.debug.print("Error: Flag '{s}' requires a value\n", .{arg});
                return error.MissingFlagValue;
            }
            const value = args[start.*];
            start.* += 1;
            return try allocator.dupe(u8, value);
        }

        return null;
    }

    pub fn parseNumericFlag(args: []const []const u8, flag: []const u8, short: ?[]const u8, start: *usize, comptime T: type) !?T {
        if (start.* >= args.len) return null;

        const arg = args[start.*];

        if (std.mem.eql(u8, arg, flag) or (short != null and std.mem.eql(u8, arg, short.?))) {
            start.* += 1;
            if (start.* >= args.len) {
                std.debug.print("Error: Flag '{s}' requires a value\n", .{arg});
                return error.MissingFlagValue;
            }
            const value = args[start.*];
            start.* += 1;
            return std.fmt.parseInt(T, value, 10) catch |err| {
                std.debug.print("Error: Invalid numeric value '{s}' for flag '{s}': {}\n", .{ value, arg, err });
                return err;
            };
        }

        return null;
    }

    pub fn parseEnumFlag(args: []const []const u8, flag: []const u8, short: ?[]const u8, start: *usize, comptime Enum: type, fromStringFn: fn ([]const u8) ?Enum) !?Enum {
        if (start.* >= args.len) return null;

        const arg = args[start.*];

        if (std.mem.eql(u8, arg, flag) or (short != null and std.mem.eql(u8, arg, short.?))) {
            start.* += 1;
            if (start.* >= args.len) {
                std.debug.print("Error: Flag '{s}' requires a value\n", .{arg});
                return error.MissingFlagValue;
            }
            const value = args[start.*];
            start.* += 1;
            return fromStringFn(value) orelse {
                std.debug.print("Error: Invalid enum value '{s}' for flag '{s}'\n", .{ value, arg });
                return error.InvalidEnumValue;
            };
        }

        return null;
    }
};

/// Compact flag parser that significantly reduces boilerplate
/// Usage:
/// ```zig
/// try compactParseFlags(allocator, args, &i, &config, printXxxHelp, &.{
///     CompactFlag{ .name = "--verbose", .short = "-v", .field = &config.verbose },
///     CompactFlag{ .name = "--output", .field = &config.output },
/// });
/// ```
pub const CompactFlag = struct {
    name: []const u8,
    short: ?[]const u8 = null,
    field: anytype,
    parser: ?fn (*usize, []const u8) !void = null, // Optional custom parser for complex types
};

/// Helper function to parse flags in a compact way
pub fn compactParseFlags(allocator: Allocator, args: []const []const u8, start_idx: *usize, help_fn: *const fn () void, comptime flags: anytype) !void {
    _ = allocator; // Not used in this version
    while (start_idx.* < args.len) : (start_idx.* += 1) {
        const arg = args[start_idx.*];

        // Check if this is a flag
        if (!std.mem.startsWith(u8, arg, "-")) {
            return; // Stop at first non-flag
        }

        var found = false;

        inline for (flags) |flag| {
            if (std.mem.eql(u8, arg, flag.name) or (flag.short != null and std.mem.eql(u8, arg, flag.short.?))) {
                // Handle --flag=value syntax
                if (std.mem.indexOf(u8, arg, "=")) |eq_pos| {
                    const value = arg[eq_pos + 1 ..];
                    try setFlagValue(flag.field, value, flag.name, help_fn, flag.parser, start_idx, args);
                } else {
                    start_idx.* += 1;
                    if (start_idx.* >= args.len) {
                        std.debug.print("Error: Flag '{s}' requires a value\n", .{arg});
                        help_fn();
                        std.process.exit(1);
                    }
                    const value = args[start_idx.*];
                    try setFlagValue(flag.field, value, flag.name, help_fn, flag.parser, start_idx, args);
                }
                found = true;
                break;
            }
        }

        if (!found) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            help_fn();
            std.process.exit(1);
        }
    }
}

/// Set a flag value based on its type
fn setFlagValue(field: anytype, value: []const u8, flag_name: []const u8, help_fn: *const fn () void, parser: ?fn (*usize, []const u8) !void, idx: *usize, args: []const []const u8) !void {
    const FieldType = @TypeOf(field.*);

    if (FieldType == bool) {
        field.* = true;
    } else if (FieldType == ?[]const u8 or FieldType == []const u8) {
        field.* = value;
    } else if (std.math.Int(FieldType)) {
        field.* = std.fmt.parseInt(FieldType, value, 10) catch |err| {
            std.debug.print("Error: Invalid numeric value '{s}' for flag '{s}': {}\n", .{ value, flag_name, err });
            help_fn();
            std.process.exit(1);
        };
    } else if (parser != null) {
        // Use custom parser for complex types
        try parser.?(idx, value);
    } else {
        std.debug.print("Error: Unsupported type for flag '{s}'\n", .{flag_name});
        help_fn();
        std.process.exit(1);
    }
}

        var found = false;

        inline for (flags) |flag| {
            if (std.mem.eql(u8, arg, flag.name) or (flag.short != null and std.mem.eql(u8, arg, flag.short.?))) {
                // Handle --flag=value syntax
                if (std.mem.indexOf(u8, arg, "=")) |eq_pos| {
                    const value = arg[eq_pos + 1 ..];
                    try setFlagValue(flag.field, value, flag.name, help_fn);
                } else {
                    start_idx.* += 1;
                    if (start_idx.* >= args.len) {
                        std.debug.print("Error: Flag '{s}' requires a value\n", .{arg});
                        help_fn();
                        std.process.exit(1);
                    }
                    const value = args[start_idx.*];
                    try setFlagValue(flag.field, value, flag.name, help_fn);
                }
                found = true;
                break;
            }
        }

        if (!found) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            help_fn();
            std.process.exit(1);
        }
    }
}

/// Set a flag value based on its type
fn setFlagValue(field: anytype, value: []const u8, flag_name: []const u8, help_fn: *const fn () void) !void {
    const FieldType = @TypeOf(field.*);

    if (FieldType == bool) {
        field.* = true;
    } else if (FieldType == ?[]const u8 or FieldType == []const u8) {
        field.* = value;
    } else if (std.math.Int(FieldType)) {
        field.* = std.fmt.parseInt(FieldType, value, 10) catch |err| {
            std.debug.print("Error: Invalid numeric value '{s}' for flag '{s}': {}\n", .{ value, flag_name, err });
            help_fn();
            std.process.exit(1);
        };
    } else {
        std.debug.print("Error: Unsupported type for flag '{s}'\n", .{flag_name});
        help_fn();
        std.process.exit(1);
    }
}

// ==================== Tests ====================

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

test "LegacyParser - parseFlag" {
    var args = [_][]const u8{ "test", "subcommand", "--verbose", "--force" };
    var idx: usize = 2;

    try std.testing.expectEqual(true, LegacyParser.parseFlag(&args, "--verbose", "-v", &idx));
    try std.testing.expectEqual(@as(usize, 3), idx);

    try std.testing.expectEqual(true, LegacyParser.parseFlag(&args, "--force", "-f", &idx));
    try std.testing.expectEqual(@as(usize, 4), idx);

    try std.testing.expectEqual(false, LegacyParser.parseFlag(&args, "--output", "-o", &idx));
    try std.testing.expectEqual(@as(usize, 4), idx); // Should not increment
}

test "LegacyParser - parseStringFlag" {
    const allocator = std.testing.allocator;

    var args1 = [_][]const u8{ "test", "subcommand", "--output", "result.txt", "--force" };
    var idx1: usize = 2;

    const value1 = try LegacyParser.parseStringFlag(allocator, &args1, "--output", "-o", &idx1);
    try std.testing.expect(value1 != null);
    try std.testing.expectEqualStrings("result.txt", value1.?);
    allocator.free(value1.?);
    try std.testing.expectEqual(@as(usize, 4), idx1); // Should skip value

    // Test --flag=value syntax
    var args2 = [_][]const u8{ "test", "subcommand", "--output=result.txt", "--force" };
    var idx2: usize = 2;

    const value2 = try LegacyParser.parseStringFlag(allocator, &args2, "--output", "-o", &idx2);
    try std.testing.expect(value2 != null);
    try std.testing.expectEqualStrings("result.txt", value2.?);
    allocator.free(value2.?);
    try std.testing.expectEqual(@as(usize, 3), idx2); // Should skip only the flag
}

test "LegacyParser - parseNumericFlag" {
    var args = [_][]const u8{ "test", "subcommand", "--count", "42", "--force" };
    var idx: usize = 2;

    const value = try LegacyParser.parseNumericFlag(&args, "--count", "-c", &idx, u8);
    try std.testing.expect(value != null);
    try std.testing.expectEqual(@as(u8, 42), value.?);
    try std.testing.expectEqual(@as(usize, 4), idx); // Should skip value
}
