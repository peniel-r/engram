//! Engram Library Entry Point
//!
//! This is the main entry point for the Engram library. It re-exports
//! all public types and utilities from the library modules.
//!
//! For CLI usage, see src/main.zig

const std = @import("std");

// Re-export core types from library
pub const Neurona = @import("lib/root.zig").Neurona;
pub const NeuronaType = @import("lib/root.zig").NeuronaType;
pub const Connection = @import("lib/root.zig").Connection;
pub const ConnectionType = @import("lib/root.zig").ConnectionType;
pub const ConnectionGroup = @import("lib/root.zig").ConnectionGroup;
pub const Context = @import("lib/root.zig").Context;

// Context-specific types
pub const StateMachineContext = @import("lib/root.zig").StateMachineContext;
pub const ArtifactContext = @import("lib/root.zig").ArtifactContext;
pub const TestCaseContext = @import("lib/root.zig").TestCaseContext;
pub const IssueContext = @import("lib/root.zig").IssueContext;
pub const RequirementContext = @import("lib/root.zig").RequirementContext;

// Library utilities
pub const Json = @import("lib/root.zig").Json;
pub const TextProcessor = @import("lib/root.zig").TextProcessor;
pub const CortexResolver = @import("lib/root.zig").CortexResolver;

// Re-export storage modules (legacy location - still used by CLI)
pub const storage = struct {
    pub const isNeuronaFile = @import("storage/filesystem.zig").isNeuronaFile;
    pub const readNeurona = @import("storage/filesystem.zig").readNeurona;
    pub const writeNeurona = @import("storage/filesystem.zig").writeNeurona;
    pub const scanNeuronas = @import("storage/filesystem.zig").scanNeuronas;
    pub const getLatestModificationTime = @import("storage/filesystem.zig").getLatestModificationTime;
    pub const BM25Index = @import("storage/tfidf.zig").BM25Index;
    pub const VectorIndex = @import("storage/vectors.zig").VectorIndex;
    pub const SearchResult = @import("storage/vectors.zig").SearchResult;
    pub const BM25Result = @import("storage/tfidf.zig").BM25Result;
    pub const GloVeIndex = @import("storage/glove.zig").GloVeIndex;
    pub const NeuralActivation = @import("core/activation.zig").NeuralActivation;
    pub const llm_cache = @import("storage/llm_cache.zig");
    pub const index = @import("storage/index.zig");
};

// Re-export core modules
pub const core = struct {
    pub const Neurona = @import("lib/root.zig").Neurona;
    pub const NeuronaType = @import("lib/root.zig").NeuronaType;
    pub const Connection = @import("lib/root.zig").Connection;
    pub const ConnectionType = @import("lib/root.zig").ConnectionType;
    pub const ConnectionGroup = @import("lib/root.zig").ConnectionGroup;
    pub const Context = @import("lib/root.zig").Context;
    pub const NeuralActivation = @import("core/activation.zig").NeuralActivation;
    pub const ActivationResult = @import("core/activation.zig").ActivationResult;
};

// Re-export utilities
pub const frontmatter = @import("utils/frontmatter.zig").Frontmatter;
pub const yaml = @import("utils/yaml.zig").Parser;
pub const utils = struct {
    pub const timestamp = @import("utils/timestamp.zig");
    pub const state_filters = @import("utils/state_filters.zig");
    pub const token_counter = @import("utils/token_counter.zig");
    pub const summary = @import("utils/summary.zig");
    pub const benchmark = @import("benchmark.zig");
    pub const HelpGenerator = @import("utils/help_generator.zig").HelpGenerator;
    pub const FileOps = @import("utils/file_ops.zig").FileOps;
    pub const NeuronaWithBody = @import("utils/file_ops.zig").NeuronaWithBody;
    pub const ErrorReporter = @import("utils/error_reporter.zig").ErrorReporter;
    pub const Json = @import("lib/utils/strings.zig").Json;
};

// Direct re-export for backward compatibility
pub const NeuralActivation = @import("core/activation.zig").NeuralActivation;
