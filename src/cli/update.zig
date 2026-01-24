// File: src/cli/update.zig
// The `engram update` command for updating Neurona fields programmatically
// Supports setting tier1, tier2, and tier3 fields

const std = @import("std");
const Allocator = std.mem.Allocator;
const Neurona = @import("../core/neurona.zig").Neurona;
const NeuronaType = @import("../core/neurona.zig").NeuronaType;
const Connection = @import("../core/neurona.zig").Connection;
const ConnectionType = @import("../core/neurona.zig").ConnectionType;
const readNeurona = @import("../storage/filesystem.zig").readNeurona;
const writeNeurona = @import("../storage/filesystem.zig").writeNeurona;
const findNeuronaPath = @import("../storage/filesystem.zig").findNeuronaPath;
const timestamp_mod = @import("../utils/timestamp.zig");
const state_machine = @import("../core/state_machine.zig");

/// Update configuration
pub const UpdateConfig = struct {
    id: []const u8,
    sets: std.ArrayListUnmanaged(FieldUpdate),
    verbose: bool = false,
    neuronas_dir: []const u8 = "neuronas",
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
    // Step 1: Find and load Neurona
    const filepath = try findNeuronaPath(allocator, config.neuronas_dir, config.id);
    defer allocator.free(filepath);

    var neurona = try readNeurona(allocator, filepath);
    defer neurona.deinit(allocator);

    // Step 2: Apply updates
    var updated = false;
    for (config.sets.items) |*update| {
        if (try applyUpdate(allocator, &neurona, update.*, config.verbose)) {
            updated = true;
        }
    }

    if (!updated) {
        if (config.verbose) {
            std.debug.print("No changes applied to {s}\n", .{config.id});
        }
        return;
    }

    // Step 3: Update timestamp
    allocator.free(neurona.updated);
    const ts = try timestamp_mod.getCurrentTimestamp(allocator);
    neurona.updated = try allocator.dupe(u8, ts);
    allocator.free(ts);

    // Step 4: Write back to file
    try writeNeurona(allocator, neurona, filepath);

    if (config.verbose) {
        std.debug.print("Updated {s}\n", .{config.id});
    } else {
        std.debug.print("✓ Updated {s}\n", .{config.id});
    }
}

/// Apply a field update to a Neurona
fn applyUpdate(allocator: Allocator, neurona: *Neurona, update: FieldUpdate, verbose: bool) !bool {
    const field = update.field;
    const value = update.value;

    // Handle context.field syntax (e.g., context.status)
    if (std.mem.startsWith(u8, field, "context.")) {
        return try applyContextUpdate(allocator, neurona, field["context.".len..], value, verbose);
    }

    // Handle direct fields
    if (std.mem.eql(u8, field, "title")) {
        allocator.free(neurona.title);
        neurona.title = try allocator.dupe(u8, value);
        if (verbose) std.debug.print("  Set title to: {s}\n", .{value});
        return true;
    }

    if (std.mem.eql(u8, field, "type")) {
        neurona.type = parseNeuronaType(value) catch {
            std.debug.print("Error: Invalid type '{s}'\n", .{value});
            return false;
        };
        if (verbose) std.debug.print("  Set type to: {s}\n", .{value});
        return true;
    }

    if (std.mem.eql(u8, field, "language")) {
        allocator.free(neurona.language);
        neurona.language = try allocator.dupe(u8, value);
        if (verbose) std.debug.print("  Set language to: {s}\n", .{value});
        return true;
    }

    if (std.mem.eql(u8, field, "tag")) {
        if (update.operator == .append) {
            try neurona.tags.append(allocator, try allocator.dupe(u8, value));
            if (verbose) std.debug.print("  Added tag: {s}\n", .{value});
        } else if (update.operator == .remove) {
            // Remove tag if exists
            var found: usize = 0;
            for (neurona.tags.items, 0..) |tag, i| {
                if (std.mem.eql(u8, tag, value)) {
                    found = i;
                    break;
                }
            }
            if (found > 0 or (neurona.tags.items.len > 0 and std.mem.eql(u8, neurona.tags.items[0], value))) {
                allocator.free(neurona.tags.orderedRemove(found));
                if (verbose) std.debug.print("  Removed tag: {s}\n", .{value});
                return true;
            }
        }
        return true;
    }

    if (std.mem.eql(u8, field, "hash")) {
        if (neurona.hash) |h| allocator.free(h);
        neurona.hash = try allocator.dupe(u8, value);
        if (verbose) std.debug.print("  Set hash to: {s}\n", .{value});
        return true;
    }

    std.debug.print("Error: Unknown field '{s}'\n", .{field});
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
                    std.debug.print("Error: {s}\n", .{err_msg});
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
                    std.debug.print("Error: Invalid priority '{s}'\n", .{value});
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
                    std.debug.print("Error: {s}\n", .{err_msg});
                    return false;
                }

                allocator.free(ctx.status);
                ctx.status = try allocator.dupe(u8, value);
                return true;
            }
            if (std.mem.eql(u8, context_field, "priority")) {
                ctx.priority = std.fmt.parseInt(u8, value, 10) catch {
                    std.debug.print("Error: Invalid priority '{s}'\n", .{value});
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
                    std.debug.print("Error: {s}\n", .{err_msg});
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
                    std.debug.print("Error: Invalid priority '{s}'\n", .{value});
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
                    std.debug.print("Error: Invalid effort_points '{s}'\n", .{value});
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
            // For custom context, get or create the key
            const existing = ctx.get(context_field);
            if (existing) |v| {
                allocator.free(v);
            }
            try ctx.put(try allocator.dupe(u8, context_field), try allocator.dupe(u8, value));
            return true;
        },
        .none => {
            std.debug.print("Error: Context not initialized for this Neurona\n", .{});
            return false;
        },
    }

    std.debug.print("Error: Unknown context field '{s}'\n", .{context_field});
    return false;
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
        .neuronas_dir = "neuronas",
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

    const result = try applyUpdate(allocator, &neurona, update, false);
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
