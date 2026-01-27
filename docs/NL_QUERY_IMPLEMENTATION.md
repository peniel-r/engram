# Natural Language Query Parsing Implementation Plan

## Overview

Implement natural language query parsing for EQL (Engram Query Language) to allow users to query Neuronas using conversational language instead of structured syntax.

**Current State**:
- `src/utils/state_filters.zig` parses structured EQL: `"state:open AND priority:1"`
- `src/cli/query.zig` supports 5 search modes but requires exact field/operator syntax
- Users must know EQL syntax (field:operator:value, AND/OR operators)

**Goal**:
- Accept natural language queries like "show me open issues"
- Convert to structured EQL: `"type:issue AND context.state:open"`
- Maintain full backward compatibility with existing structured queries

---

## Implementation Tasks

### Task 1: Create Natural Language Query Parser
**File**: `src/utils/nl_query_parser.zig`

**Components**:
1. **Token Classification**
   - Detect query intent (type, state, priority, tag)
   - Classify tokens as field names, values, operators, or modifiers

2. **Natural Language Mappings**
   - Type keywords → Neurona types:
     - "issue", "issues", "bug", "bugs" → `type:issue`
     - "test", "tests", "test case" → `type:test_case`
     - "requirement", "requirements", "req" → `type:requirement`
     - "feature", "features" → `type:feature`
     - "artifact", "artifacts" → `type:artifact`

   - State keywords → context.status:
     - "open" → `context.state:open`
     - "closed", "resolved" → `context.state:closed`
     - "passing" → `context.status:passing`
     - "failing" → `context.status:failing`
     - "in progress", "in_progress" → `context.state:in_progress`

   - Priority keywords → context.priority:
     - "high priority", "p1" → `context.priority:1`
     - "medium priority", "p2", "p3" → `context.priority:2`
     - "low priority", "p4", "p5" → `context.priority:4`

   - Tag keywords → tags:
     - "bug", "bugs" → `tag:bug`
     - "security", "secure" → `tag:security`
     - "api", "rest" → `tag:api`

3. **Query Conversion**
   - Convert natural language to FilterExpression
   - Combine multiple conditions with AND/OR
   - Handle negation (e.g., "not closed", "without bugs")

4. **Detection Logic**
   - Distinguish natural language from structured EQL
   - Structured EQL indicators: colons, operators (AND/OR), quotes
   - Natural language indicators: plain English phrases

**API**:
```zig
pub fn parseNaturalLanguageQuery(allocator: Allocator, input: []const u8) !?QueryExpression
pub fn isNaturalLanguageQuery(input: []const u8) bool
```

### Task 2: Integrate with Query Command
**File**: `src/cli/query.zig` (modifications)

**Changes**:
1. Add natural language detection in `handleQuery()` function
2. When natural language detected:
   - Call `nl_query_parser.parseNaturalLanguageQuery()`
   - Convert result to `QueryConfig.filters`
   - Proceed with existing query execution
3. Add `--nl` flag to explicitly force natural language mode

**Integration Flow**:
```
User Input → Check if NL → Parse NL → Convert to EQL → Execute Query
                        ↓
                  Structured EQL → Direct parsing → Execute Query
```

### Task 3: Update Documentation
**Files**: `src/main.zig`, `docs/PLAN.md`

**Changes**:
1. Update `printQueryHelp()` to include natural language examples
2. Update PLAN.md to mark milestone 3.2.2 as complete

---

## Natural Language Query Patterns

### Supported Patterns

| Pattern | Example | Converts To |
|---------|---------|-------------|
| **Type only** | "issues" | `type:issue` |
| **Type + State** | "open issues" | `type:issue AND context.state:open` |
| **Type + Priority** | "high priority bugs" | `type:issue AND context.priority:1 AND tag:bug` |
| **State only** | "show me passing tests" | `type:test_case AND context.status:passing` |
| **Multiple types** | "requirements and tests" | `type:requirement OR type:test_case` |
| **With negation** | "open issues not p1" | `type:issue AND context.state:open AND context.priority!=1` |
| **Tag filtering** | "show me bugs" | `tag:bug` |
| **Combined** | "find all high priority security bugs" | `type:issue AND tag:security AND context.priority:1` |

### Query Intent Detection

1. **Type Intent**: Contains "issue", "test", "requirement", "feature", "artifact"
2. **State Intent**: Contains "open", "closed", "passing", "failing"
3. **Priority Intent**: Contains "priority", "p1", "high", "low"
4. **Tag Intent**: Contains "bug", "security", "api", etc.

---

## Testing Strategy

### Unit Tests (`nl_query_parser.zig`)

```zig
test "detects natural language query"
test "detects structured EQL query"
test "parses type-only queries"
test "parses type and state queries"
test "parses priority queries"
test "parses tag queries"
test "handles negation"
test "converts to structured EQL"
test "handles multiple conditions"
```

### Integration Tests

Create test file: `tests/integration/nl_query_tests.zig`

Test cases:
```bash
engram query "open issues"
engram query "show me passing tests"
engram query "high priority bugs"
engram query "find all security issues"
engram query --nl "closed requirements"
```

---

## Backward Compatibility

**Guarantees**:
1. All existing structured EQL queries continue to work unchanged
2. Natural language detection is conservative (defaults to structured if ambiguous)
3. `--mode` flag works with both natural language and structured queries
4. JSON output format unchanged

**Detection Rules**:
- If input contains `:` AND `AND`/`OR` → Structured EQL
- If input contains field names like `context.status:` → Structured EQL
- Otherwise → Attempt natural language parsing

---

## Performance Considerations

**Targets**:
- Natural language parsing: < 5ms
- No impact on structured query performance (< 10ms for depth 5)

**Optimizations**:
- Use simple string matching (not full NLP)
- Pre-computed keyword hash maps
- Early exit for structured EQL detection
- Minimal allocations in hot path

---

## Rollout Strategy

1. **Phase 1**: Implement parser with unit tests
2. **Phase 2**: Integrate with query command
3. **Phase 3**: Add integration tests
4. **Phase 4**: Update documentation and help text
5. **Phase 5**: Manual testing and refinement

---

## Future Enhancements (Out of Scope)

- Full NLP integration (spaCy, transformers)
- Fuzzy matching for typos
- Query suggestions/autocomplete
- Voice input support
- Multi-language support (i18n)

---

## Success Criteria

- [ ] Natural language parser accepts common query patterns
- [ ] Converts NL to correct EQL format
- [ ] Integrates seamlessly with existing query command
- [ ] All existing structured EQL queries work unchanged
- [ ] Unit tests achieve 90%+ coverage
- [ ] Integration tests pass
- [ ] Performance targets met (< 5ms parsing)
- [ ] Documentation updated
- [ ] `zig build run` succeeds

---

**Created**: 2026-01-25
**Status**: Ready for implementation
**Estimated Time**: 2-3 hours
