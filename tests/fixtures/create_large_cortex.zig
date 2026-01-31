// Script to create a test cortex with 10,000 sample Neuronas
// Used for performance validation (Action Item 2.3)

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cortex_dir = "tests/fixtures/large_cortex";

    std.debug.print("Creating large test cortex at {s}...\n", .{cortex_dir});

    // Create cortex.json
    try createCortexJson(allocator, cortex_dir);
    std.debug.print("✓ Created cortex.json\n", .{});

    // Create 10,000 Neurona files
    const num_neuronas: usize = 10000;
    std.debug.print("Creating {d} Neurona files...\n", .{num_neuronas});

    for (0..num_neuronas) |i| {
        const id = try std.fmt.allocPrint(allocator, "bench.{d:0>5}", .{i});
        const title = try std.fmt.allocPrint(allocator, "Benchmark Neurona {d}", .{i});
        const path = try std.fs.path.join(allocator, &.{ cortex_dir, try std.fmt.allocPrint(allocator, "{s}.md", .{id}) });

        const content = try createNeuronaContent(allocator, id, title, i);
        try std.fs.cwd().writeFile(.{ .sub_path = path, .data = content });

        if (i % 1000 == 0 and i > 0) {
            std.debug.print("  Created {d}/{d} files...\n", .{ i, num_neuronas });
        }
    }

    std.debug.print("✓ Created {d} Neurona files\n", .{num_neuronas});
    std.debug.print("Done!\n", .{});
}

fn createCortexJson(allocator: Allocator, cortex_dir: []const u8) !void {
    const cortex_json =
        \\{
        \\  "id": "large_cortex",
        \\  "name": "Large Test Cortex (10K files)",
        \\  "version": "0.1.0",
        \\  "spec_version": "0.1.0",
        \\  "capabilities": {
        \\    "type": "zettelkasten",
        \\    "semantic_search": false,
        \\    "llm_integration": false,
        \\    "default_language": "en"
        \\  },
        \\  "indices": {
        \\    "strategy": "lazy",
        \\    "embedding_model": "none"
        \\  }
        \\}
    ;

    const path = try std.fs.path.join(allocator, &.{ cortex_dir, "cortex.json" });
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = cortex_json });
}

fn createNeuronaContent(allocator: Allocator, id: []const u8, title: []const u8, index: usize) ![]const u8 {
    // Create tags based on index to simulate realistic distribution
    const tag1 = if (index % 3 == 0) "requirement" else if (index % 3 == 1) "test" else "issue";
    const tag2 = if (index % 5 == 0) "auth" else if (index % 5 == 1) "ui" else if (index % 5 == 2) "backend" else if (index % 5 == 3) "api" else "data";

    // Create some connections to other neuronas
    const conn1 = if (index > 0) try std.fmt.allocPrint(allocator, "- bench.{d:0>5}\n", .{index - 1}) else "";
    const conn2 = if (index < 9999) try std.fmt.allocPrint(allocator, "- bench.{d:0>5}\n", .{index + 1}) else "";

    return try std.fmt.allocPrint(allocator,
        \\---
        \\id: {s}
        \\title: {s}
        \\tags: [{s}, {s}]
        \\connections:
        \\  relates_to:
        \\{s}{s}---
        \\
        \\# {s}
        \\
        \\This is benchmark neurona {d}.
        \\
        \\## Description
        \\
        \\This neurona is part of a performance test dataset with 10,000 neuronas.
        \\
        \\## Metadata
        \\
        \\- Index: {d}
        \\- Type: {s}
        \\- Category: {s}
    , .{ id, title, tag1, tag2, conn1, conn2, title, index, index, tag1, tag2 });
}
