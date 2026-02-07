# Plan: Advanced EQL Support

## Objective

Implement advanced features in the Engram Query Language (EQL) parser to support robust querying capabilities, specifically:
- **Logical Grouping (Parentheses)** for expression precedence
- **Negation (NOT operator)** for boolean logic
- **Context Field Support** for ALM status/priority queries (Phase 5)

## Current State

- The current parser (`src/utils/eql_parser.zig`) supports a flat list of conditions.
- Logic is limited to simple chained operators (associativity is ambiguous in current implementation).
- No support for precedence control via `()`.
- No proper `NOT` operator (only `neq` field operator).

## Implementation Phases

### Phase 1: AST Design & Data Structures ✅

**Goal**: Move from flat lists to a recursive Abstract Syntax Tree (AST).

1. **Define AST Nodes**:
    - `QueryNode` tagged union:
        - `condition`: `EQLCondition` (existing)
        - `logical`: `binary_op` (left: *Node, op: AND/OR, right:*Node)
        - `not`: `unary_op` (op: NOT, child: *Node)
        - `group`: `group_node` (child: *Node) - *Optional, might be implicit in AST structure*

**Status**: COMPLETED ✅

**Implementation**:
- Added `QueryNode` tagged union in `src/utils/eql_parser.zig`
- Added `LogicalOp` struct for binary operations (AND/OR)
- Added `NotOp` struct for unary NOT operation
- Added `GroupNode` struct for parenthesized expressions
- Added `QueryAST` wrapper struct with `root: *QueryNode`
- Kept existing `EQLQuery` for backward compatibility until Phase 2
- Implemented proper `deinit` methods for all AST nodes
- Added comprehensive unit tests for all AST node types
- Updated grammar comment to reflect new capabilities

### Phase 2: Recursive Descent Parser ✅

**Goal**: Rewrite `EQLParser` to handle grammar with precedence.

1. **Grammar Definition**:

    ```text
    Expression    -> Term { OR Term }
    Term          -> Factor { AND Factor }
    Factor        -> NOT Factor | ( Expression ) | Condition
    Condition     -> field:op:value | link(...)
    ```

2. **Implementation**:
    - Implement `parseExpression()`, `parseTerm()`, `parseFactor()`.
    - Handle `(` and `)` token consumption.
    - Handle `NOT` token.

**Status**: COMPLETED ✅

**Implementation**:
- Added `ParseError` union type for explicit error handling
- Implemented `parseAST()` entry method returning `QueryAST`
- Implemented `parseExpression()` for OR operations (lowest precedence)
- Implemented `parseTerm()` for AND operations (medium precedence)
- Implemented `parseFactor()` for NOT, parentheses, and conditions (highest precedence)
- Added `peekChar()` helper for single character peeking
- Fixed `parseFieldCondition()` to stop at closing parenthesis `)`
- Added 10 comprehensive unit tests for all parsing scenarios:
  - Simple conditions
  - AND expressions
  - OR expressions
  - NOT operator
  - Parenthesized expressions
  - Nested expressions
  - NOT with parentheses
  - Grouped OR with AND
  - Multiple OR operators (left-associative)
   - All 22 eql_parser tests pass

### Phase 3: Query Evaluator ✅

**Goal**: Execute AST against Neurona artifacts.

1. **Evaluator Logic**:
    - Implement `evaluate(node: *QueryNode, neurona: *Neurona) bool`.
    - Recursively traverse tree.
    - `AND`: returns `eval(left) && eval(right)`.
    - `OR`: returns `eval(left) || eval(right)`.
    - `NOT`: returns `!eval(child)`.
2. **Integration**:
    - Update `src/cli/query_helpers.zig` to use new AST.
    - Update `src/cli/query.zig` to support new filter structure (or replace `QueryFilter` list with `QueryAST`).

**Status**: COMPLETED ✅

**Implementation**:
- ✅ Added `evaluateAST()` function for recursive AST evaluation
- ✅ Added helper functions: `evaluateCondition()`, `evaluateLinkCondition()`, `evaluateTagCondition()`, `evaluateStringOp()`, `evaluateBoolOp()`
- ✅ Created `NeuronaView` struct to avoid circular imports with Neurona type
- ✅ Fixed type signatures: `evaluateCondition` accepts value (not pointer)
- ✅ Updated `query_helpers.zig` to use AST parser (`parseAST()`) with fallback to legacy parser
- ✅ Added `executeASTQuery()` in `query_helpers.zig` and `executeFilterQueryWithAST()` in `query.zig`
- ✅ Added `createNeuronaView()` function to convert Neurona to NeuronaView for evaluation
- ✅ All 9 evaluator tests passing
- ✅ All 31 eql_parser tests passing
- ✅ Full build (`zig build run`) succeeds
- ✅ Module path constraints resolved using view pattern

### Phase 4: Testing & Validation ✅

**Goal**: Ensure correctness of complex queries.

1. **Unit Tests**:
    - `(type:issue OR type:bug) AND priority:1` ✅
    - `type:requirement AND NOT status:implemented` (adjusted to `type:requirement AND NOT type:issue`) ✅
    - Nested parentheses `((A OR B) AND C) OR D` ✅
2. **CLI Verification**:
    - Run `engram query` with complex strings to verify output. ✅

**Status**: COMPLETED ✅

**Implementation**:
- ✅ Added 6 complex unit tests:
  - `evaluateAST: complex OR + AND - both match` - Tests `(type:issue OR type:bug) AND tag:security`
  - `evaluateAST: complex OR + AND - one match` - Tests when only part of query matches
  - `evaluateAST: AND + NOT - with negation` - Tests `type:requirement AND NOT type:issue`
  - `evaluateAST: AND + NOT - negation fails` - Tests contradictory conditions
  - `evaluateAST: deeply nested parentheses` - Tests `((type:issue OR type:bug) AND tag:p1) OR type:requirement`
  - `evaluateAST: deeply nested parentheses - no match` - Tests failure case
- ✅ Created test cortex with sample data (5 neuronas)
- ✅ Verified CLI queries with complex EQL strings:
  - `type:issue` ✓
  - `type:issue OR type:bug` ✓
  - `(type:issue OR type:test_case) AND tag:bug` ✓
  - `type:issue AND NOT type:test_case` ✓
  - `((type:issue OR type:bug) AND tag:bug) OR type:requirement` ✓
  - `type:test_case` ✓
  - `tag:test` ✓
  - `link(validates, req.user-authentication)` ✓
- ✅ All 15 evaluator tests passing
- ✅ All 37 eql_parser tests passing
- ✅ All complex EQL queries work correctly in CLI

**Note**: AGENTS.md examples use `status` and `state` fields which are not currently supported by evaluator. These require context field access which would need Neurona context fields in the view.

### Phase 5: Context Field Support 🔄

**Goal**: Add support for context field queries (`status`, `priority`, `assignee`) to enable full AGENTS.md examples.

1. **Extend NeuronaView**:
    - Add context field to NeuronaView struct
    - Include status, priority, assignee for ALM types
2. **Update Evaluator**:
    - Add `context.status` field evaluation
    - Add `context.priority` field evaluation
    - Add `context.assignee` field evaluation
3. **Integration**:
    - Update `createNeuronaView()` to copy context data
    - Handle context.* field parsing in parser
4. **Testing**:
    - Test `status:implemented`, `status:neq:implemented`
    - Test `context.priority:1`, `priority:gte:3`
    - Test `context.assignee:alice`
    - Verify all AGENTS.md examples work

**Status**: PENDING 🔄

**Implementation**:
- ⏳ Extend NeuronaView with context fields
- ⏳ Update evaluateCondition() for context.* syntax
- ⏳ Add context field parsing support
- ⏳ Update createNeuronaView() with context data
- ⏳ Add unit tests for context queries
- ⏳ Verify AGENTS.md examples

**Examples to support**:
```eql
type:requirement AND status:neq:implemented
type:issue AND status:open
type:requirement AND state:approved
context.status:open AND context.priority:1
```

## Technical Details

### File Handling

- **Target**: `src/utils/eql_parser.zig`
- **Dependencies**: `src/cli/query.zig` (needs refactoring to accept AST)

### Migration Strategy

To avoid breaking changes immediately:

1. Implement new parser in parallel or replace internals of `EQLParser` while keeping public API similar if possible (though return type must change).
2. Refactor `cli/query.zig` to handle the new return type.

## Success Criteria

- [x] Parser correctly handles parentheses nesting.
- [x] Parser correctly handles `NOT` operator.
- [x] Evaluator correctly filters Neuronas based on complex logic.
- [ ] `AGENTS.md` examples (reverted in previous step) can be uncommented and work.
    - **Phase 5 Required**: Basic EQL examples work (type, tag, link)
    - **Phase 5 Required**: `status` and `state` fields require context access (see Phase 5)
