//! Basic Usage Example for Engram Library
//!
//! This example demonstrates fundamental library operations:
//! - Creating Neuronas
//! - Adding connections
//! - Using text processing utilities
//!
//! Run with: zig run examples/basic_usage.zig

const std = @import("std");
const Engram = @import("Engram");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Engram Basic Usage Example ===\n\n", .{});

    // Create a neurona
    var neurona = try Engram.Neurona.init(allocator);
    defer neurona.deinit(allocator);

    const id = try allocator.dupe(u8, "concept.001");
    allocator.free(neurona.id);
    neurona.id = id;

    const title = try allocator.dupe(u8, "My First Concept");
    allocator.free(neurona.title);
    neurona.title = title;

    neurona.type = .concept;
    neurona.language = try allocator.dupe(u8, "en");

    // Add tags
    try neurona.tags.append(allocator, try allocator.dupe(u8, "example"));
    try neurona.tags.append(allocator, try allocator.dupe(u8, "tutorial"));

    std.debug.print("Created Neurona:\n", .{});
    std.debug.print("  ID: {s}\n", .{neurona.id});
    std.debug.print("  Title: {s}\n", .{neurona.title});
    std.debug.print("  Type: {s}\n", .{@tagName(neurona.type)});
    std.debug.print("  Tags: ", .{});
    for (neurona.tags.items, 0..) |tag, i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("{s}", .{tag});
    }
    std.debug.print("\n\n", .{});

    // Demonstrate connection creation
    const connection = Engram.Connection{
        .target_id = try allocator.dupe(u8, "concept.002"),
        .connection_type = .parent,
        .weight = 90,
    };
    try neurona.addConnection(allocator, connection);

    std.debug.print("Added connection:\n", .{});
    const parent_conns = neurona.getConnections(.parent);
    for (parent_conns) |conn| {
        std.debug.print("  -> {s} (weight: {d})\n", .{ conn.target_id, conn.weight });
    }
    std.debug.print("\n", .{});

    // Demonstrate JSON escaping utility
    const test_string = "Hello \"World\" <test>";
    const escaped = try Engram.Json.formatEscaped(test_string, allocator);
    defer allocator.free(escaped);

    std.debug.print("JSON escaping:\n", .{});
    std.debug.print("  Input:  {s}\n", .{test_string});
    std.debug.print("  Output: {s}\n\n", .{escaped});

    // Demonstrate text processing
    const text = "The Quick Brown Fox Jumps Over The Lazy Dog";
    const words = try Engram.TextProcessor.tokenizeToWords(allocator, text);
    defer {
        for (words) |w| allocator.free(w);
        allocator.free(words);
    }

    std.debug.print("Text tokenization:\n", .{});
    std.debug.print("  Input: \"{s}\"\n", .{text});
    std.debug.print("  Words: {d}\n", .{words.len});
    for (words) |word| {
        std.debug.print("    - {s}\n", .{word});
    }
    std.debug.print("\n", .{});

    // Demonstrate connection type parsing
    std.debug.print("Connection type parsing:\n", .{});
    const conn_types = &[_][]const u8{ "parent", "validates", "blocks", "invalid" };
    for (conn_types) |type_str| {
        const parsed = Engram.ConnectionType.fromString(type_str);
        if (parsed) |ct| {
            std.debug.print("  \"{s}\" -> {s}\n", .{ type_str, @tagName(ct) });
        } else {
            std.debug.print("  \"{s}\" -> INVALID\n", .{type_str});
        }
    }
    std.debug.print("\n", .{});

    std.debug.print("=== Example Complete ===\n", .{});
}
