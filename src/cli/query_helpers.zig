// File: src/cli/query_helpers.zig
// Helper functions for query command - EQL integration
const std = @import(\"std\");
const Allocator = std.mem.Allocator;
const EQLParser = @import(\"../utils/eql_parser.zig\").EQLParser;
const eql_parser = @import(\"../utils/eql_parser.zig\");
const nl_query_parser = @import(\"../utils/nl_query_parser.zig\");

// Re-export query types (import from query.zig)
const query = @import(\"query.zig\");
pub const QueryConfig = query.QueryConfig;
pub const QueryFilter = query.QueryFilter;
pub const TypeFilter = query.TypeFilter;
pub const TagFilter = query.TagFilter;
pub const ConnectionFilter = query.ConnectionFilter;
pub const FieldFilter = query.FieldFilter;

/// Handle query with text (EQL or natural language)
pub fn executeQueryWithText(allocator: Allocator, config: QueryConfig) !void {
    const query_text = config.query_text;

    // Step 1: Determine if it's EQL or natural language
    const is_eql = eql_parser.isEQLQuery(query_text);

    if (is_eql) {
        // Parse as EQL
        var parser = EQLParser.init(allocator, query_text);
        var eql_query = try parser.parse();
        defer eql_query.deinit(allocator);

        // Convert EQL to filters
        const filters = try convertEQLToFilters(allocator, \u0026eql_query);
        defer {
            for (filters) |*f| {
                switch (f.*) {
                    .type_filter => |*tf| tf.deinit(allocator),
                    .tag_filter => |*tf| tf.deinit(allocator),
                    .connection_filter => {},
                    .field_filter => |*ff| allocator.free(ff.field),
                }
            }
            allocator.free(filters);
        };

        const new_config = QueryConfig{
            .mode = .filter,
            .query_text = query_text,
            .filters = filters,
            .limit = config.limit,
            .json_output = config.json_output,
        };

        // Call the filter query function from query module
        const query_module = @import(\"query.zig\");
        return try query_module.executeFilterQuery(allocator, new_config);
    }

    // Fallback: treat as text search
    std.debug.print(\"Query using BM25 text search...\\n\", .{});
    const text_config = QueryConfig{
        .mode = .text,
        .query_text = query_text,
        .filters = config.filters,
        .limit = config.limit,
        .json_output = config.json_output,
    };
    
    const query_module = @import(\"query.zig\");
    return try query_module.executeBM25Query(allocator, text_config);
}

/// Convert EQL query to QueryFilters
fn convertEQLToFilters(allocator: Allocator, eql_query: *const eql_parser.EQLQuery) ![]QueryFilter {
    var filters = std.ArrayList(QueryFilter){};
    defer filters.deinit(allocator);

    for (eql_query.conditions.items) |*cond| {
        // Handle link conditions
        if (cond.link_type != null and cond.link_target != null) {
            const link_filter = ConnectionFilter{
                .connection_type = cond.link_type,
                .target_id = cond.link_target,
                .operator = .@\"and\",
            };
            try filters.append(allocator, .{ .connection_filter = link_filter });
            continue;
        }

        // Handle field conditions
        if (std.mem.eql(u8, cond.field, \"type\")) {
            var type_filter = TypeFilter{
                .types = .{},
                .include = cond.op != .neq,
            };
            const type_val = try allocator.dupe(u8, cond.value);
            try type_filter.types.append(allocator, type_val);
            try filters.append(allocator, .{ .type_filter = type_filter });
        } else if (std.mem.eql(u8, cond.field, \"tag\")) {
            var tag_filter = TagFilter{
                .tags = .{},
                .include = cond.op != .neq,
            };
            const tag_val = try allocator.dupe(u8, cond.value);
            try tag_filter.tags.append(allocator, tag_val);
            try filters.append(allocator, .{ .tag_filter = tag_filter });
        } else {
            // Generic field filter
            const field_op = convertEQLOpToFieldOp(cond.op);
            const field_filter = FieldFilter{
                .field = try allocator.dupe(u8, cond.field),
                .value = cond.value,
                .operator = field_op,
            };
            try filters.append(allocator, .{ .field_filter = field_filter });
        }
    }

    return try filters.toOwnedSlice(allocator);
}

/// Convert EQL operator to FieldOperator
fn convertEQLOpToFieldOp(op: eql_parser.ConditionOp) FieldFilter.FieldOperator {
    return switch (op) {
        .eq => .equal,
        .neq => .not_equal,
        .contains => .contains,
        .not_contains => .not_contains,
        // For now, treat gt/lt/gte/lte as equal (would need numeric comparison)
        .gt, .lt, .gte, .lte => .equal,
    };
}
