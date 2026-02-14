//! Flag parsing utilities for CLI commands
//! Provides unified flag parsing to eliminate duplication
//! Parse comptime flag specifications from command-line arguments

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Flag parser with comptime specification
pub const FlagParser = struct {
    /// Parse flags from command-line arguments
    pub fn parse(comptime spec: []const FlagSpec, args: []const []const u8, allocator: Allocator) !ParsedFlags {
        var flags = std.StringHashMap(?FlagValue).init(allocator);
        var positionals = std.ArrayListUnmanaged([]const u8){};

        var i: usize = 0;
        while (i < args.len) {
            const arg = args[i];

            if (std.mem.startsWith(u8, arg, "--")) {
                const flag_name = arg[2..];
                const spec_index = findSpec(spec, flag_name);

                if (spec_index) |idx| {
                    const flag_spec = spec[idx];

                    if (flag_spec.takes_value) {
                        if (i + 1 >= args.len) {
                            return error.MissingFlagValue;
                        }
                        i += 1;
                        const value = args[i];
                        try flags.put(flag_name, FlagValue{ .string = try allocator.dupe(u8, value) });
                    } else {
                        try flags.put(flag_name, FlagValue{ .bool = true });
                    }
                } else {
                    return error.UnknownFlag;
                }
            } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.startsWith(u8, arg, "--")) {
                const short_name = arg[1..];
                const spec_index = findShortSpec(spec, short_name);

                if (spec_index) |idx| {
                    const flag_spec = spec[idx];

                    if (flag_spec.takes_value) {
                        if (i + 1 >= args.len) {
                            return error.MissingFlagValue;
                        }
                        i += 1;
                        const value = args[i];
                        try flags.put(flag_spec.name, FlagValue{ .string = try allocator.dupe(u8, value) });
                    } else {
                        try flags.put(flag_spec.name, FlagValue{ .bool = true });
                    }
                } else {
                    return error.UnknownFlag;
                }
            } else {
                try positionals.append(allocator, try allocator.dupe(u8, arg));
            }

            i += 1;
        }

        return ParsedFlags{
            .flags = flags,
            .positionals = try positionals.toOwnedSlice(allocator),
        };
    }

    fn findSpec(comptime spec: []const FlagSpec, name: []const u8) ?usize {
        for (spec, 0..) |flag, idx| {
            if (std.mem.eql(u8, flag.name, name)) {
                return idx;
            }
        }
        return null;
    }

    fn findShortSpec(comptime spec: []const FlagSpec, short: []const u8) ?usize {
        for (spec, 0..) |flag, idx| {
            if (flag.short) |s| {
                if (std.mem.eql(u8, s, short)) {
                    return idx;
                }
            }
        }
        return null;
    }

    /// Flag specification
    pub const FlagSpec = struct {
        name: []const u8,
        short: ?[]const u8 = null,
        takes_value: bool = false,
        description: []const u8 = "",
        default_value: ?FlagValue = null,
        required: bool = false,
    };

    /// Flag value type
    pub const FlagValue = union(enum) {
        string: []const u8,
        number: i64,
        bool: bool,
        list: [][]const u8,
    };

    /// Parsed flags result
    pub const ParsedFlags = struct {
        flags: std.StringHashMap(?FlagValue),
        positionals: [][]const u8,

        pub fn deinit(self: *ParsedFlags, allocator: Allocator) void {
            var it = self.flags.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.*) |val| {
                    switch (val) {
                        .string => |s| allocator.free(s),
                        .list => |list| {
                            for (list) |item| {
                                allocator.free(item);
                            }
                            allocator.free(list);
                        },
                        else => {},
                    }
                }
            }
            self.flags.deinit();
            for (self.positionals) |p| {
                allocator.free(p);
            }
            allocator.free(self.positionals);
        }

        /// Get flag value by name
        pub fn getFlag(self: *const ParsedFlags, name: []const u8) ?FlagValue {
            return self.flags.get(name) orelse null;
        }

        /// Get flag as string
        pub fn getString(self: *const ParsedFlags, name: []const u8) ?[]const u8 {
            if (self.getFlag(name)) |val| {
                if (val == .string) return val.string;
            }
            return null;
        }

        /// Get flag as number
        pub fn getNumber(self: *const ParsedFlags, name: []const u8) ?i64 {
            if (self.getFlag(name)) |val| {
                if (val == .number) return val.number;
            }
            return null;
        }

        /// Get flag as bool
        pub fn getBool(self: *const ParsedFlags, name: []const u8) bool {
            if (self.getFlag(name)) |val| {
                if (val == .bool) return val.bool;
            }
            return false;
        }

        /// Check if flag was provided
        pub fn hasFlag(self: *const ParsedFlags, name: []const u8) bool {
            return self.flags.get(name) != null;
        }
    };
};

// ==================== Tests ====================

test "parse boolean flags" {
    const allocator = std.testing.allocator;

    const spec = [_]FlagParser.FlagSpec{
        .{ .name = "verbose", .short = "v" },
        .{ .name = "force", .short = "f" },
    };

    const args = [_][]const u8{ "--verbose", "-f" };
    var result = try FlagParser.parse(&spec, &args, allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(true, result.getBool("verbose"));
    try std.testing.expectEqual(true, result.getBool("force"));
}

test "parse string flags with values" {
    const allocator = std.testing.allocator;

    const spec = [_]FlagParser.FlagSpec{
        .{ .name = "type", .short = "t", .takes_value = true },
        .{ .name = "output", .takes_value = true },
    };

    const args = [_][]const u8{ "--type", "requirement", "--output", "result.json" };
    var result = try FlagParser.parse(&spec, &args, allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings("requirement", result.getString("type").?);
    try std.testing.expectEqualStrings("result.json", result.getString("output").?);
}

test "parse positional arguments" {
    const allocator = std.testing.allocator;

    const spec = [_]FlagParser.FlagSpec{
        .{ .name = "verbose", .short = "v" },
    };

    const args = [_][]const u8{ "--verbose", "arg1", "arg2" };
    var result = try FlagParser.parse(&spec, &args, allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.positionals.len);
    try std.testing.expectEqualStrings("arg1", result.positionals[0]);
    try std.testing.expectEqualStrings("arg2", result.positionals[1]);
}

test "hasFlag returns true for provided flags" {
    const allocator = std.testing.allocator;

    const spec = [_]FlagParser.FlagSpec{
        .{ .name = "verbose" },
    };

    const args = [_][]const u8{"--verbose"};
    var result = try FlagParser.parse(&spec, &args, allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(true, result.hasFlag("verbose"));
}

test "hasFlag returns false for missing flags" {
    const allocator = std.testing.allocator;

    const spec = [_]FlagParser.FlagSpec{
        .{ .name = "verbose" },
    };

    const args = [_][]const u8{};
    var result = try FlagParser.parse(&spec, &args, allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(false, result.hasFlag("verbose"));
}
