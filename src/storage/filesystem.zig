// Filesystem operations for Neurona files
// Handles reading, writing, and scanning Neurona Markdown files
const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Connection = @import("../core/neurona.zig").Connection;
const ConnectionType = @import("../core/neurona.zig").ConnectionType;
const frontmatter = @import("../utils/frontmatter.zig").Frontmatter;
const yaml = @import("../utils/yaml.zig");
const getString = yaml.getString;
const getInt = yaml.getInt;
const getBool = yaml.getBool;
const getArray = yaml.getArray;

pub const StorageError = error{
    FileNotFound,
    InvalidNeuronaFormat,
    MissingRequiredField,
    InvalidYaml,
    IoError,
    OutOfMemory,
};

/// Check if a file is a valid Neurona file
pub fn isNeuronaFile(filename: []const u8) bool {
    const ext = std.fs.path.extension(filename);
    return std.mem.eql(u8, ext, ".md");
}

/// Read a Neurona file and return a Neurona struct
pub fn readNeurona(allocator: Allocator, filepath: []const u8) !Neurona {
    // Read file content
    const content = std.fs.cwd().readFileAlloc(allocator, filepath, 10 * 1024 * 1024) catch |err| {
        switch (err) {
            error.FileNotFound => return StorageError.FileNotFound,
            else => return StorageError.IoError,
        }
    };
    defer allocator.free(content);

    // Extract frontmatter
    const fm = frontmatter.parse(allocator, content) catch |err| {
        switch (err) {
            error.NoFrontmatterFound => return StorageError.InvalidNeuronaFormat,
            else => return err,
        }
    };
    defer fm.deinit(allocator);

    // Parse YAML
    var yaml_data = try yaml.Parser.parse(allocator, fm.content);
    defer {
        var it = yaml_data.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        yaml_data.deinit();
    }

    // Convert YAML to Neurona
    return try yamlToNeurona(allocator, yaml_data, fm.body);
}

/// Helper: safely replace string field (free old if allocated)
fn replaceString(allocator: Allocator, old: []const u8, new_value: []const u8) ![]const u8 {
    // Free old if it was a valid allocated pointer
    if (@intFromPtr(old.ptr) != 0 and old.len > 0) {
        allocator.free(old);
    }
    return allocator.dupe(u8, new_value);
}

/// Convert parsed YAML frontmatter to Neurona struct
fn yamlToNeurona(allocator: Allocator, yaml_data: std.StringHashMap(yaml.Value), body: []const u8) !Neurona {
    _ = body; // TODO: Use body content for full Neurona

    var neurona = try Neurona.init(allocator);
    errdefer neurona.deinit(allocator);

    // Required fields: id, title (free old defaults from init first)
    const id_val = yaml_data.get("id") orelse return StorageError.MissingRequiredField;
    neurona.id = try replaceString(allocator, neurona.id, getString(id_val, ""));

    const title_val = yaml_data.get("title") orelse return StorageError.MissingRequiredField;
    neurona.title = try replaceString(allocator, neurona.title, getString(title_val, ""));

    // Tier 2 field: type
    if (yaml_data.get("type")) |type_val| {
        const type_str = getString(type_val, "concept");
        neurona.type = parseNeuronaType(type_str) catch .concept;
    }

    // Tier 2 field: updated
    if (yaml_data.get("updated")) |updated_val| {
        neurona.updated = try replaceString(allocator, neurona.updated, getString(updated_val, ""));
    }

    // Tier 2 field: language
    if (yaml_data.get("language")) |lang_val| {
        neurona.language = try replaceString(allocator, neurona.language, getString(lang_val, "en"));
    }

    // Tier 1 field: tags
    if (yaml_data.get("tags")) |tags_val| {
        const tags = try getArray(tags_val, allocator, &[_][]const u8{});
        for (tags) |tag| {
            try neurona.tags.append(allocator, tag);
        }
        allocator.free(tags);
    }

    // Tier 2 field: connections
    if (yaml_data.get("connections")) |conn_val| {
        switch (conn_val) {
            // Legacy format: ["type:target:weight"]
            .array => |arr| {
                for (arr.items) |item| {
                    const conn_str = getString(item, "");
                    var parts = std.mem.splitScalar(u8, conn_str, ':');
                    const type_str = parts.next() orelse continue;
                    const target_id = parts.next() orelse continue;
                    const weight_str = parts.next() orelse "50";

                    if (ConnectionType.fromString(type_str)) |conn_type| {
                        const weight = std.fmt.parseInt(u8, weight_str, 10) catch 50;
                        const conn = Connection{
                            .target_id = try allocator.dupe(u8, target_id),
                            .connection_type = conn_type,
                            .weight = weight,
                        };
                        try neurona.addConnection(allocator, conn);
                    }
                }
            },
            // Structured format: { type: [{id: ..., weight: ...}] }
            .object => |obj_opt| {
                if (obj_opt) |obj| {
                    var it = obj.iterator();
                    while (it.next()) |entry| {
                        const type_str = entry.key_ptr.*;
                        const conn_type = ConnectionType.fromString(type_str) orelse continue;

                        const targets_val = entry.value_ptr.*;
                        switch (targets_val) {
                            .array => |targets| {
                                for (targets.items) |target_item| {
                                    switch (target_item) {
                                        .object => |t_obj_opt| {
                                            if (t_obj_opt) |t_obj| {
                                                if (t_obj.get("id")) |target_id_val| {
                                                    const target_id = getString(target_id_val, "");
                                                    if (target_id.len == 0) continue;

                                                    var weight: u8 = 50;
                                                    if (t_obj.get("weight")) |w_val| {
                                                        weight = @intCast(getInt(w_val, 50));
                                                    }

                                                    const conn = Connection{
                                                        .target_id = try allocator.dupe(u8, target_id),
                                                        .connection_type = conn_type,
                                                        .weight = weight,
                                                    };
                                                    try neurona.addConnection(allocator, conn);
                                                }
                                            }
                                        },
                                        else => {},
                                    }
                                }
                            },
                            else => {},
                        }
                    }
                }
            },
            else => {},
        }
    }

    // Tier 3 field: hash (optional)
    if (yaml_data.get("hash")) |hash_val| {
        const hash_str = getString(hash_val, "");
        if (hash_str.len > 0) {
            neurona.hash = try allocator.dupe(u8, hash_str);
        }
    }

    return neurona;
}

/// Parse Neurona type from string
fn parseNeuronaType(type_str: []const u8) !NeuronaType {
    if (std.mem.eql(u8, type_str, "concept")) return .concept;
    if (std.mem.eql(u8, type_str, "reference")) return .reference;
    if (std.mem.eql(u8, type_str, "artifact")) return .artifact;
    if (std.mem.eql(u8, type_str, "state_machine")) return .state_machine;
    if (std.mem.eql(u8, type_str, "lesson")) return .lesson;
    if (std.mem.eql(u8, type_str, "requirement")) return .requirement;
    if (std.mem.eql(u8, type_str, "test_case")) return .test_case;
    if (std.mem.eql(u8, type_str, "issue")) return .issue;
    if (std.mem.eql(u8, type_str, "feature")) return .feature;
    return error.UnknownType;
}

// ==================== Writing Functions ====================

/// Write a Neurona struct to a Markdown file
pub fn writeNeurona(allocator: Allocator, neurona: Neurona, filepath: []const u8) !void {
    // Generate YAML frontmatter
    const yaml_content = try neuronaToYaml(allocator, neurona);
    defer allocator.free(yaml_content);

    // Generate complete Markdown content
    const content = try generateMarkdown(allocator, yaml_content, "");
    defer allocator.free(content);

    // Write to file
    const file = try std.fs.cwd().createFile(filepath, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Convert Neurona struct to YAML frontmatter string
fn neuronaToYaml(allocator: Allocator, neurona: Neurona) ![]u8 {
    var yaml_buf = std.ArrayListUnmanaged(u8){};
    errdefer yaml_buf.deinit(allocator);
    const writer = yaml_buf.writer(allocator);

    // Tier 1 fields
    try writer.print("id: {s}\n", .{neurona.id});
    try writer.print("title: {s}\n", .{neurona.title});

    // Tags (Tier 1)
    if (neurona.tags.items.len > 0) {
        try writer.writeAll("tags: [");
        for (neurona.tags.items, 0..) |tag, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("{s}", .{tag});
        }
        try writer.writeAll("]\n");
    }

    // Tier 2 fields
    if (neurona.type != .concept) {
        try writer.print("type: {s}\n", .{@tagName(neurona.type)});
    }

    // Connections (Tier 2)
    if (neurona.connections.count() > 0) {
        try writer.writeAll("connections: [");
        var first = true;
        var it = neurona.connections.iterator();
        while (it.next()) |entry| {
            const type_name = entry.key_ptr.*;
            for (entry.value_ptr.connections.items) |conn| {
                if (!first) try writer.writeAll(", ");
                // Format: "type:target_id:weight"
                try writer.print("\"{s}:{s}:{d}\"", .{ type_name, conn.target_id, conn.weight });
                first = false;
            }
        }
        try writer.writeAll("]\n");
    }

    if (neurona.updated.len > 0) {
        try writer.print("updated: \"{s}\"\n", .{neurona.updated});
    }

    if (!std.mem.eql(u8, neurona.language, "en")) {
        try writer.print("language: {s}\n", .{neurona.language});
    }

    // Tier 3 fields (optional)
    if (neurona.hash) |hash| {
        try writer.print("hash: {s}\n", .{hash});
    }

    return try yaml_buf.toOwnedSlice(allocator);
}

/// Generate complete Markdown file content from Neurona
fn generateMarkdown(allocator: Allocator, yaml_content: []const u8, body: []const u8) ![]u8 {
    var content = std.ArrayListUnmanaged(u8){};
    errdefer content.deinit(allocator);
    const writer = content.writer(allocator);

    // Write frontmatter delimiters
    try writer.writeAll("---\n");
    try writer.writeAll(yaml_content);
    try writer.writeAll("---\n\n");

    // Write body
    if (body.len > 0) {
        try writer.writeAll(body);
    }

    return try content.toOwnedSlice(allocator);
}

// ==================== Directory Scanning Functions ====================

/// List all Neurona file paths in a directory
pub fn listNeuronaFiles(allocator: Allocator, directory: []const u8) ![][]const u8 {
    var dir = try std.fs.cwd().openDir(directory, .{ .iterate = true });
    defer dir.close();

    var files = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (files.items) |file| allocator.free(file);
        files.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (isNeuronaFile(entry.name)) {
            const path = try std.fs.path.join(allocator, &.{ directory, entry.name });
            try files.append(allocator, path);
        }
    }

    return try files.toOwnedSlice(allocator);
}

/// Scan directory and load all Neurona files
pub fn scanNeuronas(allocator: Allocator, directory: []const u8) ![]Neurona {
    const filepaths = try listNeuronaFiles(allocator, directory);
    defer {
        for (filepaths) |path| allocator.free(path);
        allocator.free(filepaths);
    }

    var neuronas = std.ArrayListUnmanaged(Neurona){};
    errdefer {
        for (neuronas.items) |*n| n.deinit(allocator);
        neuronas.deinit(allocator);
    }

    for (filepaths) |filepath| {
        const neurona = readNeurona(allocator, filepath) catch |err| {
            // Skip invalid files but continue scanning
            std.debug.print("Warning: Skipping {s}: {}\n", .{ filepath, err });
            continue;
        };
        try neuronas.append(allocator, neurona);
    }

    return try neuronas.toOwnedSlice(allocator);
}

/// Find Neurona file path by ID
pub fn findNeuronaPath(allocator: Allocator, neuronas_dir: []const u8, id: []const u8) ![]const u8 {
    // Check for .md file directly
    const id_md = try std.fmt.allocPrint(allocator, "{s}.md", .{id});
    defer allocator.free(id_md);
    const direct_path = try std.fs.path.join(allocator, &.{ neuronas_dir, id_md });

    if (std.fs.cwd().access(direct_path, .{})) |_| {
        return direct_path;
    } else |err| {
        // File doesn't exist, search for files starting with ID prefix
        allocator.free(direct_path);
        if (err != error.FileNotFound) return err;
    }

    // Search in neuronas directory
    var dir = std.fs.cwd().openDir(neuronas_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return error.NeuronaNotFound;
        return err;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".md")) continue;

        // Check if ID is in filename (before .md)
        const base_name = entry.name[0 .. entry.name.len - 3]; // Remove .md
        // Exact match or prefix match logic can be refined here.
        // For now, let's assume filename IS the ID or starts with it?
        // show.zig logic was: if (std.mem.indexOf(u8, base_name, id) != null)
        // That's a substring match. Might be dangerous (id "test" matches "test.001").
        // But let's stick to what show.zig had to be consistent.
        if (std.mem.eql(u8, base_name, id)) {
            return try std.fs.path.join(allocator, &.{ neuronas_dir, entry.name });
        }
    }

    return error.NeuronaNotFound;
}

// ==================== Tests ====================

test "isNeuronaFile identifies .md files" {
    try std.testing.expect(isNeuronaFile("test.md"));
    try std.testing.expect(isNeuronaFile("neurona.md"));
    try std.testing.expect(isNeuronaFile("2026-01-22.md"));
}

test "isNeuronaFile rejects non-.md files" {
    try std.testing.expect(!isNeuronaFile("test.txt"));
    try std.testing.expect(!isNeuronaFile("test.json"));
    try std.testing.expect(!isNeuronaFile("neurona"));
}

test "isNeuronaFile handles empty strings" {
    try std.testing.expect(!isNeuronaFile(""));
    try std.testing.expect(!isNeuronaFile("   "));
}

test "readNeurona parses valid Tier 1 file" {
    const allocator = std.testing.allocator;

    // Create test fixture
    const test_path = "test_neurona_tier1.md";
    const test_content =
        \\---
        \\id: test.001
        \\title: Test Neurona
        \\tags: [test, example]
        \\---
        \\
        \\# Test Content
        \\This is test content.
    ;

    try std.fs.cwd().writeFile(.{ .sub_path = test_path, .data = test_content });
    defer std.fs.cwd().deleteFile(test_path) catch {};

    var neurona = try readNeurona(allocator, test_path);
    defer neurona.deinit(allocator);

    try std.testing.expectEqualStrings("test.001", neurona.id);
    try std.testing.expectEqualStrings("Test Neurona", neurona.title);
    try std.testing.expectEqual(@as(usize, 2), neurona.tags.items.len);
    try std.testing.expectEqualStrings("test", neurona.tags.items[0]);
    try std.testing.expectEqualStrings("example", neurona.tags.items[1]);
}

test "readNeurona returns error for missing frontmatter" {
    const allocator = std.testing.allocator;

    const test_path = "test_no_frontmatter.md";
    const test_content = "# Just content";

    try std.fs.cwd().writeFile(.{ .sub_path = test_path, .data = test_content });
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const result = readNeurona(allocator, test_path);
    try std.testing.expectError(StorageError.InvalidNeuronaFormat, result);
}

test "readNeurona returns error for missing required fields" {
    const allocator = std.testing.allocator;

    const test_path = "test_missing_fields.md";
    const test_content =
        \\---
        \\tags: [test]
        \\---
        \\
        \\# Content
    ;

    try std.fs.cwd().writeFile(.{ .sub_path = test_path, .data = test_content });
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const result = readNeurona(allocator, test_path);
    try std.testing.expectError(StorageError.MissingRequiredField, result);
}

test "readNeurona returns error for file not found" {
    const allocator = std.testing.allocator;

    const result = readNeurona(allocator, "nonexistent.md");
    try std.testing.expectError(StorageError.FileNotFound, result);
}

test "writeNeurona writes valid Tier 1 file" {
    const allocator = std.testing.allocator;

    // Create test Neurona
    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);

    allocator.free(neurona.id);
    neurona.id = try allocator.dupe(u8, "test.001");
    allocator.free(neurona.title);
    neurona.title = try allocator.dupe(u8, "Test Neurona");

    const tag1 = try allocator.dupe(u8, "test");
    try neurona.tags.append(allocator, tag1);

    // Write to file
    const test_path = "test_write_tier1.md";
    try writeNeurona(allocator, neurona, test_path);
    defer std.fs.cwd().deleteFile(test_path) catch {};

    // Verify file exists and has correct content
    const content = try std.fs.cwd().readFileAlloc(allocator, test_path, 1024);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "id: test.001") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "title: Test Neurona") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "---") != null);
}

test "writeNeurona write and read roundtrip Tier 2" {
    const allocator = std.testing.allocator;

    // Create test Neurona
    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);

    allocator.free(neurona.id);
    neurona.id = try allocator.dupe(u8, "test.002");
    allocator.free(neurona.title);
    neurona.title = try allocator.dupe(u8, "Test Requirement");
    neurona.type = .requirement;
    allocator.free(neurona.updated);
    neurona.updated = try allocator.dupe(u8, "2026-01-22");

    // Write to file
    const test_path = "test_write_tier2.md";
    try writeNeurona(allocator, neurona, test_path);
    defer std.fs.cwd().deleteFile(test_path) catch {};

    // Read back
    var loaded = try readNeurona(allocator, test_path);
    defer loaded.deinit(allocator);

    try std.testing.expectEqualStrings(neurona.id, loaded.id);
    try std.testing.expectEqualStrings(neurona.title, loaded.title);
    try std.testing.expectEqual(.requirement, loaded.type);
}

test "listNeuronaFiles lists .md files" {
    const allocator = std.testing.allocator;

    // Create test directory
    const test_dir = "test_neuronas_dir";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test files
    const p1 = try std.fs.path.join(allocator, &.{ test_dir, "test1.md" });
    defer allocator.free(p1);
    const p2 = try std.fs.path.join(allocator, &.{ test_dir, "test2.md" });
    defer allocator.free(p2);
    const p3 = try std.fs.path.join(allocator, &.{ test_dir, "not_md.txt" });
    defer allocator.free(p3);

    try std.fs.cwd().writeFile(.{ .sub_path = p1, .data = "content" });
    try std.fs.cwd().writeFile(.{ .sub_path = p2, .data = "content" });
    try std.fs.cwd().writeFile(.{ .sub_path = p3, .data = "content" });

    // List files
    const files = try listNeuronaFiles(allocator, test_dir);
    defer {
        for (files) |file| allocator.free(file);
        allocator.free(files);
    }

    try std.testing.expectEqual(@as(usize, 2), files.len);
}

test "scanNeuronas loads all valid Neuronas" {
    const allocator = std.testing.allocator;

    // Create test directory
    const test_dir = "test_scan_dir";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test Neurona files
    const path1 = try std.fs.path.join(allocator, &.{ test_dir, "test1.md" });
    defer allocator.free(path1);
    const path2 = try std.fs.path.join(allocator, &.{ test_dir, "test2.md" });
    defer allocator.free(path2);

    try std.fs.cwd().writeFile(.{ .sub_path = path1, .data = 
        \\---
        \\id: test.001
        \\title: Test One
        \\tags: [test]
        \\---
        \\
        \\# Content
    });
    try std.fs.cwd().writeFile(.{ .sub_path = path2, .data = 
        \\---
        \\id: test.002
        \\title: Test Two
        \\tags: [test]
        \\---
        \\
        \\# Content
    });
    try std.fs.cwd().writeFile(.{ .sub_path = path2, .data = 
        \\---
        \\id: test.002
        \\title: Test Two
        \\tags: [test]
        \\---
        \\
        \\# Content
    });

    // Scan directory
    const neuronas = try scanNeuronas(allocator, test_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    try std.testing.expectEqual(@as(usize, 2), neuronas.len);
}

test "scanNeuronas skips invalid files" {
    const allocator = std.testing.allocator;

    // Create test directory
    const test_dir = "test_invalid_dir";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create valid and invalid files
    const valid_path = try std.fs.path.join(allocator, &.{ test_dir, "valid.md" });
    defer allocator.free(valid_path);
    const invalid_path = try std.fs.path.join(allocator, &.{ test_dir, "invalid.md" });
    defer allocator.free(invalid_path);

    try std.fs.cwd().writeFile(.{ .sub_path = valid_path, .data = 
        \\---
        \\id: test.001
        \\title: Valid
        \\---
        \\# Content
    });
    try std.fs.cwd().writeFile(.{ .sub_path = invalid_path, .data = "No frontmatter" });

    // Scan directory
    const neuronas = try scanNeuronas(allocator, test_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }

    try std.testing.expectEqual(@as(usize, 1), neuronas.len);
    try std.testing.expectEqualStrings("test.001", neuronas[0].id);
}
