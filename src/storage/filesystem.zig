// Filesystem operations for Neurona files
// Handles reading, writing, and scanning Neurona Markdown files
const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Connection = @import("../core/neurona.zig").Connection;
const ConnectionType = @import("../core/neurona.zig").ConnectionType;
const LLMMetadata = @import("../core/neurona.zig").LLMMetadata;
const frontmatter = @import("../utils/frontmatter.zig").Frontmatter;
const yaml = @import("../utils/yaml.zig");
const validator = @import("../core/validator.zig");
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
        // Deinitialize each Value in the HashMap before freeing the HashMap itself
        var it = yaml_data.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        yaml_data.deinit();
    }

    // Validate that connections are only in frontmatter (not in body)
    try validator.validateConnectionsLocation(fm.body);

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

/// Parse context from YAML object based on neurona type
fn parseContext(allocator: Allocator, ctx_obj: std.StringHashMap(yaml.Value), neurona_type: NeuronaType) !@import("../core/neurona.zig").Context {
    const Context = @import("../core/neurona.zig").Context;

    // Try to infer context type from fields present
    const has_status = ctx_obj.get("status") != null;
    const has_framework = ctx_obj.get("framework") != null;
    const has_runtime = ctx_obj.get("runtime") != null;
    const has_verification_method = ctx_obj.get("verification_method") != null;
    const has_entry_action = ctx_obj.get("entry_action") != null;

    // Handle feature, lesson, reference, concept types as custom context
    if (neurona_type == .feature or neurona_type == .lesson or neurona_type == .reference or neurona_type == .concept) {
        var custom = std.StringHashMap([]const u8).init(allocator);
        errdefer {
            var it = custom.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            custom.deinit();
        }

        var it = ctx_obj.iterator();
        while (it.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const val = try allocator.dupe(u8, getString(entry.value_ptr.*, ""));
            try custom.put(key, val);
        }

        return Context{ .custom = custom };
    }

    if (has_verification_method) {
        var ctx = Context{ .requirement = undefined };
        ctx.requirement = .{
            .status = try allocator.dupe(u8, if (ctx_obj.get("status")) |v| getString(v, "draft") else "draft"),
            .verification_method = try allocator.dupe(u8, if (ctx_obj.get("verification_method")) |v| getString(v, "test") else "test"),
            .priority = @intCast(if (ctx_obj.get("priority")) |v| getInt(v, 3) else 3),
            .assignee = null,
            .effort_points = null,
            .sprint = null,
        };
        if (ctx_obj.get("assignee")) |a| {
            const s = getString(a, "");
            if (s.len > 0) ctx.requirement.assignee = try allocator.dupe(u8, s);
        }
        if (ctx_obj.get("effort_points")) |e| {
            ctx.requirement.effort_points = @intCast(getInt(e, 0));
        }
        if (ctx_obj.get("sprint")) |s| {
            const str = getString(s, "");
            if (str.len > 0) ctx.requirement.sprint = try allocator.dupe(u8, str);
        }
        return ctx;
    }

    if (has_framework) {
        var ctx = Context{ .test_case = undefined };
        ctx.test_case = .{
            .framework = try allocator.dupe(u8, if (ctx_obj.get("framework")) |v| getString(v, "unknown") else "unknown"),
            .test_file = null,
            .status = try allocator.dupe(u8, if (ctx_obj.get("status")) |v| getString(v, "pending") else "pending"),
            .priority = @intCast(if (ctx_obj.get("priority")) |v| getInt(v, 3) else 3),
            .assignee = null,
            .duration = null,
            .last_run = null,
        };
        if (ctx_obj.get("test_file")) |f| {
            const s = getString(f, "");
            if (s.len > 0) ctx.test_case.test_file = try allocator.dupe(u8, s);
        }
        if (ctx_obj.get("assignee")) |a| {
            const s = getString(a, "");
            if (s.len > 0) ctx.test_case.assignee = try allocator.dupe(u8, s);
        }
        if (ctx_obj.get("duration")) |d| {
            const s = getString(d, "");
            if (s.len > 0) ctx.test_case.duration = try allocator.dupe(u8, s);
        }
        if (ctx_obj.get("last_run")) |l| {
            const s = getString(l, "");
            if (s.len > 0) ctx.test_case.last_run = try allocator.dupe(u8, s);
        }
        return ctx;
    }

    if (has_runtime) {
        var ctx = Context{ .artifact = undefined };
        ctx.artifact = .{
            .runtime = try allocator.dupe(u8, if (ctx_obj.get("runtime")) |v| getString(v, "unknown") else "unknown"),
            .file_path = try allocator.dupe(u8, if (ctx_obj.get("file_path")) |v| getString(v, "") else ""),
            .safe_to_exec = if (ctx_obj.get("safe_to_exec")) |v| getBool(v, false) else false,
            .language_version = null,
            .last_modified = null,
        };
        if (ctx_obj.get("language_version")) |v| {
            const s = getString(v, "");
            if (s.len > 0) ctx.artifact.language_version = try allocator.dupe(u8, s);
        }
        if (ctx_obj.get("last_modified")) |m| {
            const s = getString(m, "");
            if (s.len > 0) ctx.artifact.last_modified = try allocator.dupe(u8, s);
        }
        return ctx;
    }

    if (has_entry_action) {
        var triggers = std.ArrayListUnmanaged([]const u8){};
        var allowed_roles = std.ArrayListUnmanaged([]const u8){};
        errdefer {
            for (triggers.items) |t| allocator.free(t);
            triggers.deinit(allocator);
            for (allowed_roles.items) |r| allocator.free(r);
            allowed_roles.deinit(allocator);
        }

        if (ctx_obj.get("triggers")) |t| {
            const arr = try getArray(t, allocator, &[_][]const u8{});
            for (arr) |trigger| try triggers.append(allocator, trigger);
            allocator.free(arr);
        }
        if (ctx_obj.get("allowed_roles")) |r| {
            const arr = try getArray(r, allocator, &[_][]const u8{});
            for (arr) |role| try allowed_roles.append(allocator, role);
            allocator.free(arr);
        }

        var ctx = Context{ .state_machine = undefined };
        ctx.state_machine = .{
            .triggers = triggers,
            .entry_action = try allocator.dupe(u8, if (ctx_obj.get("entry_action")) |v| getString(v, "") else ""),
            .exit_action = try allocator.dupe(u8, if (ctx_obj.get("exit_action")) |v| getString(v, "") else ""),
            .allowed_roles = allowed_roles,
        };
        return ctx;
    }

    if (has_status or neurona_type == .issue) {
        var ctx = Context{ .issue = undefined };
        var blocked_by = std.ArrayListUnmanaged([]const u8){};
        var related_to = std.ArrayListUnmanaged([]const u8){};
        errdefer {
            for (blocked_by.items) |b| allocator.free(b);
            blocked_by.deinit(allocator);
            for (related_to.items) |r| allocator.free(r);
            related_to.deinit(allocator);
        }

        if (ctx_obj.get("blocked_by")) |b| {
            const arr = try getArray(b, allocator, &[_][]const u8{});
            for (arr) |item| try blocked_by.append(allocator, item);
            allocator.free(arr);
        }
        if (ctx_obj.get("related_to")) |r| {
            const arr = try getArray(r, allocator, &[_][]const u8{});
            for (arr) |item| try related_to.append(allocator, item);
            allocator.free(arr);
        }

        ctx.issue = .{
            .status = try allocator.dupe(u8, if (ctx_obj.get("status")) |v| getString(v, "open") else "open"),
            .priority = @intCast(if (ctx_obj.get("priority")) |v| getInt(v, 3) else 3),
            .assignee = null,
            .created = try allocator.dupe(u8, if (ctx_obj.get("created")) |v| getString(v, "") else ""),
            .resolved = null,
            .closed = null,
            .blocked_by = blocked_by,
            .related_to = related_to,
        };
        if (ctx_obj.get("assignee")) |a| {
            const s = getString(a, "");
            if (s.len > 0) ctx.issue.assignee = try allocator.dupe(u8, s);
        }
        if (ctx_obj.get("resolved")) |r| {
            const s = getString(r, "");
            if (s.len > 0) ctx.issue.resolved = try allocator.dupe(u8, s);
        }
        if (ctx_obj.get("closed")) |c| {
            const s = getString(c, "");
            if (s.len > 0) ctx.issue.closed = try allocator.dupe(u8, s);
        }
        return ctx;
    }

    // Default: custom context for any other fields
    var custom = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = custom.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        custom.deinit();
    }

    var it = ctx_obj.iterator();
    while (it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const val = try allocator.dupe(u8, getString(entry.value_ptr.*, ""));
        try custom.put(key, val);
    }

    return Context{ .custom = custom };
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
                                                // Check for "target_id" (new format) or "id" (legacy format)
                                                const target_id_val = t_obj.get("target_id") orelse t_obj.get("id");
                                                if (target_id_val) |tid_val| {
                                                    const target_id = getString(tid_val, "");
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

    // Tier 3 field: _llm (optional) - check for flattened _llm_ fields
    const llm_t = yaml_data.get("_llm_t");
    const llm_d = yaml_data.get("_llm_d");
    const llm_k = yaml_data.get("_llm_k");
    const llm_c = yaml_data.get("_llm_c");
    const llm_strategy = yaml_data.get("_llm_strategy");

    // If any _llm_ field exists, parse_as metadata
    if (llm_t != null or llm_d != null or llm_k != null or llm_c != null or llm_strategy != null) {
        var metadata = LLMMetadata{
            .short_title = try allocator.dupe(u8, ""),
            .density = 2,
            .keywords = .{},
            .token_count = 0,
            .strategy = try allocator.dupe(u8, "summary"),
        };

        if (llm_t) |t_val| {
            const short_title = getString(t_val, "");
            if (short_title.len > 0) {
                allocator.free(metadata.short_title);
                metadata.short_title = try allocator.dupe(u8, short_title);
            }
        }

        if (llm_d) |d_val| {
            metadata.density = @intCast(getInt(d_val, 2));
        }

        if (llm_k) |k_val| {
            const keywords = try getArray(k_val, allocator, &[_][]const u8{});
            for (keywords) |kw| {
                try metadata.keywords.append(allocator, kw);
            }
            allocator.free(keywords);
        }

        if (llm_c) |c_val| {
            metadata.token_count = @intCast(getInt(c_val, 0));
        }

        if (llm_strategy) |s_val| {
            const strategy = getString(s_val, "summary");
            if (strategy.len > 0) {
                allocator.free(metadata.strategy);
                metadata.strategy = try allocator.dupe(u8, strategy);
            }
        }

        neurona.llm_metadata = metadata;
    }

    // Tier 3 field: context (optional)
    if (yaml_data.get("context")) |ctx_val| {
        switch (ctx_val) {
            .object => |ctx_obj_opt| {
                if (ctx_obj_opt) |ctx_obj| {
                    neurona.context = try parseContext(allocator, ctx_obj, neurona.type);
                }
            },
            else => {},
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

    // Preserve existing body content if file exists
    var body_content: []const u8 = "";
    defer allocator.free(body_content);
    if (std.fs.cwd().openFile(filepath, .{})) |file| {
        defer file.close();
        const existing_content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch "";
        defer allocator.free(existing_content);
        if (existing_content.len > 0) {
            const fm = frontmatter.parse(allocator, existing_content) catch null;
            if (fm) |*f| {
                defer f.deinit(allocator);
                body_content = try allocator.dupe(u8, f.body);
            }
        }
    } else |_| {}

    // Generate complete Markdown content
    const content = try generateMarkdown(allocator, yaml_content, body_content);
    defer allocator.free(content);

    // Write to file
    const file = try std.fs.cwd().createFile(filepath, .{});
    defer file.close();
    try file.writeAll(content);
}

/// Convert Neurona struct to YAML frontmatter string
pub fn neuronaToYaml(allocator: Allocator, neurona: Neurona) ![]u8 {
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

    // Connections (Tier 2) - Use simplified array format for YAML parser compatibility
    // Format: ["type:target_id:weight"]
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

    // Tier 3 field: _llm (optional) - serialize as flattened fields
    if (neurona.llm_metadata) |*meta| {
        try writer.print("_llm_t: {s}\n", .{meta.short_title});
        try writer.print("_llm_d: {d}\n", .{meta.density});
        if (meta.keywords.items.len > 0) {
            try writer.writeAll("_llm_k: [");
            for (meta.keywords.items, 0..) |kw, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("\"{s}\"", .{kw});
            }
            try writer.writeAll("]\n");
        }
        try writer.print("_llm_c: {d}\n", .{meta.token_count});
        try writer.print("_llm_strategy: {s}\n", .{meta.strategy});
    }

    // Tier 3 field: context (optional)
    try writer.writeAll("context:\n");
    switch (neurona.context) {
        .none => {},
        .artifact => |*ctx| {
            if (ctx.runtime.len > 0) try writer.print("  runtime: {s}\n", .{ctx.runtime});
            if (ctx.file_path.len > 0) try writer.print("  file_path: {s}\n", .{ctx.file_path});
            try writer.print("  safe_to_exec: {}\n", .{ctx.safe_to_exec});
            if (ctx.language_version) |v| try writer.print("  language_version: {s}\n", .{v});
            if (ctx.last_modified) |m| try writer.print("  last_modified: {s}\n", .{m});
        },
        .test_case => |*ctx| {
            if (ctx.framework.len > 0) try writer.print("  framework: {s}\n", .{ctx.framework});
            if (ctx.test_file) |f| try writer.print("  test_file: {s}\n", .{f});
            if (ctx.status.len > 0) try writer.print("  status: {s}\n", .{ctx.status});
            try writer.print("  priority: {d}\n", .{ctx.priority});
            if (ctx.assignee) |a| try writer.print("  assignee: {s}\n", .{a});
            if (ctx.duration) |d| try writer.print("  duration: {s}\n", .{d});
            if (ctx.last_run) |l| try writer.print("  last_run: {s}\n", .{l});
        },
        .issue => |*ctx| {
            if (ctx.status.len > 0) try writer.print("  status: {s}\n", .{ctx.status});
            try writer.print("  priority: {d}\n", .{ctx.priority});
            if (ctx.assignee) |a| try writer.print("  assignee: {s}\n", .{a});
            if (ctx.created.len > 0) try writer.print("  created: {s}\n", .{ctx.created});
            if (ctx.resolved) |r| try writer.print("  resolved: {s}\n", .{r});
            if (ctx.closed) |c| try writer.print("  closed: {s}\n", .{c});
            if (ctx.blocked_by.items.len > 0) {
                try writer.writeAll("  blocked_by: [");
                for (ctx.blocked_by.items, 0..) |b, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("\"{s}\"", .{b});
                }
                try writer.writeAll("]\n");
            }
            if (ctx.related_to.items.len > 0) {
                try writer.writeAll("  related_to: [");
                for (ctx.related_to.items, 0..) |r, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("\"{s}\"", .{r});
                }
                try writer.writeAll("]\n");
            }
        },
        .requirement => |*ctx| {
            if (ctx.status.len > 0) try writer.print("  status: {s}\n", .{ctx.status});
            if (ctx.verification_method.len > 0) try writer.print("  verification_method: {s}\n", .{ctx.verification_method});
            try writer.print("  priority: {d}\n", .{ctx.priority});
            if (ctx.assignee) |a| try writer.print("  assignee: {s}\n", .{a});
            if (ctx.effort_points) |e| try writer.print("  effort_points: {d}\n", .{e});
            if (ctx.sprint) |s| try writer.print("  sprint: {s}\n", .{s});
        },
        .state_machine => |*ctx| {
            if (ctx.triggers.items.len > 0) {
                try writer.writeAll("  triggers: [");
                for (ctx.triggers.items, 0..) |t, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("\"{s}\"", .{t});
                }
                try writer.writeAll("]\n");
            }
            if (ctx.entry_action.len > 0) try writer.print("  entry_action: {s}\n", .{ctx.entry_action});
            if (ctx.exit_action.len > 0) try writer.print("  exit_action: {s}\n", .{ctx.exit_action});
            if (ctx.allowed_roles.items.len > 0) {
                try writer.writeAll("  allowed_roles: [");
                for (ctx.allowed_roles.items, 0..) |r, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writer.print("\"{s}\"", .{r});
                }
                try writer.writeAll("]\n");
            }
        },
        .custom => |*ctx| {
            var it = ctx.iterator();
            while (it.next()) |entry| {
                try writer.print("  {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        },
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
        const neurona = readNeurona(allocator, filepath) catch {
            // Skip invalid files but continue scanning
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

/// Get the latest modification time (nanoseconds) of any file in a directory
pub fn getLatestModificationTime(directory: []const u8) !i64 {
    var dir = std.fs.cwd().openDir(directory, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return 0;
        return err;
    };
    defer dir.close();

    var latest: i64 = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            const stat = try dir.statFile(entry.name);
            if (stat.mtime > latest) latest = @intCast(stat.mtime);
        }
    }
    return latest;
}
