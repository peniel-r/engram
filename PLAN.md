# Plan: Advanced EQL Support

## Objective

Implement advanced features in the Engram Query Language (EQL) parser to support robust querying capabilities, specifically **Logical Grouping (Parentheses)** and **Negation (NOT operator)**.

## Current State

- The current parser (`src/utils/eql_parser.zig`) supports a flat list of conditions.
- Logic is limited to simple chained operators (associativity is ambiguous in current implementation).
- No support for precedence control via `()`.
- No proper `NOT` operator (only `neq` field operator).

## Implementation Phases

### Phase 1: AST Design & Data Structures

**Goal**: Move from flat lists to a recursive Abstract Syntax Tree (AST).

1. **Define AST Nodes**:
    - `QueryNode` tagged union:
        - `condition`: `EQLCondition` (existing)
        - `logical`: `binary_op` (left: *Node, op: AND/OR, right:*Node)
        - `not`: `unary_op` (op: NOT, child: *Node)
        - `group`: `group_node` (child: *Node) - *Optional, might be implicit in AST structure*

### Phase 2: Recursive Descent Parser

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

### Phase 3: Query Evaluator

**Goal**: Execute the AST against Neurona artifacts.

1. **Evaluator Logic**:
    - Implement `evaluate(node: *QueryNode, neurona: *Neurona) bool`.
    - Recursively traverse the tree.
    - `AND`: returns `eval(left) && eval(right)`.
    - `OR`: returns `eval(left) || eval(right)`.
    - `NOT`: returns `!eval(child)`.
2. **Integration**:
    - Update `src/cli/query_helpers.zig` to use the new AST.
    - Update `src/cli/query.zig` to support the new filter structure (or replace `QueryFilter` list with `QueryAST`).

### Phase 4: Testing & Validation

**Goal**: Ensure correctness of complex queries.

1. **Unit Tests**:
    - `(type:issue OR type:bug) AND priority:1`
    - `type:requirement AND NOT status:implemented`
    - Nested parentheses `((A OR B) AND C) OR D`
2. **CLI Verification**:
    - Run `engram query` with complex strings to verify output.

## Technical Details

### File Handling

- **Target**: `src/utils/eql_parser.zig`
- **Dependencies**: `src/cli/query.zig` (needs refactoring to accept AST)

### Migration Strategy

To avoid breaking changes immediately:

1. Implement new parser in parallel or replace internals of `EQLParser` while keeping public API similar if possible (though return type must change).
2. Refactor `cli/query.zig` to handle the new return type.

## Success Criteria

- [ ] Parser correctly handles parentheses nesting.
- [ ] Parser correctly handles `NOT` operator.
- [ ] Evaluator correctly filters Neuronas based on complex logic.
- [ ] `AGENTS.md` examples (reverted in previous step) can be uncommented and work.
