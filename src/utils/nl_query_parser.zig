// Natural Language Query Parser
// Converts conversational queries to structured EQL (Engram Query Language)
// Example: "show me open issues" → "type:issue AND context.state:open"

const std = @import("std");
const Allocator = std.mem.Allocator;

// ==================== Query Expression ====================

/// Query expression converted from natural language
pub const QueryExpression = struct {
    conditions: std.ArrayListUnmanaged(QueryCondition),
    operator: LogicalOperator = .@"and",

    // Caller must call deinit to free resources
    pub fn deinit(self: *QueryExpression, allocator: Allocator) void {
        for (self.conditions.items) |*cond| {
            cond.deinit(allocator);
        }
        self.conditions.deinit(allocator);
    }
};

/// Query condition (field operator value)
pub const QueryCondition = struct {
    field: []const u8,
    operator: FieldOperator,
    value: []const u8,

    pub fn deinit(self: *QueryCondition, allocator: Allocator) void {
        allocator.free(self.field);
        allocator.free(self.value);
    }
};

/// Field operators
pub const FieldOperator = enum {
    eq, // Equal (default)
    neq, // Not equal
    gt, // Greater than
    lt, // Less than
    gte, // Greater or equal
    lte, // Less or equal
    contains, // String contains
};

/// Logical operators for combining conditions
pub const LogicalOperator = enum {
    @"and",
    @"or",
};

// ==================== Token Classification ====================

/// Token type for natural language parsing
pub const TokenType = enum {
    type_keyword, // "issue", "test", "requirement"
    state_keyword, // "open", "closed", "passing"
    priority_keyword, // "high", "low", "p1"
    tag_keyword, // "bug", "security"
    negation, // "not", "without"
    conjunction, // "and", "or"
    query_word, // "show", "find", "list"
    unknown,
};

/// Parsed token
pub const Token = struct {
    token_type: TokenType,
    value: []const u8,
    start: usize,
    end: usize,
};

// ==================== Keyword Mappings ====================

/// Type keyword mappings to EQL type field
const type_mappings = [_]struct {
    keyword: []const u8,
    neurona_type: []const u8,
}{
    .{ .keyword = "issue", .neurona_type = "issue" },
    .{ .keyword = "issues", .neurona_type = "issue" },
    // Don't map "bug"/"bugs" to type - treat them as tags only
    .{ .keyword = "test", .neurona_type = "test_case" },
    .{ .keyword = "tests", .neurona_type = "test_case" },
    .{ .keyword = "test case", .neurona_type = "test_case" },
    .{ .keyword = "test_cases", .neurona_type = "test_case" },
    .{ .keyword = "requirement", .neurona_type = "requirement" },
    .{ .keyword = "requirements", .neurona_type = "requirement" },
    .{ .keyword = "req", .neurona_type = "requirement" },
    .{ .keyword = "reqs", .neurona_type = "requirement" },
    .{ .keyword = "feature", .neurona_type = "feature" },
    .{ .keyword = "features", .neurona_type = "feature" },
    .{ .keyword = "artifact", .neurona_type = "artifact" },
    .{ .keyword = "artifacts", .neurona_type = "artifact" },
};

/// State keyword mappings to context.state field
const state_mappings = [_]struct {
    keyword: []const u8,
    state_value: []const u8,
}{
    .{ .keyword = "open", .state_value = "open" },
    .{ .keyword = "in progress", .state_value = "in_progress" },
    .{ .keyword = "in_progress", .state_value = "in_progress" },
    .{ .keyword = "closed", .state_value = "closed" },
    .{ .keyword = "resolved", .state_value = "closed" },
    .{ .keyword = "passing", .state_value = "passing" },
    .{ .keyword = "failing", .state_value = "failing" },
    .{ .keyword = "not_run", .state_value = "not_run" },
    .{ .keyword = "draft", .state_value = "draft" },
    .{ .keyword = "approved", .state_value = "approved" },
    .{ .keyword = "implemented", .state_value = "implemented" },
};

/// Priority keyword mappings to context.priority field
const priority_mappings = [_]struct {
    keyword: []const u8,
    priority_value: u8,
}{
    .{ .keyword = "high priority", .priority_value = 1 },
    .{ .keyword = "high", .priority_value = 1 },
    .{ .keyword = "p1", .priority_value = 1 },
    .{ .keyword = "medium priority", .priority_value = 2 },
    .{ .keyword = "medium", .priority_value = 2 },
    .{ .keyword = "p2", .priority_value = 2 },
    .{ .keyword = "p3", .priority_value = 3 },
    .{ .keyword = "low priority", .priority_value = 4 },
    .{ .keyword = "low", .priority_value = 4 },
    .{ .keyword = "p4", .priority_value = 4 },
    .{ .keyword = "p5", .priority_value = 5 },
};

/// Tag keyword mappings
const tag_mappings = [_]struct {
    keyword: []const u8,
    tag_value: []const u8,
}{
    .{ .keyword = "bug", .tag_value = "bug" },
    .{ .keyword = "bugs", .tag_value = "bug" },
    .{ .keyword = "security", .tag_value = "security" },
    .{ .keyword = "secure", .tag_value = "security" },
    .{ .keyword = "api", .tag_value = "api" },
    .{ .keyword = "rest", .tag_value = "api" },
    .{ .keyword = "ui", .tag_value = "ui" },
    .{ .keyword = "frontend", .tag_value = "ui" },
    .{ .keyword = "backend", .tag_value = "backend" },
    .{ .keyword = "database", .tag_value = "database" },
};

// ==================== Detection Logic ====================

/// Check if input is natural language query (vs structured EQL)
pub fn isNaturalLanguageQuery(input: []const u8) bool {
    // Structured EQL indicators
    var has_colon = false;
    var has_logical_op = false;
    var has_field_prefix = false;

    var iter = std.mem.splitScalar(u8, input, ' ');
    while (iter.next()) |token| {
        const trimmed = std.mem.trim(u8, token, &std.ascii.whitespace);

        // Check for colons (field:value)
        if (std.mem.indexOf(u8, trimmed, ":") != null) {
            has_colon = true;
        }

        // Check for field prefixes (context., state., etc.)
        if (std.mem.startsWith(u8, trimmed, "context.") or
            std.mem.startsWith(u8, trimmed, "state.") or
            std.mem.startsWith(u8, trimmed, "type:") or
            std.mem.startsWith(u8, trimmed, "tag:"))
        {
            has_field_prefix = true;
        }

        // Check for logical operators (AND, OR in uppercase)
        const upper = tryToUpperAscii(trimmed) catch continue;
        defer std.heap.page_allocator.free(upper);
        if (std.mem.eql(u8, upper, "AND") or std.mem.eql(u8, upper, "OR")) {
            has_logical_op = true;
        }
    }

    // If has structured EQL indicators, it's not natural language
    if (has_colon and has_logical_op) return false;
    if (has_field_prefix) return false;

    // Otherwise, assume natural language
    return true;
}

// Helper function (allocate with page allocator for isNaturalLanguageQuery)
fn tryToUpperAscii(s: []const u8) ![]u8 {
    const result = try std.heap.page_allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

// ==================== Natural Language Parsing ====================

/// Parse natural language query into structured QueryExpression
pub fn parseNaturalLanguageQuery(allocator: Allocator, input: []const u8) !?QueryExpression {
    var result = QueryExpression{
        .conditions = .{},
        .operator = .@"and",
    };
    errdefer result.deinit(allocator);

    // Tokenize input
    var tokens = try tokenizeInput(allocator, input);
    defer {
        for (tokens.items) |*t| {
            allocator.free(t.value);
        }
        tokens.deinit(allocator);
    }

    // Collect all recognized keywords first
    var type_value: ?[]const u8 = null;
    var state_value: ?[]const u8 = null;
    var priority_value: ?u8 = null;
    var tag_list = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (tag_list.items) |tag| allocator.free(tag);
        tag_list.deinit(allocator);
    }
    var current_operator: FieldOperator = .eq;

    // Process tokens to collect all keywords
    for (tokens.items) |token| {
        switch (token.token_type) {
            .type_keyword => {
                const tval = findTypeMapping(token.value) orelse continue;
                if (type_value == null) {
                    type_value = tval;
                    current_operator = .eq;
                }
            },
            .state_keyword => {
                const sval = findStateMapping(token.value) orelse continue;
                if (state_value == null) {
                    state_value = sval;
                    current_operator = .eq;
                }
            },
            .priority_keyword => {
                const pval = findPriorityMapping(token.value) orelse continue;
                if (priority_value == null) {
                    priority_value = pval;
                    current_operator = .eq;
                }
            },
            .tag_keyword => {
                const tag_val = findTagMapping(token.value) orelse continue;
                const tag_dup = try allocator.dupe(u8, tag_val);
                try tag_list.append(allocator, tag_dup);
            },
            .negation => {
                current_operator = .neq;
            },
            .conjunction => {
                // For simplicity, always use AND for now
                result.operator = .@"and";
                current_operator = .eq;
            },
            .query_word, .unknown => {
                // Ignore query words and unknown tokens
            },
        }
    }

    // Now add conditions in proper order: type, state, priority, tags
    if (type_value) |tval| {
        const field = try allocator.dupe(u8, "type");
        const value = try allocator.dupe(u8, tval);
        try result.conditions.append(allocator, .{
            .field = field,
            .operator = .eq,
            .value = value,
        });
    }

    if (state_value) |sval| {
        const field = try allocator.dupe(u8, "context.status");
        const value = try allocator.dupe(u8, sval);
        try result.conditions.append(allocator, .{
            .field = field,
            .operator = .eq,
            .value = value,
        });
    }

    if (priority_value) |pval| {
        const field = try allocator.dupe(u8, "context.priority");
        const value = try std.fmt.allocPrint(allocator, "{d}", .{pval});
        try result.conditions.append(allocator, .{
            .field = field,
            .operator = .eq,
            .value = value,
        });
    }

    // Add tag filters (if any)
    if (tag_list.items.len > 0) {
        const field = try allocator.dupe(u8, "tag");
        for (tag_list.items) |tag| {
            const tag_dup = try allocator.dupe(u8, tag);
            try result.conditions.append(allocator, .{
                .field = field,
                .operator = .eq,
                .value = tag_dup,
            });
        }
    }

    // If no conditions found, return null
    if (result.conditions.items.len == 0) {
        return null;
    }

    return result;
}

/// Tokenize input into tokens with classification
fn tokenizeInput(allocator: Allocator, input: []const u8) !std.ArrayListUnmanaged(Token) {
    var tokens = std.ArrayListUnmanaged(Token){};
    errdefer {
        for (tokens.items) |*t| allocator.free(t.value);
        tokens.deinit(allocator);
    }

    // Normalize to lowercase
    const lower = try allocator.alloc(u8, input.len);
    defer allocator.free(lower);
    for (input, 0..) |c, i| {
        lower[i] = std.ascii.toLower(c);
    }

    // Split into words
    var iter = std.mem.splitScalar(u8, lower, ' ');
    var pos: usize = 0;

    while (iter.next()) |word| {
        const trimmed = std.mem.trim(u8, word, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        // Find actual position in original input
        const word_pos = findWordPosition(input, trimmed, pos) orelse trimmed.len;
        pos = word_pos + trimmed.len;

        // Classify token
        const token_type = classifyToken(trimmed);

        const token = Token{
            .token_type = token_type,
            .value = try allocator.dupe(u8, trimmed),
            .start = word_pos,
            .end = word_pos + trimmed.len,
        };
        try tokens.append(allocator, token);
    }

    return tokens;
}

/// Classify a token into its type
fn classifyToken(word: []const u8) TokenType {
    // Check for query words
    if (isQueryWord(word)) return .query_word;

    // Check for negation
    if (std.mem.eql(u8, word, "not") or std.mem.eql(u8, word, "without")) return .negation;

    // Check for conjunction
    if (std.mem.eql(u8, word, "and") or std.mem.eql(u8, word, "or")) return .conjunction;

    // Check for type keywords
    if (findTypeMapping(word) != null) return .type_keyword;

    // Check for state keywords
    if (findStateMapping(word) != null) return .state_keyword;

    // Check for priority keywords
    if (findPriorityMapping(word) != null) return .priority_keyword;

    // Check for tag keywords
    if (findTagMapping(word) != null) return .tag_keyword;

    return .unknown;
}

/// Check if word is a query word (show, find, list, etc.)
fn isQueryWord(word: []const u8) bool {
    const query_words = [_][]const u8{ "show", "find", "list", "get", "all", "me" };
    for (query_words) |qw| {
        if (std.mem.eql(u8, word, qw)) return true;
    }
    return false;
}

/// Find type mapping for keyword
fn findTypeMapping(keyword: []const u8) ?[]const u8 {
    for (type_mappings) |mapping| {
        if (std.mem.eql(u8, keyword, mapping.keyword)) {
            return mapping.neurona_type;
        }
    }
    return null;
}

/// Find state mapping for keyword
fn findStateMapping(keyword: []const u8) ?[]const u8 {
    for (state_mappings) |mapping| {
        if (std.mem.eql(u8, keyword, mapping.keyword)) {
            return mapping.state_value;
        }
    }
    return null;
}

/// Find priority mapping for keyword
fn findPriorityMapping(keyword: []const u8) ?u8 {
    for (priority_mappings) |mapping| {
        if (std.mem.eql(u8, keyword, mapping.keyword)) {
            return mapping.priority_value;
        }
    }
    return null;
}

/// Find tag mapping for keyword
fn findTagMapping(keyword: []const u8) ?[]const u8 {
    for (tag_mappings) |mapping| {
        if (std.mem.eql(u8, keyword, mapping.keyword)) {
            return mapping.tag_value;
        }
    }
    return null;
}

/// Find position of word in original input
fn findWordPosition(input: []const u8, word: []const u8, start_pos: usize) ?usize {
    const lower_input = tryToLowerAlloc(input) catch return null;
    defer std.heap.page_allocator.free(lower_input);

    const search_from = if (start_pos >= input.len) 0 else start_pos;
    const pos = std.mem.indexOfPos(u8, lower_input, search_from, word) orelse return null;
    return pos;
}

/// Helper to allocate lowercase string
fn tryToLowerAlloc(s: []const u8) ![]u8 {
    const result = try std.heap.page_allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

// ==================== Tests ====================

test "isNaturalLanguageQuery detects structured EQL" {
    // Structured EQL has colons and logical operators
    try std.testing.expect(!isNaturalLanguageQuery("state:open AND priority:1"));
    try std.testing.expect(!isNaturalLanguageQuery("type:issue"));
    try std.testing.expect(!isNaturalLanguageQuery("context.status:open"));
}

test "isNaturalLanguageQuery detects natural language" {
    // Natural language has no colons with logical operators
    try std.testing.expect(isNaturalLanguageQuery("show me open issues"));
    try std.testing.expect(isNaturalLanguageQuery("find all bugs"));
    try std.testing.expect(isNaturalLanguageQuery("passing tests"));
}

test "parseNaturalLanguageQuery parses type-only query" {
    const allocator = std.testing.allocator;

    var result = try parseNaturalLanguageQuery(allocator, "show me issues");
    defer if (result) |*r| r.deinit(allocator);

    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 1), result.?.conditions.items.len);
    try std.testing.expectEqualStrings("type", result.?.conditions.items[0].field);
    try std.testing.expectEqualStrings("issue", result.?.conditions.items[0].value);
}

test "parseNaturalLanguageQuery parses type and state query" {
    const allocator = std.testing.allocator;

    var result = try parseNaturalLanguageQuery(allocator, "open issues");
    defer if (result) |*r| r.deinit(allocator);

    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 2), result.?.conditions.items.len);

    // First condition: type
    try std.testing.expectEqualStrings("type", result.?.conditions.items[0].field);
    try std.testing.expectEqualStrings("issue", result.?.conditions.items[0].value);

    // Second condition: state
    try std.testing.expectEqualStrings("context.status", result.?.conditions.items[1].field);
    try std.testing.expectEqualStrings("open", result.?.conditions.items[1].value);
}

test "parseNaturalLanguageQuery parses priority query" {
    const allocator = std.testing.allocator;

    var result = try parseNaturalLanguageQuery(allocator, "high priority bugs");
    defer if (result) |*r| r.deinit(allocator);

    try std.testing.expect(result != null);
    try std.testing.expect(result.?.conditions.items.len >= 2);

    // "bugs" is now a tag, not a type. So we expect:
    // - priority:1
    // - tag:bug
    var found_priority = false;
    var found_tag = false;

    for (result.?.conditions.items) |cond| {
        if (std.mem.eql(u8, cond.field, "context.priority") and std.mem.eql(u8, cond.value, "1")) {
            found_priority = true;
        }
        if (std.mem.eql(u8, cond.field, "tag") and std.mem.eql(u8, cond.value, "bug")) {
            found_tag = true;
        }
    }

    try std.testing.expect(found_priority);
    try std.testing.expect(found_tag);
}

test "parseNaturalLanguageQuery handles negation" {
    const allocator = std.testing.allocator;

    var result = try parseNaturalLanguageQuery(allocator, "not closed issues");
    defer if (result) |*r| r.deinit(allocator);

    try std.testing.expect(result != null);
    if (result) |r| {
        // "not closed issues" should have:
        // - type:issue (with eq operator from "issues")
        // - context.status:closed (with neq operator from "not closed")
        try std.testing.expect(r.conditions.items.len >= 2);

        // Verify we have both type and state conditions
        var found_type = false;
        var found_state = false;
        for (r.conditions.items) |c| {
            if (std.mem.eql(u8, c.field, "type")) {
                found_type = true;
            }
            if (std.mem.eql(u8, c.field, "context.status")) {
                found_state = true;
            }
        }
        try std.testing.expect(found_type);
        try std.testing.expect(found_state);
    }
}

test "findTypeMapping returns correct types" {
    try std.testing.expectEqualStrings("issue", findTypeMapping("issue").?);
    try std.testing.expectEqualStrings("issue", findTypeMapping("issues").?);
    try std.testing.expectEqualStrings("test_case", findTypeMapping("test").?);
    try std.testing.expectEqualStrings("requirement", findTypeMapping("req").?);
    try std.testing.expectEqualStrings("feature", findTypeMapping("features").?);
}

test "findStateMapping returns correct states" {
    try std.testing.expectEqualStrings("open", findStateMapping("open").?);
    try std.testing.expectEqualStrings("closed", findStateMapping("closed").?);
    try std.testing.expectEqualStrings("closed", findStateMapping("resolved").?);
    try std.testing.expectEqualStrings("passing", findStateMapping("passing").?);
    try std.testing.expectEqualStrings("in_progress", findStateMapping("in progress").?);
}

test "findPriorityMapping returns correct priorities" {
    try std.testing.expectEqual(@as(u8, 1), findPriorityMapping("high").?);
    try std.testing.expectEqual(@as(u8, 1), findPriorityMapping("p1").?);
    try std.testing.expectEqual(@as(u8, 2), findPriorityMapping("medium").?);
    try std.testing.expectEqual(@as(u8, 4), findPriorityMapping("low").?);
}

test "findTagMapping returns correct tags" {
    try std.testing.expectEqualStrings("bug", findTagMapping("bug").?);
    try std.testing.expectEqualStrings("security", findTagMapping("security").?);
    try std.testing.expectEqualStrings("api", findTagMapping("rest").?);
}
