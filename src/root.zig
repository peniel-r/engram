//! Legacy root file - re-exports from new library location
//! This file provides backward compatibility during library refactoring

const std = @import("std");

// Re-export from new library location
pub const Neurona = @import("lib/root.zig").Neurona;
pub const NeuronaType = @import("lib/root.zig").NeuronaType;
pub const Connection = @import("lib/root.zig").Connection;
pub const ConnectionType = @import("lib/root.zig").ConnectionType;
pub const Context = @import("lib/root.zig").Context;

pub const core = struct {
    pub const Neurona = @import("lib/root.zig").Neurona;
    pub const NeuronaType = @import("lib/root.zig").NeuronaType;
    pub const Connection = @import("lib/root.zig").Connection;
    pub const ConnectionType = @import("lib/root.zig").ConnectionType;
    pub const ConnectionGroup = @import("lib/core/connections.zig").ConnectionGroup;
    pub const Context = @import("lib/root.zig").Context;
    pub const NeuralActivation = @import("core/activation.zig").NeuralActivation;
    pub const ActivationResult = @import("core/activation.zig").ActivationResult;
};

// Re-export storage modules (from existing location for now)
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

// Re-export core NeuralActivation directly for backward compatibility
pub const NeuralActivation = @import("core/activation.zig").NeuralActivation;

// Re-export utils
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

// Re-export CLI (for integration tests)
pub const cli = struct {
    pub const init = @import("cli/init.zig");
    pub const new = @import("cli/new.zig");
    pub const query = @import("cli/query.zig");
    pub const impact = @import("cli/impact.zig");
    pub const release_status = @import("cli/release_status.zig");
    pub const trace = @import("cli/trace.zig");
};

// Add test to verify backward compatibility
test "legacy root re-exports correctly" {
    const allocator = std.testing.allocator;

    // Test Neurona
    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);
    neurona.title = try allocator.dupe(u8, "Test");

    try std.testing.expectEqualStrings("Test", neurona.title);

    // Test ConnectionType
    const conn_type = ConnectionType.fromString("parent");
    try std.testing.expectEqual(ConnectionType.parent, conn_type.?);
}

// Keep old functions for backward compatibility
pub fn addInt(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(addInt(3, 7) == 10);
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add function works" {
    try std.testing.expect(add(3, 7) == 10);
}
