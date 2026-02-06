// File: src/utils/eql_parser.zig
// EQL (Engram Query Language) Parser
// Parses structured query syntax like: "type:issue AND tag:p1"
//
// Grammar:
//   Expression    -> Term { OR Term }
//   Term          -> Factor { AND Factor }
//   Factor        -> NOT Factor | ( Expression ) | Condition
//   Condition     -> field ':' [op ':'] value | link(type, target)
//
// Examples:
//   type:issue
//   type:issue AND tag:p1
//   context.status:open AND context.priority:1
//   priority:gte:3
//   title:contains:authentication
//   link(validates, req.auth.001) AND type:test_case
//   (type:issue OR type:bug) AND priority:1
//   type:requirement AND NOT status:implemented
//   ((A OR B) AND C) OR D

const std = @import("std");
const Allocator = std.mem.Allocator;

// ==================== Data Structures ====================

/// Parsed EQL query (flat structure - to be replaced by QueryAST in Phase 2)
pub const EQLQuery = struct {
    conditions: std.ArrayListUnmanaged(EQLCondition),
    logic_op: LogicOp = .@"and",

    pub fn init() EQLQuery {
        return .{
            .conditions = .{},
            .logic_op = .@"and",
        };
    }

    pub fn deinit(self: *EQLQuery, allocator: Allocator) void {
        for (self.conditions.items) |*cond| {
            cond.deinit(allocator);
        }
        self.conditions.deinit(allocator);
    }
};

/// Query node in AST (Phase 1+)
pub const QueryNode = union(enum) {
    condition: EQLCondition,
    logical: LogicalOp,
    not: NotOp,
    group: GroupNode,

    pub fn deinit(self: *QueryNode, allocator: Allocator) void {
        switch (self.*) {
            .condition => |*cond| cond.deinit(allocator),
            .logical => |*op| {
                op.left.deinit(allocator);
                allocator.destroy(op.left);
                op.right.deinit(allocator);
                allocator.destroy(op.right);
            },
            .not => |*op| {
                op.child.deinit(allocator);
                allocator.destroy(op.child);
            },
            .group => |*node| {
                node.child.deinit(allocator);
                allocator.destroy(node.child);
            },
        }
    }
};

/// Binary logical operation (AND/OR)
pub const LogicalOp = struct {
    left: *QueryNode,
    op: LogicOp,
    right: *QueryNode,
};

/// Unary NOT operation
pub const NotOp = struct {
    child: *QueryNode,
};

/// Grouped expression (parentheses)
pub const GroupNode = struct {
    child: *QueryNode,
};

/// AST-based EQL query (Phase 1+)
pub const QueryAST = struct {
    root: *QueryNode,

    pub fn init(root: *QueryNode) QueryAST {
        return .{
            .root = root,
        };
    }

    pub fn deinit(self: *QueryAST, allocator: Allocator) void {
        self.root.deinit(allocator);
        allocator.destroy(self.root);
    }
};

/// Query condition
pub const EQLCondition = struct {
    field: []const u8,
    op: ConditionOp,
    value: []const u8,

    // For link conditions
    link_type: ?[]const u8 = null,
    link_target: ?[]const u8 = null,

    pub fn deinit(self: *EQLCondition, allocator: Allocator) void {
        allocator.free(self.field);
        allocator.free(self.value);
        if (self.link_type) |lt| allocator.free(lt);
        if (self.link_target) |lt| allocator.free(lt);
    }
};

/// Logical operators
pub const LogicOp = enum {
    @"and",
    @"or",

    pub fn fromString(s: []const u8) ?LogicOp {
        const upper = toUpperTemp(s) catch return null;
        defer std.heap.page_allocator.free(upper);

        if (std.mem.eql(u8, upper, "AND")) return .@"and";
        if (std.mem.eql(u8, upper, "OR")) return .@"or";
        return null;
    }
};

/// Condition operators
pub const ConditionOp = enum {
    eq, // Equal (default)
    neq, // Not equal
    gt, // Greater than
    lt, // Less than
    gte, // Greater or equal
    lte, // Less or equal
    contains, // String contains
    not_contains, // String not contains

    pub fn fromString(s: []const u8) ?ConditionOp {
        if (std.mem.eql(u8, s, "eq")) return .eq;
        if (std.mem.eql(u8, s, "neq")) return .neq;
        if (std.mem.eql(u8, s, "gt")) return .gt;
        if (std.mem.eql(u8, s, "lt")) return .lt;
        if (std.mem.eql(u8, s, "gte")) return .gte;
        if (std.mem.eql(u8, s, "lte")) return .lte;
        if (std.mem.eql(u8, s, "contains")) return .contains;
        if (std.mem.eql(u8, s, "not_contains")) return .not_contains;
        return null;
    }
};

// ==================== Parser ====================

/// EQL Parser
pub const EQLParser = struct {
    query: []const u8,
    pos: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator, query: []const u8) EQLParser {
        return .{
            .query = query,
            .allocator = allocator,
        };
    }

    /// Parse the query into an EQLQuery
    pub fn parse(self: *EQLParser) !EQLQuery {
        var result = EQLQuery.init();
        errdefer result.deinit(self.allocator);

        // Parse first condition
        const first_cond = try self.parseCondition();
        try result.conditions.append(self.allocator, first_cond);

        // Parse additional conditions with logical operators
        while (self.pos < self.query.len) {
            self.skipWhitespace();
            if (self.pos >= self.query.len) break;

            // Try to parse logical operator
            const logic_op = self.parseLogicOp() orelse break;
            result.logic_op = logic_op;

            self.skipWhitespace();

            // Parse next condition
            const cond = try self.parseCondition();
            try result.conditions.append(self.allocator, cond);
        }

        return result;
    }

    /// Parse a single condition
    fn parseCondition(self: *EQLParser) !EQLCondition {
        self.skipWhitespace();

        // Check for link condition: link(type, target)
        if (self.peekString("link(")) {
            return try self.parseLinkCondition();
        }

        // Parse field condition: field:op:value or field:value
        return try self.parseFieldCondition();
    }

    /// Parse link condition: link(type, target)
    fn parseLinkCondition(self: *EQLParser) !EQLCondition {
        // Consume "link("
        self.pos += 5;
        self.skipWhitespace();

        // Parse connection type
        const type_start = self.pos;
        while (self.pos < self.query.len and
            self.query[self.pos] != ',' and
            self.query[self.pos] != ')')
        {
            self.pos += 1;
        }
        const link_type = std.mem.trim(u8, self.query[type_start..self.pos], &std.ascii.whitespace);

        if (self.pos >= self.query.len or self.query[self.pos] != ',') {
            return error.InvalidLinkSyntax;
        }
        self.pos += 1; // Skip comma
        self.skipWhitespace();

        // Parse target ID
        const target_start = self.pos;
        while (self.pos < self.query.len and self.query[self.pos] != ')') {
            self.pos += 1;
        }
        const link_target = std.mem.trim(u8, self.query[target_start..self.pos], &std.ascii.whitespace);

        if (self.pos >= self.query.len or self.query[self.pos] != ')') {
            return error.InvalidLinkSyntax;
        }
        self.pos += 1; // Skip closing paren

        return EQLCondition{
            .field = try self.allocator.dupe(u8, "link"),
            .op = .eq,
            .value = try self.allocator.dupe(u8, ""),
            .link_type = try self.allocator.dupe(u8, link_type),
            .link_target = try self.allocator.dupe(u8, link_target),
        };
    }

    /// Parse field condition: field:op:value or field:value
    fn parseFieldCondition(self: *EQLParser) !EQLCondition {
        // Parse field name
        const field_start = self.pos;
        while (self.pos < self.query.len and
            self.query[self.pos] != ':' and
            !std.ascii.isWhitespace(self.query[self.pos]))
        {
            self.pos += 1;
        }
        const field = self.query[field_start..self.pos];

        if (self.pos >= self.query.len or self.query[self.pos] != ':') {
            return error.InvalidFieldSyntax;
        }
        self.pos += 1; // Skip first colon

        // Try to parse operator (optional)
        const op_start = self.pos;
        var has_op = false;
        var op: ConditionOp = .eq;

        // Peek ahead for second colon to detect operator
        var peek_pos = self.pos;
        while (peek_pos < self.query.len and
            self.query[peek_pos] != ':' and
            !std.ascii.isWhitespace(self.query[peek_pos]) and
            self.query[peek_pos] != 'A' and
            self.query[peek_pos] != 'O')
        {
            peek_pos += 1;
        }

        if (peek_pos < self.query.len and self.query[peek_pos] == ':') {
            // We have an operator
            const op_str = self.query[op_start..peek_pos];
            if (ConditionOp.fromString(op_str)) |parsed_op| {
                op = parsed_op;
                has_op = true;
                self.pos = peek_pos + 1; // Skip operator and second colon
            }
        }

        // Parse value
        const value_start = self.pos;
        while (self.pos < self.query.len and
            !std.ascii.isWhitespace(self.query[self.pos]))
        {
            // Stop at logical operators (AND, OR)
            if (self.peekString("AND") or self.peekString("OR")) break;
            self.pos += 1;
        }
        const value = self.query[value_start..self.pos];

        return EQLCondition{
            .field = try self.allocator.dupe(u8, field),
            .op = op,
            .value = try self.allocator.dupe(u8, value),
        };
    }

    /// Parse logical operator (AND, OR)
    fn parseLogicOp(self: *EQLParser) ?LogicOp {
        self.skipWhitespace();

        if (self.peekString("AND")) {
            self.pos += 3;
            return .@"and";
        }

        if (self.peekString("OR")) {
            self.pos += 2;
            return .@"or";
        }

        return null;
    }

    /// Skip whitespace
    fn skipWhitespace(self: *EQLParser) void {
        while (self.pos < self.query.len and
            std.ascii.isWhitespace(self.query[self.pos]))
        {
            self.pos += 1;
        }
    }

    /// Peek ahead to check if string matches
    fn peekString(self: *EQLParser, s: []const u8) bool {
        if (self.pos + s.len > self.query.len) return false;
        return std.mem.eql(u8, self.query[self.pos .. self.pos + s.len], s);
    }
};

// ==================== Helper Functions ====================

/// Check if query string is EQL format (vs natural language)
pub fn isEQLQuery(query: []const u8) bool {
    // EQL indicators:
    // 1. Contains colons with field names (type:, tag:, context., etc.)
    // 2. Contains AND/OR logical operators
    // 3. Contains link() syntax

    var has_colon = false;
    var has_logical_op = false;
    var has_link = false;

    // Check for link syntax
    if (std.mem.indexOf(u8, query, "link(") != null) {
        has_link = true;
    }

    // Check for field:value patterns
    var iter = std.mem.splitScalar(u8, query, ' ');
    while (iter.next()) |token| {
        const trimmed = std.mem.trim(u8, token, &std.ascii.whitespace);

        // Check for colons (field:value)
        if (std.mem.indexOf(u8, trimmed, ":") != null) {
            has_colon = true;
        }

        // Check for logical operators (AND, OR)
        const upper = toUpperTemp(trimmed) catch continue;
        defer std.heap.page_allocator.free(upper);
        if (std.mem.eql(u8, upper, "AND") or std.mem.eql(u8, upper, "OR")) {
            has_logical_op = true;
        }
    }

    // If has EQL indicators, it's EQL
    return has_link or (has_colon and (has_logical_op or isSimpleFieldQuery(query)));
}

/// Check if query is a simple field query (field:value)
fn isSimpleFieldQuery(query: []const u8) bool {
    // Simple patterns: "type:issue", "tag:security", "context.status:open"
    const colon_idx = std.mem.indexOf(u8, query, ":") orelse return false;

    // Check if it's a field name before colon
    const field = std.mem.trim(u8, query[0..colon_idx], &std.ascii.whitespace);

    // Common field names
    const field_names = [_][]const u8{
        "type",
        "tag",
        "context.status",
        "context.priority",
        "context.state",
        "priority",
        "state",
        "status",
        "title",
        "id",
    };

    for (field_names) |fname| {
        if (std.mem.eql(u8, field, fname)) return true;
        if (std.mem.startsWith(u8, field, "context.")) return true;
    }

    return false;
}

/// Helper to convert string to uppercase (temporary allocation)
fn toUpperTemp(s: []const u8) ![]u8 {
    const result = try std.heap.page_allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

// ==================== Tests ====================

test "isEQLQuery: detects EQL syntax" {
    try std.testing.expect(isEQLQuery("type:issue"));
    try std.testing.expect(isEQLQuery("type:issue AND tag:p1"));
    try std.testing.expect(isEQLQuery("context.status:open"));
    try std.testing.expect(isEQLQuery("priority:gte:3"));
    try std.testing.expect(isEQLQuery("link(validates, req.001)"));
}

test "isEQLQuery: rejects natural language" {
    try std.testing.expect(!isEQLQuery("show me open issues"));
    try std.testing.expect(!isEQLQuery("find all bugs"));
    try std.testing.expect(!isEQLQuery("passing tests"));
}

test "parse: simple field condition" {
    const allocator = std.testing.allocator;

    var parser = EQLParser.init(allocator, "type:issue");
    var query = try parser.parse();
    defer query.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), query.conditions.items.len);
    try std.testing.expectEqualStrings("type", query.conditions.items[0].field);
    try std.testing.expectEqual(ConditionOp.eq, query.conditions.items[0].op);
    try std.testing.expectEqualStrings("issue", query.conditions.items[0].value);
}

test "parse: field condition with operator" {
    const allocator = std.testing.allocator;

    var parser = EQLParser.init(allocator, "priority:gte:3");
    var query = try parser.parse();
    defer query.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), query.conditions.items.len);
    try std.testing.expectEqualStrings("priority", query.conditions.items[0].field);
    try std.testing.expectEqual(ConditionOp.gte, query.conditions.items[0].op);
    try std.testing.expectEqualStrings("3", query.conditions.items[0].value);
}

test "parse: multiple conditions with AND" {
    const allocator = std.testing.allocator;

    var parser = EQLParser.init(allocator, "type:issue AND tag:p1");
    var query = try parser.parse();
    defer query.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), query.conditions.items.len);
    try std.testing.expectEqual(LogicOp.@"and", query.logic_op);

    try std.testing.expectEqualStrings("type", query.conditions.items[0].field);
    try std.testing.expectEqualStrings("issue", query.conditions.items[0].value);

    try std.testing.expectEqualStrings("tag", query.conditions.items[1].field);
    try std.testing.expectEqualStrings("p1", query.conditions.items[1].value);
}

test "parse: link condition" {
    const allocator = std.testing.allocator;

    var parser = EQLParser.init(allocator, "link(validates, req.auth.001)");
    var query = try parser.parse();
    defer query.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), query.conditions.items.len);
    try std.testing.expectEqualStrings("link", query.conditions.items[0].field);
    try std.testing.expectEqualStrings("validates", query.conditions.items[0].link_type.?);
    try std.testing.expectEqualStrings("req.auth.001", query.conditions.items[0].link_target.?);
}

test "parse: complex query with link and field" {
    const allocator = std.testing.allocator;

    var parser = EQLParser.init(allocator, "link(validates, req.001) AND type:test_case");
    var query = try parser.parse();
    defer query.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), query.conditions.items.len);

    // First condition: link
    try std.testing.expectEqualStrings("link", query.conditions.items[0].field);
    try std.testing.expectEqualStrings("validates", query.conditions.items[0].link_type.?);

    // Second condition: type
    try std.testing.expectEqualStrings("type", query.conditions.items[1].field);
    try std.testing.expectEqualStrings("test_case", query.conditions.items[1].value);
}

// ==================== AST Tests (Phase 1) ====================

test "AST: condition node" {
    const allocator = std.testing.allocator;

    const node = try allocator.create(QueryNode);
    node.* = .{
        .condition = EQLCondition{
            .field = try allocator.dupe(u8, "type"),
            .op = .eq,
            .value = try allocator.dupe(u8, "issue"),
        },
    };
    defer {
        node.deinit(allocator);
        allocator.destroy(node);
    }

    try std.testing.expect(node.* == .condition);
    try std.testing.expectEqualStrings("type", node.condition.field);
    try std.testing.expectEqualStrings("issue", node.condition.value);
}

test "AST: logical node (AND)" {
    const allocator = std.testing.allocator;

    const left = try allocator.create(QueryNode);
    left.* = .{
        .condition = EQLCondition{
            .field = try allocator.dupe(u8, "type"),
            .op = .eq,
            .value = try allocator.dupe(u8, "issue"),
        },
    };

    const right = try allocator.create(QueryNode);
    right.* = .{
        .condition = EQLCondition{
            .field = try allocator.dupe(u8, "tag"),
            .op = .eq,
            .value = try allocator.dupe(u8, "p1"),
        },
    };

    const node = try allocator.create(QueryNode);
    node.* = .{
        .logical = LogicalOp{
            .left = left,
            .op = .@"and",
            .right = right,
        },
    };
    defer {
        node.deinit(allocator);
        allocator.destroy(node);
    }

    try std.testing.expect(node.* == .logical);
    try std.testing.expectEqualStrings("type", node.logical.left.condition.field);
    try std.testing.expectEqualStrings("tag", node.logical.right.condition.field);
}

test "AST: NOT node" {
    const allocator = std.testing.allocator;

    const child = try allocator.create(QueryNode);
    child.* = .{
        .condition = EQLCondition{
            .field = try allocator.dupe(u8, "status"),
            .op = .eq,
            .value = try allocator.dupe(u8, "implemented"),
        },
    };

    const node = try allocator.create(QueryNode);
    node.* = .{
        .not = NotOp{
            .child = child,
        },
    };
    defer {
        node.deinit(allocator);
        allocator.destroy(node);
    }

    try std.testing.expect(node.* == .not);
    try std.testing.expectEqualStrings("status", node.not.child.condition.field);
    try std.testing.expectEqualStrings("implemented", node.not.child.condition.value);
}

test "AST: group node" {
    const allocator = std.testing.allocator;

    const child = try allocator.create(QueryNode);
    child.* = .{
        .condition = EQLCondition{
            .field = try allocator.dupe(u8, "type"),
            .op = .eq,
            .value = try allocator.dupe(u8, "issue"),
        },
    };

    const node = try allocator.create(QueryNode);
    node.* = .{
        .group = GroupNode{
            .child = child,
        },
    };
    defer {
        node.deinit(allocator);
        allocator.destroy(node);
    }

    try std.testing.expect(node.* == .group);
    try std.testing.expectEqualStrings("type", node.group.child.condition.field);
}

test "AST: QueryAST initialization" {
    const allocator = std.testing.allocator;

    const root = try allocator.create(QueryNode);
    root.* = .{
        .condition = EQLCondition{
            .field = try allocator.dupe(u8, "type"),
            .op = .eq,
            .value = try allocator.dupe(u8, "issue"),
        },
    };

    var ast = QueryAST.init(root);
    defer ast.deinit(allocator);

    try std.testing.expectEqualStrings("type", ast.root.condition.field);
    try std.testing.expectEqualStrings("issue", ast.root.condition.value);
}
