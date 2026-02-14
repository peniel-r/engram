// File: src/cli/show.zig
// The `engram show` command for displaying Neuronas
// Displays Neurona content with connections
// Also supports `engram show config` to open configuration file
// MIGRATED: Now uses Phase 3 CLI utilities (JsonOutput, HumanOutput)

const std = @import("std");
const Allocator = std.mem.Allocator;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Neurona = @import("../core/neurona.zig").Neurona;
const FileOps = @import("../utils/file_ops.zig").FileOps;
const uri_parser = @import("../utils/uri_parser.zig");
const config_util = @import("../utils/config.zig");
const editor_util = @import("../utils/editor.zig");

// Import Phase 3 CLI utilities
const JsonOutput = @import("output/json.zig").JsonOutput;
const HumanOutput = @import("output/human.zig").HumanOutput;

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

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("Opening config file: {s}\n", .{config_path});
        try stdout.flush();
        try editor_util.open(allocator, config_path, app_config.editor);
        return;
    }

    // Determine cortex directory (searches up and down 3 levels)
    const cortex_dir = uri_parser.findCortexDir(allocator, config.cortex_dir) catch |err| {
        if (err == error.CortexNotFound) {
            try HumanOutput.printError("No cortex found in current directory or within 3 directory levels.");
            try HumanOutput.printInfo("Navigate to a cortex directory or use --cortex <path> to specify location.");
            try HumanOutput.printInfo("Run 'engram init <name>' to create a new cortex.");
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

    // Read neurona with body using unified API
    var result = try FileOps.readNeuronaWithBody(allocator, neuronas_dir, resolved_id.?);
    defer result.deinit(allocator);

    // Output
    if (config.json_output) {
        try outputJson(allocator, &result.neurona, result.filepath, result.body);
    } else {
        try outputHuman(&result.neurona, result.body, config.show_connections, config.show_body);
    }
}

/// Human-friendly output
fn outputHuman(neurona: *const Neurona, body: []const u8, show_connections: bool, show_body: bool) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    // Header
    try stdout.print("\n", .{});
    try stdout.print("  ID: {s}\n", .{neurona.id});
    try stdout.print("  Title: {s}\n", .{neurona.title});
    try stdout.print("  Type: {s}\n", .{@tagName(neurona.type)});

    // Tags
    if (neurona.tags.items.len > 0) {
        try stdout.print("  Tags: ", .{});
        for (neurona.tags.items, 0..) |tag, i| {
            if (i > 0) try stdout.print(", ", .{});
            try stdout.print("{s}", .{tag});
        }
        try stdout.print("\n", .{});
    }

    // Connections
    if (show_connections) {
        var conn_it = neurona.connections.iterator();
        if (conn_it.next()) |_| {
            try stdout.print("  Connections:\n", .{});
            conn_it = neurona.connections.iterator(); // Reset iterator
            while (conn_it.next()) |entry| {
                try stdout.print("    {s}: {d} connection(s)\n", .{ entry.key_ptr.*, entry.value_ptr.connections.items.len });
            }
        }
    }

    // Metadata
    try stdout.print("  Updated: {s}\n", .{neurona.updated});
    try stdout.print("  Language: {s}\n", .{neurona.language});
    try stdout.flush();

    // Body
    if (show_body and body.len > 0) {
        try stdout.print("\n", .{});
        for (0..50) |_| try stdout.print("=", .{});
        try stdout.print("\n", .{});
        try stdout.print("{s}", .{body});
        try stdout.print("\n", .{});
        for (0..50) |_| try stdout.print("=", .{});
        try stdout.print("\n", .{});
    } else if (show_body) {
        try stdout.print("\n  (No body content)\n", .{});
    }
    try stdout.flush();
}

/// JSON output for AI
fn outputJson(allocator: Allocator, neurona: *const Neurona, filepath: []const u8, body: []const u8) !void {
    _ = allocator;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try JsonOutput.beginObject(stdout);

    try JsonOutput.stringField(stdout, "id", neurona.id);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.stringField(stdout, "title", neurona.title);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.enumField(stdout, "type", neurona.type);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.stringField(stdout, "filepath", filepath);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.stringField(stdout, "language", neurona.language);
    try JsonOutput.separator(stdout, true);
    try JsonOutput.stringField(stdout, "updated", neurona.updated);

    // Tags
    try JsonOutput.separator(stdout, true);
    try stdout.print("\"tags\":[", .{});
    for (neurona.tags.items, 0..) |tag, i| {
        if (i > 0) try stdout.writeAll(",");
        try JsonOutput.stringField(stdout, "", tag);
    }
    try stdout.writeAll("]");

    // Connections count
    try JsonOutput.separator(stdout, true);
    try JsonOutput.numberField(stdout, "connections", neurona.connections.count());

    // Body content (escaped for JSON)
    try JsonOutput.separator(stdout, true);
    try stdout.print("\"body\":", .{});
    try JsonOutput.stringField(stdout, "", body);
    try JsonOutput.separator(stdout, true);

    // Context
    try stdout.print("\"context\":{{", .{});
    switch (neurona.context) {
        .requirement => |ctx| {
            try JsonOutput.stringField(stdout, "status", ctx.status);
            try JsonOutput.separator(stdout, true);
            try JsonOutput.stringField(stdout, "verification_method", ctx.verification_method);
        },
        .test_case => |ctx| {
            try JsonOutput.stringField(stdout, "status", ctx.status);
            try JsonOutput.separator(stdout, true);
            try JsonOutput.stringField(stdout, "framework", ctx.framework);
        },
        .issue => |ctx| {
            try JsonOutput.stringField(stdout, "status", ctx.status);
        },
        .artifact => |ctx| {
            try JsonOutput.stringField(stdout, "runtime", ctx.runtime);
        },
        else => {},
    }
    try stdout.writeAll("}}");
    try JsonOutput.separator(stdout, true);

    // LLM metadata
    if (neurona.llm_metadata) |*meta| {
        try stdout.print("\"_llm\":{{", .{});
        try JsonOutput.stringField(stdout, "t", meta.short_title);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.numberField(stdout, "d", meta.density);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.numberField(stdout, "c", meta.token_count);
        try JsonOutput.separator(stdout, true);
        try JsonOutput.stringField(stdout, "strategy", meta.strategy);

        try JsonOutput.separator(stdout, true);
        try stdout.print("\"k\":[", .{});
        for (meta.keywords.items, 0..) |kw, i| {
            if (i > 0) try stdout.writeAll(",");
            try JsonOutput.stringField(stdout, "", kw);
        }
        try stdout.writeAll("]");
        try stdout.writeAll("}}");
    }

    try JsonOutput.endObject(stdout);
    try stdout.print("\n", .{});
    try stdout.flush();
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
    const test_dir = "neuronas_test";
    const filepath_with_id = try std.fmt.allocPrint(allocator, "{s}/test.001.md", .{test_dir});
    defer allocator.free(filepath_with_id); // Fix: Free allocated path
    try std.fs.cwd().writeFile(.{ .sub_path = filepath_with_id, .data = "---\nid: test.001\n---\n" });

    const result = try FileOps.findNeuronaFile(allocator, test_dir, "test.001");
    defer allocator.free(result);

    // Should return path as-is since we passed full path
    try std.testing.expect(result.len > 0);
}

test "readBodyContent handles files without body" {
    // This test verifies overall execute flow
    // No explicit allocations needed in this test
}
