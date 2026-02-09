//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// Import the new Core Library
const lib = @import("neurona.zig");

// Re-export Core Library Top-Level
pub const Neurona = lib.Neurona;
pub const Cortex = lib.Cortex;

// Re-export Core Modules
pub const NeuronaType = lib.core.NeuronaType;
pub const Connection = lib.core.Connection;
pub const ConnectionType = lib.core.ConnectionType;

pub const core = lib.core;

// Re-export storage modules
pub const storage = struct {
    pub const isNeuronaFile = lib.storage.filesystem.isNeuronaFile;
    pub const readNeurona = lib.storage.filesystem.readNeurona;
    pub const writeNeurona = lib.storage.filesystem.writeNeurona;
    pub const scanNeuronas = lib.storage.filesystem.scanNeuronas;
    pub const getLatestModificationTime = lib.storage.filesystem.getLatestModificationTime;
    pub const BM25Index = lib.storage.BM25Index;
    pub const VectorIndex = lib.storage.VectorIndex;
    pub const SearchResult = lib.storage.SearchResult;
    pub const BM25Result = lib.storage.BM25Result;
    pub const GloVeIndex = lib.storage.GloVeIndex;
    pub const NeuralActivation = lib.core.NeuralActivation;
    pub const llm_cache = lib.storage.llm_cache;
    pub const index = lib.storage.index;
};

// Re-export utils
pub const frontmatter = lib.utils.frontmatter.Frontmatter;
pub const yaml = lib.utils.yaml.Parser;
pub const utils = struct {
    pub const timestamp = lib.utils.timestamp;
    pub const state_filters = lib.utils.state_filters;
    pub const token_counter = lib.utils.token_counter;
    pub const summary = lib.utils.summary;
    pub const benchmark = @import("benchmark.zig"); // Benchmark is not in lib
    pub const HelpGenerator = @import("utils/help_generator.zig").HelpGenerator; // CLI specific
    pub const FileOps = lib.utils.file_ops.FileOps;
    pub const NeuronaWithBody = lib.utils.file_ops.NeuronaWithBody;
    pub const ErrorReporter = @import("utils/error_reporter.zig").ErrorReporter; // CLI specific
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

pub fn bufferedPrint() !void {
    // Stdout is for actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn addInt(a: i32, b: i32) i32 {
    return a + b;
}

test "root module basic functionality" {
    try std.testing.expect(addInt(3, 7) == 10);
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
