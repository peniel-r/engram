// File: src/cli/update.zig
// The `engram update` command for updating Neurona fields programmatically
// Supports setting tier1, tier2, and tier3 fields
// MIGRATED: Now uses Phase 3 CLI utilities (HumanOutput)
// MIGRATED: Now uses lib types via root.zig

const std = @import("std");
const Allocator = std.mem.Allocator;
// Use lib types via root.zig (Phase 4 migration)
const Neurona = @import("../root.zig").Neurona;
const NeuronaType = @import("../root.zig").NeuronaType;
const Connection = @import("../root.zig").Connection;
const ConnectionType = @import("../root.zig").ConnectionType;
const LLMMetadata = @import("../lib/core/types.zig").LLMMetadata;
const readNeurona = @import("../storage/filesystem.zig").readNeurona;
const writeNeurona = @import("../storage/filesystem.zig").writeNeurona;
const findNeuronaPath = @import("../storage/filesystem.zig").findNeuronaPath;
const updateBody = @import("../storage/filesystem.zig").updateBody;
const timestamp_mod = @import("../utils/timestamp.zig");
const state_machine = @import("../core/state_machine.zig");
const uri_parser = @import("../utils/uri_parser.zig");

// Import Phase 3 CLI utilities
const HumanOutput = @import("output/human.zig").HumanOutput;

/// Update configuration
pub const UpdateConfig = struct {
    id: []const u8,
    sets: std.ArrayListUnmanaged(FieldUpdate),
    verbose: bool = false,
    cortex_dir: ?[]const u8 = null,
};

/// Field update specification
pub const FieldUpdate = struct {
    field: []const u8,
    value: []const u8,
    operator: UpdateOperator = .set,

    pub fn deinit(self: *FieldUpdate, allocator: Allocator) void {
        allocator.free(self.field);
        allocator.free(self.value);
    }
};

/// Update operators
pub const UpdateOperator = enum {
    set, // Set field to value
    append, // Append to list (for tags)
    remove, // Remove value from list
};

/// Main command handler
pub fn execute(allocator: Allocator, config: UpdateConfig) !void {
    // Determine neuronas directory
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

    // Step 1: Find and load Neurona
    const filepath = try findNeuronaPath(allocator, neuronas_dir, config.id);
    defer allocator.free(filepath);

    var neurona = try readNeurona(allocator, filepath);
    defer neurona.deinit(allocator);

    // Step 2: Apply updates
    var updated = false;
    var body_updated = false;
    for (config.sets.items) |*update_item| {
        if (try applyUpdate(allocator, &neurona, update_item.*, config.verbose, neuronas_dir)) {
            updated = true;
        }
        if (std.mem.eql(u8, update_item.field, "content")) {
            body_updated = true;
        }
    }

    if (!updated) {
        if (config.verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("No changes applied to {s}\n", .{config.id});
            try stdout.flush();
        }
        return;
    }

    // Step 3: Update timestamp
    allocator.free(neurona.updated);
    const ts = try timestamp_mod.getCurrentTimestamp(allocator);
    neurona.updated = try allocator.dupe(u8, ts);
    allocator.free(ts);

    // Step 4: Write back to file (skip if body was already updated)
    if (!body_updated) {
        try writeNeurona(allocator, neurona, filepath, false);
    }

    if (config.verbose) {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("Updated {s}\n", .{config.id});
        try stdout.flush();
    } else {
        try HumanOutput.printSuccess(config.id);
    }
}

/// Apply a field update to a Neurona
fn applyUpdate(allocator: Allocator, neurona: *Neurona, update: FieldUpdate, verbose: bool, neuronas_dir: []const u8) !bool {
    if (std.mem.eql(u8, update.field, "content")) {
        // Update markdown body content (not frontmatter)
        const body_filepath = try findNeuronaPath(allocator, neuronas_dir, neurona.id);
        defer allocator.free(body_filepath);
        try updateBody(allocator, body_filepath, update.value);
        if (verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("  Set body content to: {s}...\n", .{update.value[0..@min(50, update.value.len)]});
            try stdout.flush();
        }
        return true;
    }

    if (std.mem.eql(u8, update.field, "_llm_t")) {
        return try updateLLMMetadata(allocator, neurona, "short_title", update.value, verbose);
    }
    if (std.mem.eql(u8, update.field, "_llm_d")) {
        return try updateLLMMetadata(allocator, neurona, "density", update.value, verbose);
    }
    if (std.mem.eql(u8, update.field, "_llm_k")) {
        return try updateLLMMetadata(allocator, neurona, "keywords", update.value, verbose);
    }
    if (std.mem.eql(u8, update.field, "_llm_c")) {
        return try updateLLMMetadata(allocator, neurona, "token_count", update.value, verbose);
    }
    if (std.mem.eql(u8, update.field, "_llm_strategy")) {
        return try updateLLMMetadata(allocator, neurona, "strategy", update.value, verbose);
    }

    if (std.mem.eql(u8, update.field, "title")) {
        allocator.free(neurona.title);
        neurona.title = try allocator.dupe(u8, update.value);
        if (verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("  Set title to: {s}\n", .{update.value});
            try stdout.flush();
        }
        return true;
    }

    if (std.mem.eql(u8, update.field, "type")) {
        neurona.type = parseNeuronaType(update.value) catch {
            try HumanOutput.printError("Invalid type '{s}'");
            return false;
        };
        if (verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("  Set type to: {s}\n", .{update.value});
            try stdout.flush();
        }
        return true;
    }

    if (std.mem.eql(u8, update.field, "language")) {
        allocator.free(neurona.language);
        neurona.language = try allocator.dupe(u8, update.value);
        if (verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("  Set language to: {s}\n", .{update.value});
            try stdout.flush();
        }
        return true;
    }

    if (std.mem.eql(u8, update.field, "tag")) {
        if (update.operator == .append) {
            try neurona.tags.append(allocator, try allocator.dupe(u8, update.value));
            if (verbose) {
                var stdout_buffer: [4096]u8 = undefined;
                var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
                const stdout = &stdout_writer.interface;
                try stdout.print("  Added tag: {s}\n", .{update.value});
                try stdout.flush();
            }
        } else if (update.operator == .remove) {
            // Remove tag if exists
            var found: usize = 0;
            for (neurona.tags.items, 0..) |tag, i| {
                if (std.mem.eql(u8, tag, update.value)) {
                    found = i;
                    break;
                }
            }
            if (found > 0 or (neurona.tags.items.len > 0 and std.mem.eql(u8, neurona.tags.items[0], update.value))) {
                allocator.free(neurona.tags.orderedRemove(found));
                if (verbose) {
                    var stdout_buffer: [4096]u8 = undefined;
                    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
                    const stdout = &stdout_writer.interface;
                    try stdout.print("  Removed tag: {s}\n", .{update.value});
                    try stdout.flush();
                }
                return true;
            }
        }
        return true;
    }

    if (std.mem.eql(u8, update.field, "hash")) {
        if (neurona.hash) |h| allocator.free(h);
        neurona.hash = try allocator.dupe(u8, update.value);
        if (verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("  Set hash to: {s}\n", .{update.value});
            try stdout.flush();
        }
        return true;
    }

    // Handle context.* fields
    if (std.mem.startsWith(u8, update.field, "context.")) {
        return try applyContextUpdate(allocator, neurona, update.field["context.".len..], update.value, verbose);
    }

    try HumanOutput.printError("Unknown field '{s}'");
    return false;
}

/// Apply update to context field
fn applyContextUpdate(allocator: Allocator, neurona: *Neurona, context_field: []const u8, value: []const u8, verbose: bool) !bool {
    _ = verbose;

    switch (neurona.context) {
        .test_case => |*ctx| {
            if (std.mem.eql(u8, context_field, "status")) {
                // Validate state transition
                const current = ctx.status;
                if (!state_machine.isValidTransitionByType("test_case", current, value)) {
                    const err_msg = state_machine.getTransitionError("test_case", current, value);
                    try HumanOutput.printError(err_msg);
                    return false;
                }

                allocator.free(ctx.status);
                ctx.status = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "framework")) {
                allocator.free(ctx.framework);
                ctx.framework = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "priority")) {
                ctx.priority = std.fmt.parseInt(u8, value, 10) catch {
                    try HumanOutput.printError("Invalid priority '{s}'");
                    return false;
                };
                return true;
            }
            if (std.mem.eql(u8, context_field, "assignee")) {
                if (ctx.assignee) |a| allocator.free(a);
                ctx.assignee = try allocator.dupe(u8, value);
                return true;
            }
        },
        .artifact => |*ctx| {
            if (std.mem.eql(u8, context_field, "runtime")) {
                allocator.free(ctx.runtime);
                ctx.runtime = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "file_path")) {
                allocator.free(ctx.file_path);
                ctx.file_path = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "safe_to_exec")) {
                ctx.safe_to_exec = std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1");
                return true;
            }
        },
        .state_machine => |*ctx| {
            if (std.mem.eql(u8, context_field, "entry_action")) {
                allocator.free(ctx.entry_action);
                ctx.entry_action = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "exit_action")) {
                allocator.free(ctx.exit_action);
                ctx.exit_action = try allocator.dupe(u8, value);
                return true;
            }
        },
        .issue => |*ctx| {
            if (std.mem.eql(u8, context_field, "status")) {
                // Validate state transition
                const current = ctx.status;
                if (!state_machine.isValidTransitionByType("issue", current, value)) {
                    const err_msg = state_machine.getTransitionError("issue", current, value);
                    try HumanOutput.printError(err_msg);
                    return false;
                }

                allocator.free(ctx.status);
                ctx.status = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "priority")) {
                ctx.priority = std.fmt.parseInt(u8, value, 10) catch {
                    try HumanOutput.printError("Invalid priority '{s}'");
                    return false;
                };
                return true;
            }
            if (std.mem.eql(u8, context_field, "assignee")) {
                if (ctx.assignee) |a| allocator.free(a);
                ctx.assignee = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "created")) {
                allocator.free(ctx.created);
                ctx.created = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "resolved")) {
                if (ctx.resolved) |r| allocator.free(r);
                ctx.resolved = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "closed")) {
                if (ctx.closed) |c| allocator.free(c);
                ctx.closed = try allocator.dupe(u8, value);
                return true;
            }
        },
        .requirement => |*ctx| {
            if (std.mem.eql(u8, context_field, "status")) {
                // Validate state transition
                const current = ctx.status;
                if (!state_machine.isValidTransitionByType("requirement", current, value)) {
                    const err_msg = state_machine.getTransitionError("requirement", current, value);
                    try HumanOutput.printError(err_msg);
                    return false;
                }

                allocator.free(ctx.status);
                ctx.status = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "verification_method")) {
                allocator.free(ctx.verification_method);
                ctx.verification_method = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "priority")) {
                ctx.priority = std.fmt.parseInt(u8, value, 10) catch {
                    try HumanOutput.printError("Invalid priority '{s}'");
                    return false;
                };
                return true;
            }
            if (std.mem.eql(u8, context_field, "assignee")) {
                if (ctx.assignee) |a| allocator.free(a);
                ctx.assignee = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "effort_points")) {
                ctx.effort_points = std.fmt.parseInt(u16, value, 10) catch {
                    try HumanOutput.printError("Invalid effort_points '{s}'");
                    return false;
                };
                return true;
            }
            if (std.mem.eql(u8, context_field, "sprint")) {
                if (ctx.sprint) |s| allocator.free(s);
                ctx.sprint = try allocator.dupe(u8, value);
                return true;
            }
        },
        .custom => |*ctx| {
            // For custom context, check if key exists
            var key_exists = false;
            var it = ctx.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, entry.key_ptr.*, context_field)) {
                    key_exists = true;
                    // Free old value and replace
                    allocator.free(entry.value_ptr.*);
                    entry.value_ptr.* = try allocator.dupe(u8, value);
                    break;
                }
            }
            if (!key_exists) {
                // Key doesn't exist - insert new
                const key_copy = try allocator.dupe(u8, context_field);
                errdefer allocator.free(key_copy);
                const value_copy = try allocator.dupe(u8, value);
                errdefer allocator.free(value_copy);
                try ctx.put(key_copy, value_copy);
            }
            return true;
        },
        .none => {
            try HumanOutput.printError("Context not initialized for this Neurona");
            return false;
        },
    }

    try HumanOutput.printError("Unknown context field '{s}'");
    return false;
}

/// Update LLM metadata field
fn updateLLMMetadata(allocator: Allocator, neurona: *Neurona, field: []const u8, value: []const u8, verbose: bool) !bool {
    // Initialize metadata if not exists
    if (neurona.llm_metadata == null) {
        neurona.llm_metadata = LLMMetadata{
            .short_title = try allocator.dupe(u8, ""),
            .density = 2,
            .keywords = .{},
            .token_count = 0,
            .strategy = try allocator.dupe(u8, "summary"),
        };
    }

    const meta = if (neurona.llm_metadata) |*m| m else unreachable;

    if (std.mem.eql(u8, field, "short_title")) {
        allocator.free(meta.short_title);
        meta.short_title = try allocator.dupe(u8, value);
        if (verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("  Set _llm.short_title to: {s}\n", .{value});
            try stdout.flush();
        }
        return true;
    } else if (std.mem.eql(u8, field, "density")) {
        meta.density = std.fmt.parseInt(u8, value, 10) catch {
            try HumanOutput.printError("Invalid density '{s}'");
            return false;
        };
        if (verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("  Set _llm.density to: {d}\n", .{meta.density});
            try stdout.flush();
        }
        return true;
    } else if (std.mem.eql(u8, field, "keywords")) {
        // Split comma-separated keywords
        var it = std.mem.splitScalar(u8, value, ',');
        meta.keywords.deinit(allocator);
        meta.keywords = .{};
        while (it.next()) |kw| {
            const trimmed = std.mem.trim(u8, kw, " ");
            if (trimmed.len > 0) {
                try meta.keywords.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
        if (verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("  Set _llm.keywords to: {d} items\n", .{meta.keywords.items.len});
            try stdout.flush();
        }
        return true;
    } else if (std.mem.eql(u8, field, "token_count")) {
        meta.token_count = std.fmt.parseInt(u32, value, 10) catch 0;
        if (verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("  Set _llm.token_count to: {d}\n", .{meta.token_count});
            try stdout.flush();
        }
        return true;
    } else if (std.mem.eql(u8, field, "strategy")) {
        allocator.free(meta.strategy);
        meta.strategy = try allocator.dupe(u8, value);
        if (verbose) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("  Set _llm.strategy to: {s}\n", .{value});
            try stdout.flush();
        }
        return true;
    } else {
        // Unknown field
        return false;
    }
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

// ==================== Tests ====================

test "UpdateConfig creates correctly" {
    const allocator = std.testing.allocator;

    var sets = std.ArrayListUnmanaged(FieldUpdate){};
    defer {
        for (sets.items) |*s| s.deinit(allocator);
        sets.deinit(allocator);
    }

    const update = FieldUpdate{
        .field = try allocator.dupe(u8, "title"),
        .value = try allocator.dupe(u8, "New Title"),
        .operator = .set,
    };
    try sets.append(allocator, update);

    const config = UpdateConfig{
        .id = "test.001",
        .sets = sets,
        .verbose = false,
        .cortex_dir = "neuronas",
    };

    try std.testing.expectEqualStrings("test.001", config.id);
    try std.testing.expectEqual(@as(usize, 1), config.sets.items.len);
}

test "FieldUpdate operator enum values" {
    try std.testing.expectEqual(UpdateOperator.set, UpdateOperator.set);
    try std.testing.expectEqual(UpdateOperator.append, UpdateOperator.append);
    try std.testing.expectEqual(UpdateOperator.remove, UpdateOperator.remove);
}

test "applyUpdate updates title" {
    const allocator = std.testing.allocator;

    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);
    neurona.title = try allocator.dupe(u8, "Old Title");

    var update = FieldUpdate{
        .field = try allocator.dupe(u8, "title"),
        .value = try allocator.dupe(u8, "New Title"),
        .operator = .set,
    };
    defer update.deinit(allocator);

    const result = try applyUpdate(allocator, &neurona, update, false, "test_neuronas");
    try std.testing.expect(result);
    try std.testing.expectEqualStrings("New Title", neurona.title);
}

test "parseNeuronaType parses all types" {
    try std.testing.expectEqual(.concept, try parseNeuronaType("concept"));
    try std.testing.expectEqual(.requirement, try parseNeuronaType("requirement"));
    try std.testing.expectEqual(.test_case, try parseNeuronaType("test_case"));
    try std.testing.expectEqual(.issue, try parseNeuronaType("issue"));
    try std.testing.expectEqual(.artifact, try parseNeuronaType("artifact"));
}

test "getCurrentTimestamp returns valid ISO format" {
    const allocator = std.testing.allocator;

    const ts = try timestamp_mod.getCurrentTimestamp(allocator);
    defer allocator.free(ts);

    try std.testing.expect(ts.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, ts, "T") != null);
    try std.testing.expect(std.mem.endsWith(u8, ts, "Z"));
}
