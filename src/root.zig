//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// Re-export core modules
pub const Neurona = @import("core/neurona.zig").Neurona;
pub const NeuronaType = @import("core/neurona.zig").NeuronaType;
pub const Connection = @import("core/neurona.zig").Connection;
pub const ConnectionType = @import("core/neurona.zig").ConnectionType;
pub const Cortex = @import("core/cortex.zig").Cortex;
pub const core = struct {
    pub const graph = @import("core/graph.zig");
    pub const NeuralActivation = @import("core/activation.zig").NeuralActivation;
    pub const ActivationResult = @import("core/activation.zig").ActivationResult;
    pub const state_machine = @import("core/state_machine.zig");
    pub const validator = @import("core/validator.zig");
};

// Re-export storage modules
pub const storage = struct {
    pub const isNeuronaFile = @import("storage/filesystem.zig").isNeuronaFile;
    pub const readNeurona = @import("storage/filesystem.zig").readNeurona;
    pub const writeNeurona = @import("storage/filesystem.zig").writeNeurona;
    pub const scanNeuronas = @import("storage/filesystem.zig").scanNeuronas;
    pub const getLatestModificationTime = @import("storage/filesystem.zig").getLatestModificationTime;
    pub const BM25Index = @import("storage/tfidf.zig").BM25Index;
    pub const VectorIndex = @import("storage/vectors.zig").VectorIndex;
    pub const SearchResult = @import("storage/vectors.zig").SearchResult;
    pub const BM25Result = @import("storage/tfidf.zig").SearchResult;
    pub const GloVeIndex = @import("storage/glove.zig").GloVeIndex;
    pub const NeuralActivation = @import("core/activation.zig").NeuralActivation;
    pub const llm_cache = @import("storage/llm_cache.zig");
    pub const index = @import("storage/index.zig");
};

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
