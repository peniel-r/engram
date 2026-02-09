//! Neurona System Core Library
//! Implements the Neurona Open Specification v0.1.0
//!
//! This library provides the core primitives and logic for the Neurona system,
//! decoupled from any CLI or specific application logic.

const std = @import("std");

// Core Modules (Entities & Logic)
pub const core = struct {
    pub const Neurona = @import("core/neurona.zig").Neurona;
    pub const NeuronaType = @import("core/neurona.zig").NeuronaType;
    pub const Connection = @import("core/neurona.zig").Connection;
    pub const ConnectionType = @import("core/neurona.zig").ConnectionType;
    pub const ConnectionGroup = @import("core/neurona.zig").ConnectionGroup;
    pub const Context = @import("core/neurona.zig").Context;
    pub const Cortex = @import("core/cortex.zig").Cortex;
    pub const graph = @import("core/graph.zig");
    pub const Graph = graph.Graph; // Convenience alias
    pub const NeuralActivation = @import("core/activation.zig").NeuralActivation;
    pub const ActivationResult = @import("core/activation.zig").ActivationResult;
    pub const state_machine = @import("core/state_machine.zig");
    pub const validator = @import("core/validator.zig");
    pub const query_engine = @import("core/query_engine.zig");
    pub const index_engine = @import("core/index_engine.zig");
    pub const neurona_factory = @import("core/neurona_factory.zig");
};

// Storage Modules (Persistence & Indexing)
pub const storage = struct {
    pub const filesystem = @import("storage/filesystem.zig");
    pub const BM25Index = @import("storage/tfidf.zig").BM25Index;
    pub const VectorIndex = @import("storage/vectors.zig").VectorIndex;
    pub const SearchResult = @import("storage/vectors.zig").SearchResult;
    pub const GloVeIndex = @import("storage/glove.zig").GloVeIndex;
    pub const llm_cache = @import("storage/llm_cache.zig");
    pub const index = @import("storage/index.zig");
};

// Utility Modules (Helpers)
pub const utils = struct {
    pub const frontmatter = @import("utils/frontmatter.zig");
    pub const yaml = @import("utils/yaml.zig");
    pub const timestamp = @import("utils/timestamp.zig");
    pub const state_filters = @import("utils/state_filters.zig");
    pub const token_counter = @import("utils/token_counter.zig");
    pub const summary = @import("utils/summary.zig");
    pub const file_ops = @import("utils/file_ops.zig");
};

// Top-level exports for convenience
pub const Neurona = core.Neurona;
pub const Cortex = core.Cortex;

test {
    std.testing.refAllDecls(@This());
}
