// File: src/cli/link.zig
// The `engram link` command for creating connections between Neuronas

const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = @import("../storage/filesystem.zig");
const neurona_core = @import("../core/neurona.zig");
const ConnectionType = neurona_core.ConnectionType;
const Connection = neurona_core.Connection;
const timestamp = @import("../utils/timestamp.zig");
const uri_parser = @import("../utils/uri_parser.zig");
const ErrorReporter = @import("../utils/error_reporter.zig").ErrorReporter;

/// Configuration for Link command
pub const LinkConfig = struct {
    source_id: []const u8,
    target_id: []const u8,
    connection_type: []const u8,
    weight: u8 = 50,
    bidirectional: bool = false,
    verbose: bool = false,
    cortex_dir: ?[]const u8 = null,
};

/// Execute the link command
pub fn execute(allocator: Allocator, config: LinkConfig) !void {
    // Determine neuronas directory
    const cortex_dir = uri_parser.findCortexDir(allocator, config.cortex_dir) catch |err| {
        if (err == error.CortexNotFound) {
            ErrorReporter.cortexNotFound();
            std.process.exit(1);
        }
        return err;
    };
    defer allocator.free(cortex_dir);

    const neuronas_dir = try std.fmt.allocPrint(allocator, "{s}/neuronas", .{cortex_dir});
    defer allocator.free(neuronas_dir);

    // 1. Validate connection type
    const conn_type = ConnectionType.fromString(config.connection_type) orelse {
        ErrorReporter.invalidConnectionType(config.connection_type);
        return error.InvalidConnectionType;
    };

    // Resolve source URI or use direct ID
    const source_id = try uri_parser.resolveOrFallback(allocator, config.source_id, neuronas_dir);
    defer allocator.free(source_id);

    // Resolve target URI or use direct ID
    const target_id = try uri_parser.resolveOrFallback(allocator, config.target_id, neuronas_dir);
    defer allocator.free(target_id);

    // 2. Find source Neurona
    const source_path = fs.findNeuronaPath(allocator, neuronas_dir, source_id) catch |err| {
        if (err == error.NeuronaNotFound) {
            std.debug.print("Error: Source Neurona '{s}' not found in {s}.\n", .{ source_id, neuronas_dir });
        }
        return err;
    };
    defer allocator.free(source_path);

    // 3. Find target Neurona
    const target_path = fs.findNeuronaPath(allocator, neuronas_dir, target_id) catch |err| {
        if (err == error.NeuronaNotFound) {
            std.debug.print("Error: Target Neurona '{s}' not found in {s}.\n", .{ target_id, neuronas_dir });
        }
        return err;
    };
    defer allocator.free(target_path);

    // 4. Update source
    {
        var source = try fs.readNeurona(allocator, source_path);
        defer source.deinit(allocator);

        const conn = Connection{
            .target_id = try allocator.dupe(u8, target_id),
            .connection_type = conn_type,
            .weight = config.weight,
        };
        try source.addConnection(allocator, conn);

        // Update timestamp
        allocator.free(source.updated);
        source.updated = try timestamp.nowDate(allocator);

        try fs.writeNeurona(allocator, source, source_path, false);

        if (config.verbose) {
            std.debug.print("Linked {s} --[{s}]--> {s}\n", .{ source_id, config.connection_type, target_id });
        }
    }

    // 5. Handle bidirectional link
    if (config.bidirectional) {
        const reverse_type = getReverseType(conn_type) orelse {
            if (config.verbose) {
                std.debug.print("Warning: No reverse type defined for '{s}', skipping reverse link.\n", .{config.connection_type});
            }
            return;
        };

        var target = try fs.readNeurona(allocator, target_path);
        defer target.deinit(allocator);

        const conn = Connection{
            .target_id = try allocator.dupe(u8, source_id),
            .connection_type = reverse_type,
            .weight = config.weight,
        };
        try target.addConnection(allocator, conn);

        // Update timestamp
        allocator.free(target.updated);
        target.updated = try timestamp.nowDate(allocator);

        try fs.writeNeurona(allocator, target, target_path, false);

        if (config.verbose) {
            std.debug.print("Linked {s} --[{s}]--> {s}\n", .{ target_id, @tagName(reverse_type), source_id });
        }
    }
}

/// Get the semantic inverse of a connection type
fn getReverseType(ctype: ConnectionType) ?ConnectionType {
    return switch (ctype) {
        .parent => .child,
        .child => .parent,
        .validates => .validated_by,
        .validated_by => .validates,
        .blocks => .blocked_by,
        .blocked_by => .blocks,
        .implements => .implemented_by,
        .implemented_by => .implements,
        .tests => .tested_by,
        .tested_by => .tests,
        .prerequisite => .next,
        .next => .prerequisite,
        .related => .related,
        .relates_to => .relates_to,
        .opposes => .opposes,
    };
}

test "getReverseType returns correct inverses" {
    try std.testing.expectEqual(ConnectionType.child, getReverseType(.parent).?);
    try std.testing.expectEqual(ConnectionType.parent, getReverseType(.child).?);
    try std.testing.expectEqual(ConnectionType.validated_by, getReverseType(.validates).?);
    try std.testing.expectEqual(ConnectionType.related, getReverseType(.related).?);
}

test "execute links two neuronas" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_neuronas_link";
    const neuronas_subdir = try std.fs.path.join(allocator, &.{ test_dir, "neuronas" });
    defer allocator.free(neuronas_subdir);
    try std.fs.cwd().makePath(neuronas_subdir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create cortex.json
    const cortex_json_path = try std.fs.path.join(allocator, &.{ test_dir, "cortex.json" });
    defer allocator.free(cortex_json_path);
    try std.fs.cwd().writeFile(.{
        .sub_path = cortex_json_path,
        .data = "{\"name\":\"test\",\"type\":\"alm\"}",
    });

    // Create source neurona
    const source_path = try std.fs.path.join(allocator, &.{ neuronas_subdir, "source.md" });
    defer allocator.free(source_path);
    try std.fs.cwd().writeFile(.{ .sub_path = source_path, .data = 
        \\---
        \\id: source
        \\title: Source
        \\tags: []
        \\---
    });

    // Create target neurona
    const target_path = try std.fs.path.join(allocator, &.{ neuronas_subdir, "target.md" });
    defer allocator.free(target_path);
    try std.fs.cwd().writeFile(.{ .sub_path = target_path, .data = 
        \\---
        \\id: target
        \\title: Target
        \\tags: []
        \\---
    });

    // Execute link
    const config = LinkConfig{
        .source_id = "source",
        .target_id = "target",
        .connection_type = "parent",
        .cortex_dir = test_dir,
    };

    try execute(allocator, config);

    // Verify source has connection
    var source = try fs.readNeurona(allocator, source_path);
    defer source.deinit(allocator);

    const conns = source.getConnections(.parent);
    try std.testing.expectEqual(@as(usize, 1), conns.len);
    try std.testing.expectEqualStrings("target", conns[0].target_id);
}

test "execute bidirectional link" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_neuronas_link_bi";
    const neuronas_subdir = try std.fs.path.join(allocator, &.{ test_dir, "neuronas" });
    defer allocator.free(neuronas_subdir);
    try std.fs.cwd().makePath(neuronas_subdir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create cortex.json
    const cortex_json_path = try std.fs.path.join(allocator, &.{ test_dir, "cortex.json" });
    defer allocator.free(cortex_json_path);
    try std.fs.cwd().writeFile(.{
        .sub_path = cortex_json_path,
        .data = "{\"name\":\"test\",\"type\":\"alm\"}",
    });

    // Create source neurona
    const source_path = try std.fs.path.join(allocator, &.{ neuronas_subdir, "source.md" });
    defer allocator.free(source_path);
    try std.fs.cwd().writeFile(.{ .sub_path = source_path, .data = 
        \\---
        \\id: source
        \\title: Source
        \\tags: []
        \\---
    });

    // Create target neurona
    const target_path = try std.fs.path.join(allocator, &.{ neuronas_subdir, "target.md" });
    defer allocator.free(target_path);
    try std.fs.cwd().writeFile(.{ .sub_path = target_path, .data = 
        \\---
        \\id: target
        \\title: Target
        \\tags: []
        \\---
    });

    // Execute link
    const config = LinkConfig{
        .source_id = "source",
        .target_id = "target",
        .connection_type = "parent",
        .bidirectional = true,
        .cortex_dir = test_dir,
    };

    try execute(allocator, config);

    // Verify source has connection
    var source = try fs.readNeurona(allocator, source_path);
    defer source.deinit(allocator);
    const s_conns = source.getConnections(.parent);
    try std.testing.expectEqual(@as(usize, 1), s_conns.len);
    try std.testing.expectEqualStrings("target", s_conns[0].target_id);

    // Verify target has reverse connection
    var target = try fs.readNeurona(allocator, target_path);
    defer target.deinit(allocator);
    const t_conns = target.getConnections(.child);
    try std.testing.expectEqual(@as(usize, 1), t_conns.len);
    try std.testing.expectEqualStrings("source", t_conns[0].target_id);
}

test "execute resolves URIs for source and target" {
    const allocator = std.testing.allocator;

    // Setup test directory
    const test_dir = "test_uri_link";
    const neuronas_subdir = try std.fs.path.join(allocator, &.{ test_dir, "neuronas" });
    defer allocator.free(neuronas_subdir);
    try std.fs.cwd().makePath(neuronas_subdir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create cortex.json
    const cortex_json_path = try std.fs.path.join(allocator, &.{ test_dir, "cortex.json" });
    defer allocator.free(cortex_json_path);
    try std.fs.cwd().writeFile(.{
        .sub_path = cortex_json_path,
        .data = "{\"name\":\"test\",\"type\":\"alm\"}",
    });

    // Create source neurona
    const source_path = try std.fs.path.join(allocator, &.{ neuronas_subdir, "source.md" });
    defer allocator.free(source_path);
    try std.fs.cwd().writeFile(.{ .sub_path = source_path, .data = 
        \\---
        \\id: source
        \\title: Source
        \\tags: []
        \\---
    });

    // Create target neurona
    const target_path = try std.fs.path.join(allocator, &.{ neuronas_subdir, "target.md" });
    defer allocator.free(target_path);
    try std.fs.cwd().writeFile(.{ .sub_path = target_path, .data = 
        \\---
        \\id: target
        \\title: Target
        \\tags: []
        \\---
    });

    // Test with direct IDs (not URIs, should fallback)
    const config = LinkConfig{
        .source_id = "source",
        .target_id = "target",
        .connection_type = "parent",
        .cortex_dir = test_dir,
    };

    try execute(allocator, config);

    // Verify link created
    var source = try fs.readNeurona(allocator, source_path);
    defer source.deinit(allocator);
    const conns = source.getConnections(.parent);
    try std.testing.expectEqual(@as(usize, 1), conns.len);
}
