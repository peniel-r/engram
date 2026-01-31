const std = @import("std");
const Allocator = std.mem.Allocator;
const yaml_parser = @import("yaml.zig");

pub const Config = struct {
    editor: []const u8,
    default_artifact_type: []const u8,

    pub fn deinit(self: *Config, allocator: Allocator) void {
        allocator.free(self.editor);
        allocator.free(self.default_artifact_type);
    }

    pub fn clone(self: *const Config, allocator: Allocator) !Config {
        return Config{
            .editor = try allocator.dupe(u8, self.editor),
            .default_artifact_type = try allocator.dupe(u8, self.default_artifact_type),
        };
    }
};

pub fn getDefaultConfig(allocator: Allocator) !Config {
    const config = Config{
        .editor = try allocator.dupe(u8, "hx"),
        .default_artifact_type = try allocator.dupe(u8, "feature"),
    };
    return config;
}

pub fn getConfigPath(allocator: Allocator) ![]const u8 {
    const home_dir = try std.fs.getAppDataDir(allocator, "engram");
    defer allocator.free(home_dir);

    return allocator.dupe(u8, home_dir);
}

pub fn getConfigFilePath(allocator: Allocator) ![]const u8 {
    const config_dir = try getConfigPath(allocator);
    defer allocator.free(config_dir);

    return std.fs.path.join(allocator, &[_][]const u8{ config_dir, "config.yaml" });
}

pub fn ensureConfigDir(allocator: Allocator) !void {
    const config_dir = try getConfigPath(allocator);
    defer allocator.free(config_dir);

    std.fs.cwd().makePath(config_dir) catch |err| {
        if (err == error.PathAlreadyExists) return;
        return err;
    };
}

pub fn createDefaultConfigFile(allocator: Allocator) !void {
    try ensureConfigDir(allocator);
    const config_path = try getConfigFilePath(allocator);
    defer allocator.free(config_path);

    const default_config =
        \\# Engram Configuration File
        \\# Configuration settings for the Engram application
        \\
        \\editor: hx
        \\default-artifact-type: feature
    ;

    const file = try std.fs.cwd().createFile(config_path, .{ .read = false });
    defer file.close();

    _ = try file.writeAll(default_config);
}

pub fn loadConfig(allocator: Allocator) !Config {
    const config_path = try getConfigFilePath(allocator);
    defer allocator.free(config_path);

    const file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            try createDefaultConfigFile(allocator);
            return getDefaultConfig(allocator);
        }
        return err;
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);

    var parsed = yaml_parser.Parser.parse(allocator, contents) catch {
        std.debug.print("Warning: Failed to parse config file, using defaults\n", .{});
        return getDefaultConfig(allocator);
    };
    defer {
        var it = parsed.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        parsed.deinit();
    }

    const editor = if (parsed.get("editor")) |e|
        try allocator.dupe(u8, yaml_parser.getString(e, "hx"))
    else
        try allocator.dupe(u8, "hx");

    const config = Config{
        .editor = editor,
        .default_artifact_type = if (parsed.get("default-artifact-type")) |type_val|
            try allocator.dupe(u8, yaml_parser.getString(type_val, "feature"))
        else
            try allocator.dupe(u8, "feature"),
    };

    return config;
}

pub fn loadOrCreateConfig(allocator: Allocator) !Config {
    return loadConfig(allocator) catch getDefaultConfig(allocator);
}

test "loadConfig parses hyphenated keys" {
    const allocator = std.testing.allocator;

    const test_yaml = "# Comment\neditor: hx\ndefault-artifact-type: feature";

    var parsed = yaml_parser.Parser.parse(allocator, test_yaml) catch {
        return error.ParseFailed;
    };
    defer {
        var it = parsed.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        parsed.deinit();
    }

    try std.testing.expectEqual(@as(usize, 2), parsed.count());

    const editor = parsed.get("editor") orelse return error.NotFound;
    const editor_str = yaml_parser.getString(editor, "default");
    try std.testing.expectEqualStrings("hx", editor_str);

    const artifact_type = parsed.get("default-artifact-type") orelse return error.NotFound;
    const artifact_str = yaml_parser.getString(artifact_type, "default");
    try std.testing.expectEqualStrings("feature", artifact_str);
}

test "getDefaultConfig returns default values" {
    const allocator = std.testing.allocator;

    var config = try getDefaultConfig(allocator);
    defer config.deinit(allocator);

    try std.testing.expectEqualStrings("hx", config.editor);
    try std.testing.expectEqualStrings("feature", config.default_artifact_type);
}
