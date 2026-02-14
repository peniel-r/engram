//! Query mode types and configurations for library use
//! Provides clean interface for different search strategies

const std = @import("std");

/// Query mode for different search algorithms
pub const QueryMode = enum {
    /// Filter by type, tags, connections (default)
    filter,

    /// BM25 full-text search
    text,

    /// Vector similarity search
    vector,

    /// Combined BM25 + vector with fusion
    hybrid,

    /// Neural propagation across graph
    activation,

    /// Convert QueryMode to string
    pub fn toString(self: QueryMode) []const u8 {
        return switch (self) {
            .filter => "filter",
            .text => "text",
            .vector => "vector",
            .hybrid => "hybrid",
            .activation => "activation",
        };
    }

    /// Parse string to QueryMode
    pub fn fromString(s: []const u8) ?QueryMode {
        if (std.mem.eql(u8, s, "filter")) return .filter;
        if (std.mem.eql(u8, s, "text")) return .text;
        if (std.mem.eql(u8, s, "vector")) return .vector;
        if (std.mem.eql(u8, s, "hybrid")) return .hybrid;
        if (std.mem.eql(u8, s, "activation")) return .activation;
        return null;
    }
};
