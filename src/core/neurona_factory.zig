// Core Neurona Factory
// Manages the creation of new Neuronas, including templating and validation
// Decoupled from CLI output/input

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("neurona.zig").Neurona;
const NeuronaType = @import("neurona.zig").NeuronaType;
const id_gen = @import("../utils/id_generator.zig");
const timestamp = @import("../utils/timestamp.zig");

pub const CreationConfig = struct {
    type: NeuronaType,
    title: []const u8,
    tags: []const []const u8 = &[_][]const u8{},
    
    // Optional context overrides
    assignee: ?[]const u8 = null,
    priority: ?u8 = null,
    
    // Relationships
    parent: ?[]const u8 = null,
    validates: ?[]const u8 = null,
    blocks: ?[]const u8 = null,
};

pub const CreationResult = struct {
    id: []const u8,
    content: []const u8, // The full markdown content
    filepath: []const u8, // Suggested relative filepath
};

/// Generate a new Neurona based on configuration and templates
pub fn create(allocator: Allocator, config: CreationConfig) !CreationResult {
    // 1. Generate ID
    const prefix = getTypePrefix(config.type);
    const id = try id_gen.fromTitleWithPrefix(allocator, prefix, config.title);
    
    // 2. Get Template
    const template = getTemplate(config.type);

    // 3. Gather Context (Programmatic)
    var context = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = context.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        context.deinit();
    }
    try gatherContext(allocator, &context, config, template);

    // 4. Build Connections
    var connections = std.ArrayList(Connection).init(allocator);
    defer connections.deinit();
    try buildConnections(allocator, &connections, config);

    // 5. Generate Content
    const content = try generateFileContent(allocator, id, config, template, context, connections.items);
    
    // 6. Determine Filepath
    const filepath = try std.fmt.allocPrint(allocator, "neuronas/{s}.md", .{id});

    return CreationResult{
        .id = id,
        .content = content, // Caller owns memory
        .filepath = filepath, // Caller owns memory
    };
}

const Connection = struct {
    type: []const u8,
    target: []const u8,
    weight: u8 = 100,
};

const TemplateConfig = struct {
    type_name: []const u8,
    tier: u8,
    default_tags: []const []const u8,
    required_context: []const []const u8,
    optional_context: []const []const u8,
    content_sections: []const []const u8,
};

fn getTypePrefix(t: NeuronaType) []const u8 {
    return switch (t) {
        .requirement => "req",
        .test_case => "test",
        .issue => "issue",
        .artifact => "art",
        .feature => "feat",
        .concept => "concept",
        .reference => "reference",
        .lesson => "lesson",
        else => "neurona",
    };
}

fn getTemplate(t: NeuronaType) TemplateConfig {
    switch (t) {
        .concept => return .{
            .type_name = "concept",
            .tier = 2,
            .default_tags = &[_][]const u8{"concept"},
            .required_context = &[_][]const u8{"definition"},
            .optional_context = &[_][]const u8{"difficulty", "examples"},
            .content_sections = &[_][]const u8{
                "Definition",
                "Key Points",
                "Examples",
                "Related Concepts"
            },
        },
        .reference => return .{
            .type_name = "reference",
            .tier = 2,
            .default_tags = &[_][]const u8{"reference"},
            .required_context = &[_][]const u8{"source"},
            .optional_context = &[_][]const u8{"url", "author", "citation"},
            .content_sections = &[_][]const u8{
                "Source",
                "Key Information",
                "Notes",
            },
        },
        .lesson => return .{
            .type_name = "lesson",
            .tier = 2,
            .default_tags = &[_][]const u8{"lesson"},
            .required_context = &[_][]const u8{"learning_objectives"},
            .optional_context = &[_][]const u8{
                "prerequisites",
                "key_takeaways",
                "difficulty",
                "estimated_time"
            },
            .content_sections = &[_][]const u8{
                "Learning Objectives",
                "Prerequisites",
                "Content",
                "Key Takeaways",
            },
        },
        .requirement => return .{
            .type_name = "requirement",
            .tier = 2,
            .default_tags = &[_][]const u8{"requirement"},
            .required_context = &[_][]const u8{"status", "verification_method"},
            .optional_context = &[_][]const u8{"assignee", "priority", "effort_points"},
            .content_sections = &[_][]const u8{
                "Description",
                "Acceptance Criteria",
                "Notes",
            },
        },
        .test_case => return .{
            .type_name = "test_case",
            .tier = 2,
            .default_tags = &[_][]const u8{"test"},
            .required_context = &[_][]const u8{"status", "framework"},
            .optional_context = &[_][]const u8{"priority", "assignee", "duration"},
            .content_sections = &[_][]const u8{
                "Test Description",
                "Test Steps",
                "Expected Results",
            },
        },
        .issue => return .{
            .type_name = "issue",
            .tier = 2,
            .default_tags = &[_][]const u8{"issue"},
            .required_context = &[_][]const u8{"status", "created"},
            .optional_context = &[_][]const u8{"priority", "assignee", "resolved", "closed"},
            .content_sections = &[_][]const u8{
                "Issue Description",
                "Steps to Reproduce",
                "Expected Behavior",
                "Actual Behavior",
            },
        },
        .artifact => return .{
            .type_name = "artifact",
            .tier = 2,
            .default_tags = &[_][]const u8{"artifact"},
            .required_context = &[_][]const u8{"runtime", "file_path"},
            .optional_context = &[_][]const u8{"language_version", "last_modified"},
            .content_sections = &[_][]const u8{
                "Description",
                "Usage",
                "Notes",
            },
        },
        .feature => return .{
            .type_name = "feature",
            .tier = 2,
            .default_tags = &[_][]const u8{"feature"},
            .required_context = &[_][]const u8{},
            .optional_context = &[_][]const u8{},
            .content_sections = &[_][]const u8{
                "Description",
                "Implementation Plan",
                "Notes",
            },
        },
        else => return .{
            .type_name = "neurona",
            .tier = 1,
            .default_tags = &[_][]const u8{},
            .required_context = &[_][]const u8{},
            .optional_context = &[_][]const u8{},
            .content_sections = &[_][]const u8{
                "Content",
            },
        },
    }
}

fn gatherContext(allocator: Allocator, context: *std.StringHashMap([]const u8), config: CreationConfig, template: TemplateConfig) !void {
    for (template.required_context) |field| {
        const val = if (shouldAutoFill(field, config)) |v| v else getDefaultForField(field, config.type);
        try context.put(field, try allocator.dupe(u8, val));
    }
}

fn shouldAutoFill(field: []const u8, config: CreationConfig) ?[]const u8 {
    if (std.mem.eql(u8, field, "assignee") and config.assignee != null) return config.assignee.?;
    if (std.mem.eql(u8, field, "priority") and config.priority != null) {
        // Simplified conversion
        const p = config.priority.?;
        if (p == 1) return "1";
        return "3"; 
    }
    return null;
}

fn getDefaultForField(field: []const u8, t: NeuronaType) []const u8 {
    if (std.mem.eql(u8, field, "verification_method")) return "test";
    if (std.mem.eql(u8, field, "framework")) return "pytest";
    if (std.mem.eql(u8, field, "priority")) return "3";
    if (std.mem.eql(u8, field, "status")) {
        return switch (t) {
            .requirement => "draft",
            .test_case => "not_run",
            .issue => "open",
            else => "active",
        };
    }
    if (std.mem.eql(u8, field, "created")) return "[timestamp]";
    return "unspecified";
}

fn buildConnections(allocator: Allocator, list: *std.ArrayList(Connection), config: CreationConfig) !void {
    if (config.parent) |p| try list.append(.{ .type = "parent", .target = try allocator.dupe(u8, p), .weight = 90 });
    if (config.validates) |v| try list.append(.{ .type = "validates", .target = try allocator.dupe(u8, v), .weight = 100 });
    if (config.blocks) |b| try list.append(.{ .type = "blocks", .target = try allocator.dupe(u8, b), .weight = 100 });
}

fn generateFileContent(allocator: Allocator, id: []const u8, config: CreationConfig, template: TemplateConfig, context: std.StringHashMap([]const u8), connections: []const Connection) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    const writer = buf.writer();

    try writer.writeAll("---\n");
    try writer.print("id: {s}\n", .{id});
    try writer.print("title: {s}\n", .{config.title});
    try writer.print("type: {s}\n", .{@tagName(config.type)}); // Use enum tagName

    try writer.writeAll("tags: [");
    for (template.default_tags, 0..) |tag, i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.print("\"{s}\"", .{tag});
    }
    for (config.tags, 0..) |tag, i| {
        if (template.default_tags.len > 0 or i > 0) try writer.writeAll(", ");
        try writer.print("\"{s}\"", .{tag});
    }
    try writer.writeAll("]\n\n");

    if (connections.len > 0) {
        try writer.writeAll("connections:\n");
        // Simple output
        for (connections) |conn| {
            try writer.print("  {s}:\n", .{conn.type});
            try writer.print("    - id: {s}\n", .{conn.target});
            try writer.print("      weight: {d}\n", .{conn.weight});
        }
        try writer.writeAll("\n");
    }

    try writer.writeAll("context:\n");
    var it = context.iterator();
    while (it.next()) |entry| {
        try writer.print("  {s}: {s}\n", .{entry.key_ptr.*, entry.value_ptr.*});
    }

    const now = try timestamp.getCurrentTimestamp(allocator);
    defer allocator.free(now);
    try writer.print("\nupdated: \"{s}\"\n", .{now});
    try writer.writeAll("language: en\n");
    try writer.writeAll("---\n\n");

    try writer.print("# {s}\n\n", .{config.title});
    for (template.content_sections) |sec| {
        try writer.print("## {s}\n\n[Write content here]\n\n", .{sec});
    }

    return buf.toOwnedSlice();
}