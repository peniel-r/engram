//! Engram - Neurona Knowledge Protocol Library
//!
//! This library provides the core primitives and logic for the Neurona System,
//! implementing the Neurona Open Specification v0.1.0.
//!
//! ## Usage
//!
//! ```zig
//! const Engram = @import("Engram");
//!
//! // Create a neurona
//! var neurona = try Engram.Neurona.init(allocator);
//! neurona.title = "My Concept";
//! neurona.id = "concept.001";
//! ```
//!
//! ## Core Modules
//!
//! - **types**: Neurona data structures
//! - **connections**: Connection types and logic
//! - **context**: Context extensions for Tier 3
//! - **utils**: String, path, and text processing utilities
//!

const std = @import("std");

// Core types
pub const Neurona = @import("core/types.zig").Neurona;
pub const NeuronaType = @import("core/types.zig").NeuronaType;
pub const LLMMetadata = @import("core/types.zig").LLMMetadata;

// Connections
pub const Connection = @import("core/connections.zig").Connection;
pub const ConnectionType = @import("core/connections.zig").ConnectionType;
pub const ConnectionGroup = @import("core/connections.zig").ConnectionGroup;

// Context
pub const Context = @import("core/context.zig").Context;

// Context-specific types
pub const StateMachineContext = @import("core/context.zig").StateMachineContext;
pub const ArtifactContext = @import("core/context.zig").ArtifactContext;
pub const TestCaseContext = @import("core/context.zig").TestCaseContext;
pub const IssueContext = @import("core/context.zig").IssueContext;
pub const RequirementContext = @import("core/context.zig").RequirementContext;

// Utils
pub const Json = @import("utils/strings.zig").Json;
pub const TextProcessor = @import("utils/text.zig").TextProcessor;
pub const CortexResolver = @import("utils/paths.zig").CortexResolver;

// Storage
pub const Storage = @import("storage/filesystem.zig").Storage;
pub const StorageError = @import("storage/filesystem.zig").StorageError;

// Query
pub const QueryEngine = @import("query/engine.zig").QueryEngine;
pub const QueryMode = @import("query/modes.zig").QueryMode;
pub const QueryResult = @import("query/engine.zig").QueryResult;

// Re-export Allocator for convenience
pub const Allocator = std.mem.Allocator;

test "library root compiles" {
    const allocator = std.testing.allocator;

    // Test that we can create core types
    var neurona = try Neurona.init(allocator);
    defer neurona.deinit(allocator);

    neurona.title = try allocator.dupe(u8, "Test");

    // Test connection type parsing
    const conn_type = ConnectionType.fromString("parent");
    try std.testing.expectEqual(ConnectionType.parent, conn_type.?);

    // Test JSON utilities
    const escaped = try Json.formatEscaped("test\"value", allocator);
    defer allocator.free(escaped);
    try std.testing.expect(escaped.len > 10);
}
