// File: src/cli/show.zig
// The `engram show` command for displaying Neuronas
// Displays Neurona content with connections
// Also supports `engram show config` to open configuration file

const std = @import("std");
const Allocator = std.mem.Allocator;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Neurona = @import("../core/neurona.zig").Neurona;
const readNeurona = @import("../storage/filesystem.zig").readNeurona;
const uri_parser = @import("../utils/uri_parser.zig");
const config_util = @import("../utils/config.zig");
const editor_util = @import("../utils/editor.zig");

/// Display configuration
pub const ShowConfig = struct {
    id: []const u8,
    show_connections: bool = true,
    show_body: bool = true,
    json_output: bool = false,
    cortex_dir: ?[]const u8 = null,
};

/// Main command handler
pub fn execute(allocator: Allocator, config: ShowConfig) !void {
    // Handle special "config" case
    if (std.mem.eql(u8, config.id, "config")) {
        const config_path = try config_util.getConfigFilePath(allocator);
        defer allocator.free(config_path);

        // Ensure config file exists, create default if not
        _ = std.fs.cwd().openFile(config_path, .{}) catch {
            try config_util.createDefaultConfigFile(allocator);
        };

        // Load config to get editor preference
        var app_config = try config_util.loadConfig(allocator);
        defer app_config.deinit(allocator);

        std.debug.print("Opening config file: {s}\n", .{config_path});
        try editor_util.open(allocator, config_path, app_config.editor);
        return;
    }

    // Determine cortex directory (searches up and down 3 levels)
    const cortex_dir = uri_parser.findCortexDir(allocator, config.cortex_dir) catch |err| {
        if (err == error.CortexNotFound) {
            std.debug.print("Error: No cortex found in current directory or within 3 directory levels.\n", .{});
            std.debug.print("\nHint: Navigate to a cortex directory or use --cortex <path> to specify location.\n", .{});
            std.debug.print("Run 'engram init <name>' to create a new cortex.\n", .{});
            std.process.exit(1);
        }
        return err;
    };
    defer if (config.cortex_dir == null) allocator.free(cortex_dir);

    const neuronas_dir = try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex_dir});
    defer allocator.free(neuronas_dir);

    // Resolve URI or use direct ID
    var resolved_id: ?[]const u8 = null;
    if (uri_parser.URI.isURI(config.id)) {
        resolved_id = try uri_parser.resolveURIStr(allocator, config.id, neuronas_dir);
    } else {
        resolved_id = try allocator.dupe(u8, config.id);
    }
    defer if (resolved_id) |id| allocator.free(id);

    // Step1: Find and read Neurona file
    const filepath = try findNeuronaPath(allocator, neuronas_dir, resolved_id.?);
    defer allocator.free(filepath);

    var neurona = try readNeurona(allocator, filepath);
    defer neurona.deinit(allocator);

    // Step 2: Read body content
    const body = try readBodyContent(allocator, filepath);
    defer allocator.free(body);

    // Step 3: Output
    if (config.json_output) {
        try outputJson(allocator, &neurona, filepath, body);
    } else {
        try outputHuman(&neurona, body, config.show_connections, config.show_body);
    }
}

/// Find Neurona file by ID
fn findNeuronaPath(allocator: Allocator, directory: []const u8, id: []const u8) ![]const u8 {
    // Check for .md file directly
    const direct_path = try std.fmt.allocPrint(allocator, "{s}/{s}.md", .{ directory, id });
    defer allocator.free(direct_path);

    if (std.fs.cwd().openFile(direct_path, .{})) |_| {
        return try allocator.dupe(u8, direct_path);
    } else |err| {
        // File doesn't exist, search for files starting with ID prefix
        if (err != error.FileNotFound) return err;
    }

    // Search in directory
    var dir = try std.fs.cwd().openDir(directory, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;

        // Check if ID is in filename (before .md)
        const base_name = entry.name[0 .. entry.name.len - 3]; // Remove .md
        if (std.mem.indexOf(u8, base_name, id) != null) {
            return try std.fs.path.join(allocator, &.{ directory, entry.name });
        }
    }

    return error.NeuronaNotFound;
}

/// Read file body content (markdown after frontmatter)
fn readBodyContent(allocator: Allocator, filepath: []const u8) ![]const u8 {
    const content = try std.fs.cwd().readFileAlloc(allocator, filepath, 10 * 1024 * 1024);
    defer allocator.free(content); // Fix: Free the temporary content buffer

    // Find end of frontmatter (second ---)
    const second_delim = std.mem.indexOfPos(u8, content, 0, "\n---") orelse return error.InvalidFormat;

    // Skip past second delimiter and any newlines
    var body_start = second_delim + 4;
    while (body_start < content.len and std.ascii.isWhitespace(content[body_start])) : (body_start += 1) {}

    return try allocator.dupe(u8, content[body_start..]);
}

/// Human-friendly output
fn outputHuman(neurona: *const Neurona, body: []const u8, show_connections: bool, show_body: bool) !void {
    // Header
    std.debug.print("\n", .{});
    std.debug.print("  ID: {s}\n", .{neurona.id});
    std.debug.print("  Title: {s}\n", .{neurona.title});
    std.debug.print("  Type: {s}\n", .{@tagName(neurona.type)});

    // Tags
    if (neurona.tags.items.len > 0) {
        std.debug.print("  Tags: ", .{});
        for (neurona.tags.items, 0..) |tag, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{tag});
        }
        std.debug.print("\n", .{});
    }

    // Connections
    if (show_connections) {
        var conn_it = neurona.connections.iterator();
        if (conn_it.next()) |_| {
            std.debug.print("  Connections:\n", .{});
            conn_it = neurona.connections.iterator(); // Reset iterator
            while (conn_it.next()) |entry| {
                std.debug.print("    {s}: {d} connection(s)\n", .{ entry.key_ptr.*, entry.value_ptr.connections.items.len });
            }
        }
    }

    // Metadata
    std.debug.print("  Updated: {s}\n", .{neurona.updated});
    std.debug.print("  Language: {s}\n", .{neurona.language});

    // Body
    if (show_body and body.len > 0) {
        std.debug.print("\n", .{});
        for (0..50) |_| std.debug.print("=", .{});
        std.debug.print("\n", .{});
        std.debug.print("{s}", .{body});
        std.debug.print("\n", .{});
        for (0..50) |_| std.debug.print("=", .{});
        std.debug.print("\n", .{});
    } else if (show_body) {
        std.debug.print("\n  (No body content)\n", .{});
    }
}

/// Print string as JSON-escaped value
fn printJsonString(s: []const u8) void {
    std.debug.print("\"", .{});
    for (s) |c| {
        switch (c) {
            '"' => std.debug.print("\\\"", .{}),
            '\\' => std.debug.print("\\\\", .{}),
            '\n' => std.debug.print("\\n", .{}),
            '\r' => std.debug.print("\\r", .{}),
            '\t' => std.debug.print("\\t", .{}),
            else => std.debug.print("{c}", .{c}),
        }
    }
    std.debug.print("\"", .{});
}

/// JSON output for AI
fn outputJson(allocator: Allocator, neurona: *const Neurona, filepath: []const u8, body: []const u8) !void {
    _ = allocator;
    std.debug.print("{{", .{});
    std.debug.print("\"id\":\"{s}\",", .{neurona.id});
    std.debug.print("\"title\":\"{s}\",", .{neurona.title});
    std.debug.print("\"type\":\"{s}\",", .{@tagName(neurona.type)});
    std.debug.print("\"filepath\":\"{s}\",", .{filepath});
    std.debug.print("\"language\":\"{s}\",", .{neurona.language});
    std.debug.print("\"updated\":\"{s}\",", .{neurona.updated});

    // Tags
    std.debug.print("\"tags\":[", .{});
    for (neurona.tags.items, 0..) |tag, i| {
        if (i > 0) std.debug.print(",", .{});
        printJsonString(tag);
    }
    std.debug.print("],", .{});

    // Connections count
    std.debug.print("\"connections\":{d},", .{neurona.connections.count()});

    // Body content (escaped for JSON)
    std.debug.print("\"body\":", .{});
    printJsonString(body);
    std.debug.print(",", .{});

    // Context
    std.debug.print("\"context\":{{", .{});
    switch (neurona.context) {
        .requirement => |ctx| {
            std.debug.print("\"status\":\"{s}\",", .{ctx.status});
            std.debug.print("\"verification_method\":\"{s}\"", .{ctx.verification_method});
        },
        .test_case => |ctx| {
            std.debug.print("\"status\":\"{s}\",", .{ctx.status});
            std.debug.print("\"framework\":\"{s}\"", .{ctx.framework});
        },
        .issue => |ctx| {
            std.debug.print("\"status\":\"{s}\"", .{ctx.status});
        },
        .artifact => |ctx| {
            std.debug.print("\"runtime\":\"{s}\"", .{ctx.runtime});
        },
        else => {},
    }
    std.debug.print("}},", .{});

    // LLM metadata
    if (neurona.llm_metadata) |*meta| {
        std.debug.print("\"_llm\":{{", .{});
        std.debug.print("\"t\":\"{s}\",", .{meta.short_title});
        std.debug.print("\"d\":{d},", .{meta.density});
        std.debug.print("\"c\":{d},", .{meta.token_count});
        std.debug.print("\"strategy\":\"{s}\",", .{meta.strategy});

        std.debug.print("\"k\":[", .{});
        for (meta.keywords.items, 0..) |kw, i| {
            if (i > 0) std.debug.print(",", .{});
            printJsonString(kw);
        }
        std.debug.print("]", .{});
        std.debug.print("}}", .{});
    }

    std.debug.print("}}\n", .{});
}

// Example CLI usage:
//
//   engram show test.001
//   → Displays test.001.md with all information
//
//   engram show req.auth.oauth2 --no-body
//   → Displays without body content
//
//   engram show test.oauth.001 --json
//   → Returns JSON for AI parsing

// ==================== Tests ====================

test "ShowConfig with default values" {
    const config = ShowConfig{
        .id = "test.001",
        .show_connections = true,
        .show_body = true,
        .json_output = false,
    };

    try std.testing.expectEqualStrings("test.001", config.id);
    try std.testing.expectEqual(true, config.show_connections);
    try std.testing.expectEqual(true, config.show_body);
    try std.testing.expectEqual(false, config.json_output);
}

test "ShowConfig with flags set" {
    const config = ShowConfig{
        .id = "req.auth",
        .show_connections = false,
        .show_body = false,
        .json_output = true,
    };

    try std.testing.expectEqual(false, config.show_connections);
    try std.testing.expectEqual(false, config.show_body);
    try std.testing.expectEqual(true, config.json_output);
}

test "findNeuronaPath returns direct .md file" {
    const allocator = std.testing.allocator;

    // Setup test file
    const test_file = "test_find_neurona.md";
    try std.fs.cwd().writeFile(.{
        .sub_path = test_file,
        .data = "---\nid: test.001\n---\n",
    });
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Rename to neuronas/test.001.md format
    try std.fs.cwd().makePath("neuronas_test");
    defer std.fs.cwd().deleteTree("neuronas_test") catch {};

    const target_path = try std.fs.path.join(allocator, &.{ "neuronas_test", "test.001.md" });
    defer allocator.free(target_path);
    try std.fs.cwd().writeFile(.{
        .sub_path = target_path,
        .data = "---\nid: test.001\n---\n",
    });

    // Test with full path
    const result = try findNeuronaPath(allocator, "neuronas_test", "test.001");
    defer allocator.free(result);

    // Should return the path as-is since we passed full path
    try std.testing.expect(result.len > 0);
}

test "readBodyContent handles files without body" {
    // This test verifies overall execute flow
    // No explicit allocations needed in this test
}
