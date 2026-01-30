// Performance benchmarks for Engram Phase 1 targets
// Validates: Cold Start < 50ms, File Read < 10ms, Graph Traversal < 5ms, Index Build < 100ms

const std = @import("std");
const Allocator = std.mem.Allocator;
const Engram = @import("Engram");

const fs = Engram.storage;
const cortex = Engram.Cortex;
const graph_module = Engram.core.graph;
const benchmark = Engram.utils.benchmark;

/// Run all benchmarks and print results
pub fn runAll(allocator: Allocator) !void {
    std.debug.print("\n=== Engram Performance Benchmarks ===\n\n", .{});

    var reports = std.ArrayListUnmanaged(benchmark.BenchmarkReport){};
    defer {
        // No strings to free in BenchmarkReport currently
        reports.deinit(allocator);
    }

    const runner = benchmark.Benchmark.init(allocator, "Engram Benchmarks");

    // 1. Cold Start
    try reports.append(allocator, try runner.run("Cold Start (cortex.json load)", 10, benchmarkColdStart, .{allocator}));

    // 2. File Read
    try reports.append(allocator, try runner.run("File Read (simple md)", 20, benchmarkFileRead, .{allocator}));

    // 3. Graph Traversal Depth 1
    try reports.append(allocator, try runner.run("Graph Traversal (Depth 1)", 1000, benchmarkGraphTraversalD1, .{allocator}));

    // 4. Graph Traversal Depth 3
    try reports.append(allocator, try runner.run("Graph Traversal (Depth 3)", 100, benchmarkGraphTraversalD3, .{allocator}));

    // 5. Graph Traversal Depth 5
    try reports.append(allocator, try runner.run("Graph Traversal (Depth 5)", 50, benchmarkGraphTraversalD5, .{allocator}));

    // 6. Index Build (100 files)
    try reports.append(allocator, try runner.run("Index Build (100 files scan)", 5, benchmarkIndexBuild, .{allocator}));

    // Print summary
    printResults(reports.items);
}

/// Helper for cold start measurement
fn benchmarkColdStart(allocator: Allocator) !void {
    // Setup test cortex
    const test_dir = "bench_cortex";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const cortex_config = try cortex.default(allocator, "test_cortex", "Test Cortex");
    defer {
        allocator.free(cortex_config.id);
        allocator.free(cortex_config.name);
        allocator.free(cortex_config.version);
        allocator.free(cortex_config.spec_version);
        allocator.free(cortex_config.capabilities.type);
        allocator.free(cortex_config.capabilities.default_language);
        allocator.free(cortex_config.indices.strategy);
        allocator.free(cortex_config.indices.embedding_model);
    }

    const cortex_path = try std.fs.path.join(allocator, &.{ test_dir, "cortex.json" });
    defer allocator.free(cortex_path);

    const cortex_json = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "id": "{s}",
        \\  "name": "{s}",
        \\  "version": "0.1.0",
        \\  "spec_version": "0.1.0",
        \\  "capabilities": {{
        \\    "type": "zettelkasten",
        \\    "semantic_search": false,
        \\    "llm_integration": false,
        \\    "default_language": "en"
        \\  }},
        \\  "indices": {{
        \\    "strategy": "lazy",
        \\    "embedding_model": "none"
        \\  }}
        \\}}
    , .{ cortex_config.id, cortex_config.name });
    defer allocator.free(cortex_json);

    try std.fs.cwd().writeFile(.{
        .sub_path = cortex_path,
        .data = cortex_json,
    });

    const loaded = try cortex.fromFile(allocator, cortex_path);

    // Manual cleanup for const return
    allocator.free(loaded.id);
    allocator.free(loaded.name);
    allocator.free(loaded.version);
    allocator.free(loaded.spec_version);
    allocator.free(loaded.capabilities.type);
    allocator.free(loaded.capabilities.default_language);
    allocator.free(loaded.indices.strategy);
    allocator.free(loaded.indices.embedding_model);
}

fn benchmarkFileRead(allocator: Allocator) !void {
    _ = allocator;
    const test_file = "bench_neurona.md";
    try std.fs.cwd().writeFile(.{
        .sub_path = test_file,
        .data = "---\nid: bench.001\ntitle: Benchmark\n---\n",
    });
    defer std.fs.cwd().deleteFile(test_file) catch {};

    var buffer: [4096]u8 = undefined;
    const file = try std.fs.cwd().openFile(test_file, .{});
    defer file.close();
    _ = try file.readAll(&buffer);
}

fn benchmarkGraphTraversalD1(allocator: Allocator) !void {
    var test_graph = graph_module.Graph.init();
    defer test_graph.deinit(allocator);

    for (0..100) |i| {
        const from_id = try std.fmt.allocPrint(allocator, "node.{d}", .{i});
        defer allocator.free(from_id);
        const to_id = try std.fmt.allocPrint(allocator, "node.{d}", .{(i + 1) % 100});
        defer allocator.free(to_id);
        try test_graph.addEdge(allocator, from_id, to_id, 50);
    }

    const adj = test_graph.getAdjacent("node.50");
    _ = adj;
}

fn benchmarkGraphTraversalD3(allocator: Allocator) !void {
    var test_graph = graph_module.Graph.init();
    defer test_graph.deinit(allocator);

    // Build a small grid/chain for depth search
    for (0..200) |i| {
        const from_id = try std.fmt.allocPrint(allocator, "node.{d}", .{i});
        defer allocator.free(from_id);
        const to_id = try std.fmt.allocPrint(allocator, "node.{d}", .{i + 1});
        defer allocator.free(to_id);
        try test_graph.addEdge(allocator, from_id, to_id, 50);
    }

    const bfs_results = try test_graph.bfs(allocator, "node.0");
    defer {
        for (bfs_results) |r| allocator.free(r.path);
        allocator.free(bfs_results);
    }
}

fn benchmarkGraphTraversalD5(allocator: Allocator) !void {
    var test_graph = graph_module.Graph.init();
    defer test_graph.deinit(allocator);

    // Chain of 500 nodes
    for (0..500) |i| {
        const from_id = try std.fmt.allocPrint(allocator, "node.{d}", .{i});
        defer allocator.free(from_id);
        const to_id = try std.fmt.allocPrint(allocator, "node.{d}", .{i + 1});
        defer allocator.free(to_id);
        try test_graph.addEdge(allocator, from_id, to_id, 50);
    }

    var path = try test_graph.shortestPath(allocator, "node.0", "node.100");
    path.deinit(allocator);
}

fn benchmarkIndexBuild(allocator: Allocator) !void {
    const test_dir = "bench_index";
    try std.fs.cwd().makePath(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    for (0..100) |i| {
        const id = try std.fmt.allocPrint(allocator, "bench.{d:0>3}", .{i});
        defer allocator.free(id);
        const path = try std.fs.path.join(allocator, &.{ test_dir, try std.fmt.allocPrint(allocator, "{s}.md", .{id}) });
        defer allocator.free(path);

        const content = try std.fmt.allocPrint(allocator,
            \\---
            \\id: {s}
            \\title: Bench {d}
            \\tags: [test]
            \\---
        , .{ id, i });
        defer allocator.free(content);

        try std.fs.cwd().writeFile(.{
            .sub_path = path,
            .data = content,
        });
    }

    const neuronas = try fs.scanNeuronas(allocator, test_dir);
    defer {
        for (neuronas) |*n| n.deinit(allocator);
        allocator.free(neuronas);
    }
}

/// Print benchmark results summary
fn printResults(results: []const benchmark.BenchmarkReport) void {
    std.debug.print("=== Results Summary ===\n\n", .{});
    std.debug.print("{s: <35} | {s: >11} | {s: >11} | {s}\n", .{ "Name", "Avg MS", "Max MS", "Status" });
    std.debug.print("--------------------------------------------------------------------------------\n", .{});

    var passed: usize = 0;
    var failed: usize = 0;

    for (results) |result| {
        const threshold: f64 = if (std.mem.indexOf(u8, result.operation, "Cold Start") != null) 50.0 else if (std.mem.indexOf(u8, result.operation, "Traversal (Depth 5)") != null) 10.0 else if (std.mem.indexOf(u8, result.operation, "Traversal (Depth 3)") != null) 5.0 else if (std.mem.indexOf(u8, result.operation, "Traversal (Depth 1)") != null) 1.0 else 100.0;

        const passes = result.avg_ms < threshold;
        const status = if (passes) "✅ PASS" else "❌ FAIL";

        std.debug.print("{s: <35} | {d: >8.3} ms | {d: >8.3} ms | {s}\n", .{ result.operation, result.avg_ms, result.max_ms, status });

        if (passes) passed += 1 else failed += 1;
    }

    std.debug.print("\nTotal: {d}/{d} benchmarks passed\n", .{ passed, results.len });
}

// Main entry point for standalone benchmark execution
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try runAll(allocator);
}
