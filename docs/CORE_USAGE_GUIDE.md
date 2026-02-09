# Neurona Core: Developer Usage Guide

The **Neurona Core Library** is a high-performance implementation of the [Neurona Open Specification](./NEURONA_OPEN_SPEC.md). It allows you to transform static documentation into a dynamic, AI-ready neural knowledge graph.

## 1. Installation

Add Neurona to your `build.zig.zon`:

```zig
.{
    .name = "my_project",
    .version = "0.1.0",
    .dependencies = .{
        .neurona = .{
            .path = "../path/to/engram", // Or git URL
        },
    },
}
```

In your `build.zig`:

```zig
const neurona = b.dependency("neurona", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("neurona", neurona.module("neurona"));
```

## 2. Core Concepts

*   **Neurona**: The atomic unit of knowledge (Markdown + YAML Frontmatter).
*   **Cortex**: A collection of Neuronas (the "Brain").
*   **Soma**: The physical storage (`neuronas/` directory).
*   **Memory**: The system-generated indices (`.activations/` directory).

## 3. Creating Knowledge (Neurona Factory)

The `neurona_factory` handles ID generation, ALM templating, and metadata validation.

```zig
const neurona = @import("neurona");
const factory = neurona.core.neurona_factory;

// Create a Requirement (ALM Type)
const result = try factory.create(allocator, .{
    .type = .requirement,
    .title = "User Authentication",
    .priority = 1,
    .tags = &[_][]const u8{ "security", "v1.0" },
});

// result.id -> "req.user-authentication"
// result.content -> Complete Markdown string with Frontmatter
// result.filepath -> "neuronas/req.user-authentication.md"
```

## 4. Building the Graph (Index Engine)

The `index_engine` pre-computes the relationships and vectors required for sub-10ms search performance.

```zig
const index_engine = neurona.core.index_engine;

const stats = try index_engine.sync(allocator, .{
    .neuronas_dir = "project/neuronas",
    .activations_dir = "project/.activations",
    .force_rebuild = false,
});

std.debug.print("Graph synced: {d} nodes, {d} edges
", .{ 
    stats.graph_nodes, 
    stats.graph_edges 
});
```

## 5. Multi-Mode Search (Query Engine)

The `query_engine` supports five distinct search modes to satisfy different retrieval needs.

### Structured Filter (EQL)
```zig
const query_engine = neurona.core.query_engine;

const results = try query_engine.execute(allocator, .{
    .mode = .filter,
    .neuronas_dir = "project/neuronas",
    .filters = &[_]query_engine.QueryFilter{
        .{ .type_filter = .{ .types = &[_][]const u8{"issue"} } },
        .{ .tag_filter = .{ .tags = &[_][]const u8{"p1"} } },
    },
});
// Access results.neuronas (deep-copied Neurona structs)
```

### Hybrid & Neural Activation
```zig
// Hybrid: Combines BM25 Text Search + Vector Similarity
const hybrid_results = try query_engine.execute(allocator, .{
    .mode = .hybrid,
    .query_text = "database connection leaks",
    .neuronas_dir = "project/neuronas",
    .limit = 5,
});

// Activation: Spreads signal across the graph from a starting point
const graph_results = try query_engine.execute(allocator, .{
    .mode = .activation,
    .query_text = "req.auth.001",
    .neuronas_dir = "project/neuronas",
});
```

## 6. LLM Optimizations

Leverage Engram's token-counting and summarization logic to build efficient RAG (Retrieval-Augmented Generation) pipelines.

```zig
const utils = neurona.utils;

// 1. Precise Token Counting
const tokens = try utils.token_counter.countTokens(allocator, content, null, null);

// 2. Structural Summarization
const summary = try utils.summary.generateSummary(
    allocator,
    full_text,
    "hierarchical", // "full", "summary", or "hierarchical"
    500,            // max_tokens
    null,           // optional cache
    "neurona.id",
    "content_hash",
);
```

## 7. Direct Graph Traversal

If you need to traverse the graph manually (e.g., for custom impact analysis):

```zig
const Graph = neurona.core.Graph;
var graph = Graph.init();
defer graph.deinit(allocator);

// Load the persistent index
try neurona.storage.index.loadGraphInto(allocator, &graph, "project/.activations/graph.idx");

// Traverse neighbors
const neighbors = graph.getAdjacent("req.auth.001");
for (neighbors) |edge| {
    std.debug.print("Connected to {s} (Weight: {d})
", .{ edge.target_id, edge.weight });
}
```
