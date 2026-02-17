//! Filesystem storage implementation for Neurona files
//! Handles reading, writing, and scanning Neurona Markdown files
//!
//! This is a library-only implementation without CLI dependencies.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Neurona = @import("../core/types.zig").Neurona;
const NeuronaType = @import("../core/types.zig").NeuronaType;
const Connection = @import("../core/connections.zig").Connection;
const ConnectionType = @import("../core/connections.zig").ConnectionType;
const Context = @import("../core/context.zig").Context;
const LLMMetadata = @import("../core/types.zig").LLMMetadata;

/// Storage errors
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

/// Simple YAML value type for parsing frontmatter
const YamlValue = union(enum) {
    string: []const u8,
    number: i64,
    boolean: bool,
    null,

    pub fn deinit(self: YamlValue, allocator: Allocator) void {
        if (self == .string) {
            allocator.free(self.string);
        }
    }
};

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

    // Find frontmatter delimiter (---)
    const frontmatter_start = std.mem.indexOf(u8, content, "---");
    if (frontmatter_start == null) {
        return StorageError.InvalidNeuronaFormat;
    }

    const frontmatter_end = std.mem.indexOf(u8, content[frontmatter_start.? + 3 ..], "---");
    if (frontmatter_end == null) {
        return StorageError.InvalidNeuronaFormat;
    }

    const yaml_start = frontmatter_start.? + 3;
    const yaml_end = frontmatter_start.? + 3 + frontmatter_end.?;
    const yaml_content = content[yaml_start..yaml_end];
    const body = content[yaml_end + 3 ..];

    // Parse YAML key-value pairs
    var yaml_fields = std.StringHashMap(YamlValue).init(allocator);
    defer {
        var it = yaml_fields.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        yaml_fields.deinit();
    }

    try parseSimpleYaml(allocator, yaml_content, &yaml_fields);

    // Create neurona from parsed data
    return try yamlToNeurona(allocator, yaml_fields, body);
}

/// Parse simple YAML key-value pairs
fn parseSimpleYaml(allocator: Allocator, yaml: []const u8, fields: *std.StringHashMap(YamlValue)) !void {
    var lines = std.mem.splitScalar(u8, yaml, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Split on first colon
        const colon_idx = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;

        const key_slice = std.mem.trim(u8, trimmed[0..colon_idx], &std.ascii.whitespace);
        const value_str = std.mem.trim(u8, trimmed[colon_idx + 1 ..], &std.ascii.whitespace);

        // Parse value
        const value = try parseYamlValue(allocator, value_str);
        errdefer value.deinit(allocator);

        // Duplicate the key since it's a slice of the yaml string which will be freed
        const key = try allocator.dupe(u8, key_slice);
        errdefer allocator.free(key);

        try fields.put(key, value);
    }
}

/// Parse a single YAML value
fn parseYamlValue(allocator: Allocator, value_str: []const u8) !YamlValue {
    const trimmed = std.mem.trim(u8, value_str, &std.ascii.whitespace);

    // Check for boolean
    if (std.mem.eql(u8, trimmed, "true")) {
        return YamlValue{ .boolean = true };
    }
    if (std.mem.eql(u8, trimmed, "false")) {
        return YamlValue{ .boolean = false };
    }

    // Check for null
    if (std.mem.eql(u8, trimmed, "null") or trimmed.len == 0) {
        return YamlValue{ .null = {} };
    }

    // Check for quoted string
    if (trimmed.len >= 2 and (trimmed[0] == '"' or trimmed[0] == '\'')) {
        const quote = trimmed[0];
        if (trimmed[trimmed.len - 1] == quote) {
            const unquoted = try allocator.dupe(u8, trimmed[1 .. trimmed.len - 1]);
            return YamlValue{ .string = unquoted };
        }
    }

    // Check for list [item1, item2]
    if (trimmed.len >= 2 and trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
        const list_str = trimmed[1 .. trimmed.len - 1];
        var list = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (list.items) |item| allocator.free(item);
            list.deinit(allocator);
        }

        var items = std.mem.splitScalar(u8, list_str, ',');
        while (items.next()) |item| {
            const trimmed_item = std.mem.trim(u8, item, &std.ascii.whitespace);
            if (trimmed_item.len > 0) {
                try list.append(allocator, try allocator.dupe(u8, trimmed_item));
            }
        }

        // For simplicity, we'll store as a JSON-like string representation
        var buffer = std.ArrayListUnmanaged(u8).initCapacity(allocator, list_str.len);
        try buffer.appendSlice(allocator, list_str);
        return YamlValue{ .string = buffer.toOwnedSlice(allocator) };
    }

    // Try to parse as number
    if (std.fmt.parseInt(i64, trimmed, 10)) |num| {
        return YamlValue{ .number = num };
    } else |_| {}

    // Default: treat as string
    return YamlValue{ .string = try allocator.dupe(u8, trimmed) };
}

/// Convert parsed YAML fields to Neurona
fn yamlToNeurona(allocator: Allocator, fields: std.StringHashMap(YamlValue), body: []const u8) !Neurona {
    _ = body;
    var neurona = try Neurona.init(allocator);
    errdefer neurona.deinit(allocator);

    // Set required fields
    if (fields.get("id")) |val| {
        if (val == .string) {
            const new_id = try allocator.dupe(u8, val.string);
            allocator.free(neurona.id);
            neurona.id = new_id;
        }
    }

    if (fields.get("title")) |val| {
        if (val == .string) {
            const new_title = try allocator.dupe(u8, val.string);
            allocator.free(neurona.title);
            neurona.title = new_title;
        }
    }

    if (fields.get("type")) |val| {
        if (val == .string) {
            const type_str = std.mem.trim(u8, val.string, &std.ascii.whitespace);
            neurona.type = parseNeuronaType(type_str);
        }
    }

    if (fields.get("updated")) |val| {
        if (val == .string) {
            const new_updated = try allocator.dupe(u8, val.string);
            allocator.free(neurona.updated);
            neurona.updated = new_updated;
        }
    }

    if (fields.get("language")) |val| {
        if (val == .string) {
            const new_language = try allocator.dupe(u8, val.string);
            allocator.free(neurona.language);
            allocator.free(neurona.language);
            neurona.language = new_language;
        }
    }

    if (fields.get("hash")) |val| {
        if (val == .string) {
            if (neurona.hash) |h| allocator.free(h);
            neurona.hash = try allocator.dupe(u8, val.string);
        }
    }

    // Parse tags
    if (fields.get("tags")) |val| {
        if (val == .string) {
            // Clear existing tags
            for (neurona.tags.items) |tag| allocator.free(tag);
            neurona.tags.clearRetainingCapacity(0);

            // Parse tag list
            const tags_str = std.mem.trim(u8, val.string, &std.ascii.whitespace);
            if (tags_str.len >= 2 and tags_str[0] == '[' and tags_str[tags_str.len - 1] == ']') {
                const list_str = tags_str[1 .. tags_str.len - 1];
                var items = std.mem.splitScalar(u8, list_str, ',');
                while (items.next()) |item| {
                    const trimmed = std.mem.trim(u8, item, &std.ascii.whitespace);
                    if (trimmed.len > 0) {
                        try neurona.tags.append(allocator, try allocator.dupe(u8, trimmed));
                    }
                }
            }
        }
    }

    // Parse LLM metadata
    if (fields.get("_llm")) |val| {
        if (val == .string) {
            // Simple implementation - assume JSON-like object stored as string
            neurona.llm_metadata = try parseLLMMetadata(allocator, val.string);
        }
    }

    // Parse context
    neurona.context = try parseContext(allocator, fields, neurona.type);

    return neurona;
}

/// Parse LLM metadata from string
fn parseLLMMetadata(allocator: Allocator, s: []const u8) !?LLMMetadata {
    // Simple implementation - parse key-value pairs from string
    var meta = LLMMetadata{
        .short_title = try allocator.dupe(u8, ""),
        .density = 2,
        .keywords = .{},
        .token_count = 0,
        .strategy = try allocator.dupe(u8, "full"),
    };
    errdefer meta.deinit(allocator);

    // Parse simple patterns like: t: "Short", d: 3, k: [k1, k2], c: 100
    var parts = std.mem.splitScalar(u8, s, ',');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, &std.ascii.whitespace);
        const colon_idx = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;

        const key = std.mem.trim(u8, trimmed[0..colon_idx], &std.ascii.whitespace);
        const value_str = trimmed[colon_idx + 1 ..];

        if (std.mem.eql(u8, key, "t")) {
            allocator.free(meta.short_title);
            const unquoted = try parseUnquoted(value_str, allocator);
            meta.short_title = unquoted;
        } else if (std.mem.eql(u8, key, "d")) {
            if (std.fmt.parseInt(u8, value_str, 10)) |d| {
                meta.density = d;
            } else |_| {}
        } else if (std.mem.eql(u8, key, "c")) {
            if (std.fmt.parseInt(u32, value_str, 10)) |c| {
                meta.token_count = c;
            } else |_| {}
        }
    }

    return meta;
}

/// Parse unquoted string
fn parseUnquoted(s: []const u8, allocator: Allocator) ![]const u8 {
    const trimmed = std.mem.trim(u8, s, &std.ascii.whitespace);
    if (trimmed.len >= 2 and (trimmed[0] == '"' or trimmed[0] == '\'')) {
        return allocator.dupe(u8, trimmed[1 .. trimmed.len - 1]);
    }
    return allocator.dupe(u8, trimmed);
}

/// Parse neurona type from string
fn parseNeuronaType(s: []const u8) NeuronaType {
    const normalized = std.ascii.lowerString(s);
    if (std.mem.eql(u8, normalized, "concept")) return .concept;
    if (std.mem.eql(u8, normalized, "reference")) return .reference;
    if (std.mem.eql(u8, normalized, "artifact")) return .artifact;
    if (std.mem.eql(u8, normalized, "state_machine")) return .state_machine;
    if (std.mem.eql(u8, normalized, "lesson")) return .lesson;
    if (std.mem.eql(u8, normalized, "requirement")) return .requirement;
    if (std.mem.eql(u8, normalized, "test_case")) return .test_case;
    if (std.mem.eql(u8, normalized, "issue")) return .issue;
    if (std.mem.eql(u8, normalized, "feature")) return .feature;
    return .concept; // Default
}

/// Parse context from YAML fields
fn parseContext(allocator: Allocator, fields: std.StringHashMap(YamlValue), neurona_type: NeuronaType) !Context {
    switch (neurona_type) {
        .requirement => {
            const status = if (fields.get("context.status")) |val| val.string else "draft";
            const priority = if (fields.get("context.priority")) |val| blk: {
                if (val == .number) {
                    const n = val.number;
                    break :blk @as(u8, @truncate(n));
                }
                break :blk 2;
            } else 2;
            const verification = if (fields.get("context.verification_method")) |val| val.string else "manual";
            const assignee = fields.get("context.assignee");

            var ctx = try createRequirementContext(allocator, status, priority, verification, assignee);
            errdefer ctx.deinit(allocator);
            return Context{ .requirement = ctx };
        },
        .test_case => {
            const status = if (fields.get("context.status")) |val| val.string else "not_run";
            const framework = if (fields.get("context.framework")) |val| val.string else "ztest";
            const priority = if (fields.get("context.priority")) |val| blk: {
                if (val == .number) {
                    const n = val.number;
                    break :blk @as(u8, @truncate(n));
                }
                break :blk 2;
            } else 2;
            const assignee = fields.get("context.assignee");

            var ctx = try createTestCaseContext(allocator, status, framework, priority, assignee);
            errdefer ctx.deinit(allocator);
            return Context{ .test_case = ctx };
        },
        .issue => {
            const status = if (fields.get("context.status")) |val| val.string else "open";
            const priority = if (fields.get("context.priority")) |val| blk: {
                if (val == .number) {
                    const n = val.number;
                    break :blk @as(u8, @truncate(n));
                }
                break :blk 2;
            } else 2;
            const assignee = fields.get("context.assignee");
            const created = if (fields.get("context.created")) |val| val.string else "";

            var ctx = try createIssueContext(allocator, status, priority, assignee, created);
            errdefer ctx.deinit(allocator);
            return Context{ .issue = ctx };
        },
        else => {
            return Context{ .none = {} };
        },
    }
}

/// Create requirement context
fn createRequirementContext(allocator: Allocator, status: []const u8, priority: u8, verification: []const u8, assignee: ?YamlValue) !Context.RequirementContext {
    return Context.RequirementContext{
        .status = try allocator.dupe(u8, status),
        .verification_method = try allocator.dupe(u8, verification),
        .priority = priority,
        .assignee = if (assignee) |val| blk: {
            if (val == .string) break :blk try allocator.dupe(u8, val.string);
            break :blk null;
        } else null,
        .effort_points = null,
        .sprint = null,
    };
}

/// Create test case context
fn createTestCaseContext(allocator: Allocator, status: []const u8, framework: []const u8, priority: u8, assignee: ?YamlValue) !Context.TestCaseContext {
    return Context.TestCaseContext{
        .framework = try allocator.dupe(u8, framework),
        .test_file = null,
        .status = try allocator.dupe(u8, status),
        .priority = priority,
        .assignee = if (assignee) |val| blk: {
            if (val == .string) break :blk try allocator.dupe(u8, val.string);
            break :blk null;
        } else null,
        .duration = null,
        .last_run = null,
    };
}

/// Create issue context
fn createIssueContext(allocator: Allocator, status: []const u8, priority: u8, assignee: ?YamlValue, created: []const u8) !Context.IssueContext {
    var created_list = std.ArrayListUnmanaged([]const u8){};
    try created_list.append(allocator, try allocator.dupe(u8, created));

    var resolved_list = std.ArrayListUnmanaged([]const u8){};
    var closed_list = std.ArrayListUnmanaged([]const u8){};
    var related_list = std.ArrayListUnmanaged([]const u8){};

    return Context.IssueContext{
        .status = try allocator.dupe(u8, status),
        .priority = priority,
        .assignee = if (assignee) |val| blk: {
            if (val == .string) break :blk try allocator.dupe(u8, val.string);
            break :blk null;
        } else null,
        .created = created_list.toOwnedSlice(allocator),
        .resolved = resolved_list.toOwnedSlice(allocator),
        .closed = closed_list.toOwnedSlice(allocator),
        .blocked_by = .{},
        .related_to = related_list.toOwnedSlice(allocator),
    };
}

/// Scan all Neurona files in a directory
pub fn scanNeuronas(allocator: Allocator, neuronas_dir: []const u8) ![]Neurona {
    var neuronas = std.ArrayListUnmanaged(Neurona){};
    errdefer {
        for (neuronas.items) |*n| n.deinit(allocator);
        neuronas.deinit(allocator);
    }

    var dir = try std.fs.openDirAbsolute(neuronas_dir, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!isNeuronaFile(entry.name)) continue;

        const filepath = try std.fs.path.join(allocator, &.{ neuronas_dir, entry.name });
        defer allocator.free(filepath);

        const neurona = try readNeurona(allocator, filepath);
        try neuronas.append(allocator, neurona);
    }

    return neuronas.toOwnedSlice(allocator);
}

/// Storage implementation struct
pub const Storage = struct {
    allocator: Allocator,
    neuronas_dir: []const u8,

    pub fn init(allocator: Allocator, neuronas_dir: []const u8) Storage {
        return Storage{
            .allocator = allocator,
            .neuronas_dir = neuronas_dir,
        };
    }

    pub fn deinit(self: *Storage) void {
        _ = self;
    }

    pub fn read(self: *const Storage, id: []const u8) !Neurona {
        const filename = try std.fmt.allocPrint(self.allocator, "{s}.md", .{id});
        defer self.allocator.free(filename);

        const filepath = try std.fs.path.join(self.allocator, &.{ self.neuronas_dir, filename });
        defer self.allocator.free(filepath);

        return readNeurona(self.allocator, filepath);
    }

    pub fn write(self: *const Storage, neurona: *const Neurona) !void {
        const filename = try std.fmt.allocPrint(self.allocator, "{s}.md", .{neurona.id});
        defer self.allocator.free(filename);

        const filepath = try std.fs.path.join(self.allocator, &.{ self.neuronas_dir, filename });
        defer self.allocator.free(filepath);

        // Build YAML frontmatter
        var yaml = std.ArrayListUnmanaged(u8).initCapacity(self.allocator, 512);
        defer yaml.deinit(self.allocator);

        try yaml.appendSlice(self.allocator, "---\n");
        try yaml.appendSlice(self.allocator, "id: ");
        try yaml.appendSlice(self.allocator, neurona.id);
        try yaml.appendSlice(self.allocator, "\n");

        try yaml.appendSlice(self.allocator, "title: ");
        try yaml.appendSlice(self.allocator, "\"");
        try yaml.appendSlice(self.allocator, neurona.title);
        try yaml.appendSlice(self.allocator, "\"");
        try yaml.appendSlice(self.allocator, "\n");

        try yaml.appendSlice(self.allocator, "type: ");
        try yaml.appendSlice(self.allocator, @tagName(neurona.type));
        try yaml.appendSlice(self.allocator, "\n");

        if (neurona.tags.items.len > 0) {
            try yaml.appendSlice(self.allocator, "tags: [");
            for (neurona.tags.items, 0..) |tag, i| {
                if (i > 0) try yaml.appendSlice(self.allocator, ", ");
                try yaml.appendSlice(self.allocator, "\"");
                try yaml.appendSlice(self.allocator, tag);
                try yaml.appendSlice(self.allocator, "\"");
            }
            try yaml.appendSlice(self.allocator, "]\n");
        }

        if (neurona.llm_metadata) |meta| {
            try yaml.appendSlice(self.allocator, "_llm:\n");
            try yaml.appendSlice(self.allocator, "  t: \"");
            try yaml.appendSlice(self.allocator, meta.short_title);
            try yaml.appendSlice(self.allocator, "\"\n");
            try yaml.appendSlice(self.allocator, "  d: ");
            try yaml.append(self.allocator, meta.density);
            try yaml.appendSlice(self.allocator, "\n");
            try yaml.appendSlice(self.allocator, "  c: ");
            try yaml.append(self.allocator, meta.token_count);
            try yaml.appendSlice(self.allocator, "\n");
        }

        try yaml.appendSlice(self.allocator, "---\n");

        // Write to file
        try std.fs.cwd().writeFile(.{
            .sub_path = filepath,
            .data = yaml.items,
        });
    }

    pub fn scan(self: *const Storage) ![]Neurona {
        return scanNeuronas(self.allocator, self.neuronas_dir);
    }
};

test "isNeuronaFile identifies markdown files" {
    try std.testing.expect(isNeuronaFile("test.md"));
    try std.testing.expect(!isNeuronaFile("test.txt"));
    try std.testing.expect(!isNeuronaFile("test"));
}

test "parseNeuronaType parses all types" {
    try std.testing.expectEqual(.concept, parseNeuronaType("concept"));
    try std.testing.expectEqual(.requirement, parseNeuronaType("Requirement"));
    try std.testing.expectEqual(.test_case, parseNeuronaType("TEST_CASE"));
    try std.testing.expectEqual(.issue, parseNeuronaType("Issue"));
    try std.testing.expectEqual(.concept, parseNeuronaType("unknown"));
}

test "Storage init creates valid structure" {
    const allocator = std.testing.allocator;

    const storage = Storage.init(allocator, "neuronas");
    _ = storage;
}

test "parseLLMMetadata parses simple format" {
    const allocator = std.testing.allocator;

    const s = "t: \"Short\", d: 3, c: 100";
    const meta = try parseLLMMetadata(allocator, s) orelse return error.ParseFailed;
    defer meta.deinit(allocator);

    try std.testing.expectEqualStrings("Short", meta.short_title);
    try std.testing.expectEqual(@as(u8, 3), meta.density);
    try std.testing.expectEqual(@as(u32, 100), meta.token_count);
}
