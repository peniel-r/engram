//! Custom Query Example for Engram Library
//!
//! This example demonstrates advanced query patterns:
//! - Filter by type, tags, and connections
//! - Neural activation-based traversal
//! - Graph-based dependency analysis
//!
//! Run with: zig run examples/custom_query.zig

const std = @import("std");
const Engram = @import("Engram");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Engram Custom Query Example ===\n\n", .{});

    // Create a small knowledge graph for demonstration
    var neuronas = std.ArrayListUnmanaged(Engram.Neurona){};
    defer {
        for (neuronas.items) |*n| n.deinit(allocator);
        neuronas.deinit(allocator);
    }

    // Create concepts with relationships
    const concept_ids = &[_][]const u8{
        "concept.ai",
        "concept.machine-learning",
        "concept.neural-network",
        "concept.deep-learning",
        "concept.transformer",
    };

    const concept_titles = &[_][]const u8{
        "Artificial Intelligence",
        "Machine Learning",
        "Neural Network",
        "Deep Learning",
        "Transformer Model",
    };

    // Create neuronas and link them
    for (concept_ids, concept_titles, 0..) |id, title, i| {
        var neurona = try Engram.Neurona.init(allocator);
        errdefer neurona.deinit(allocator);

        neurona.id = try allocator.dupe(u8, id);
        neurona.title = try allocator.dupe(u8, title);
        neurona.type = .concept;
        neurona.language = try allocator.dupe(u8, "en");

        // Add tags
        try neurona.tags.append(allocator, try allocator.dupe(u8, "ai"));
        try neurona.tags.append(allocator, try allocator.dupe(u8, "concept"));

        // Create hierarchical connections
        if (i > 0) {
            // All concepts connect to AI as parent
            const conn = Engram.Connection{
                .target_id = try allocator.dupe(u8, "concept.ai"),
                .connection_type = .prerequisite,
                .weight = 80,
            };
            try neurona.addConnection(allocator, conn);

            // Neural network connects to ML
            if (i == 2) {
                const conn2 = Engram.Connection{
                    .target_id = try allocator.dupe(u8, "concept.machine-learning"),
                    .connection_type = .related,
                    .weight = 90,
                };
                try neurona.addConnection(allocator, conn2);
            }

            // Deep learning connects to neural network
            if (i == 3) {
                const conn2 = Engram.Connection{
                    .target_id = try allocator.dupe(u8, "concept.neural-network"),
                    .connection_type = .prerequisite,
                    .weight = 95,
                };
                try neurona.addConnection(allocator, conn2);
            }

            // Transformer connects to deep learning
            if (i == 4) {
                const conn2 = Engram.Connection{
                    .target_id = try allocator.dupe(u8, "concept.deep-learning"),
                    .connection_type = .prerequisite,
                    .weight = 90,
                };
                try neurona.addConnection(allocator, conn2);
            }
        }

        try neuronas.append(allocator, neurona);
    }

    std.debug.print("Created {d} neuronas in knowledge graph\n\n", .{neuronas.items.len});

    // Demonstrate filter queries
    std.debug.print("=== Filter Query Examples ===\n\n", .{});

    // Filter by type
    std.debug.print("1. Filter by type (concept):\n", .{});
    for (neuronas.items) |n| {
        if (n.type == .concept) {
            std.debug.print("   - {s}: {s}\n", .{ n.id, n.title });
        }
    }
    std.debug.print("\n", .{});

    // Filter by tag
    std.debug.print("2. Filter by tag (ai):\n", .{});
    for (neuronas.items) |n| {
        for (n.tags.items) |tag| {
            if (std.mem.eql(u8, tag, "ai")) {
                std.debug.print("   - {s}: {s}\n", .{ n.id, n.title });
                break;
            }
        }
    }
    std.debug.print("\n", .{});

    // Filter by connection
    std.debug.print("3. Filter by connection (has 'prerequisite' to concept.ai):\n", .{});
    const ai_conns = neuronas.items[0].getConnections(.prerequisite);
    std.debug.print("   concept.ai has {d} prerequisite connections\n", .{ai_conns.len});

    for (neuronas.items) |n| {
        const prereqs = n.getConnections(.prerequisite);
        for (prereqs) |conn| {
            if (std.mem.eql(u8, conn.target_id, "concept.ai")) {
                std.debug.print("   - {s} -> {s}\n", .{ n.id, conn.target_id });
            }
        }
    }
    std.debug.print("\n", .{});

    // Demonstrate neural activation traversal
    std.debug.print("=== Neural Activation Traversal ===\n\n", .{});

    // Start from transformer and traverse prerequisites
    const seed_id = "concept.transformer";
    std.debug.print("Seed: {s}\n", .{seed_id});
    std.debug.print("Following prerequisite connections (decay = 0.5):\n", .{});

    var visited = std.StringHashMap(f64).init(allocator);
    defer visited.deinit();

    // Simple BFS traversal with decay
    var queue = std.ArrayListUnmanaged(struct { id: []const u8, weight: f64 }){};
    defer queue.deinit(allocator);

    try queue.append(allocator, .{ .id = seed_id, .weight = 1.0 });

    const decay_rate = 0.5;

    while (queue.pop()) |item| {
        // Skip if already visited with higher weight
        const existing = visited.get(item.id);
        if (existing != null and existing.? >= item.weight) {
            continue;
        }
        try visited.put(try allocator.dupe(u8, item.id), item.weight);

        // Find and queue neighbors
        for (neuronas.items) |n| {
            if (std.mem.eql(u8, n.id, item.id)) {
                std.debug.print("   {s} (activation: {d:.2})\n", .{ n.id, item.weight });

                // Get all connection types
                var it = n.connections.iterator();
                while (it.next()) |entry| {
                    for (entry.value_ptr.connections.items) |conn| {
                        const new_weight = item.weight * decay_rate * (@as(f64, @floatFromInt(conn.weight)) / 100.0);
                        try queue.append(allocator, .{ .id = conn.target_id, .weight = new_weight });
                    }
                }
                break;
            }
        }
    }
    std.debug.print("\n", .{});

    // Demonstrate graph analysis
    std.debug.print("=== Graph Analysis ===\n\n", .{});

    // Count connections per neurona
    std.debug.print("Connection counts per neurona:\n", .{});
    for (neuronas.items) |n| {
        var total_conns: usize = 0;
        var it = n.connections.iterator();
        while (it.next()) |entry| {
            total_conns += entry.value_ptr.connections.items.len;
        }
        std.debug.print("   {s}: {d} connections\n", .{ n.id, total_conns });
    }
    std.debug.print("\n", .{});

    // Find most connected neurona
    var max_conns: usize = 0;
    var most_connected: ?[]const u8 = null;

    for (neuronas.items) |n| {
        var total_conns: usize = 0;
        var it = n.connections.iterator();
        while (it.next()) |entry| {
            total_conns += entry.value_ptr.connections.items.len;
        }
        if (total_conns > max_conns) {
            max_conns = total_conns;
            most_connected = n.id;
        }
    }

    if (most_connected) |id| {
        std.debug.print("Most connected: {s} with {d} connections\n", .{ id, max_conns });
    }

    std.debug.print("\n=== Example Complete ===\n", .{});
}
