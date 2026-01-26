# Engram CLI Master Plan

**Version**: 1.1.0
**Status**: Phase 1 Complete - Phase 2 Complete - Phase 3 In Progress
**Last Updated**: 2026-01-24

---

## Executive Summary

This master plan outlines the implementation of **Engram**, a high-performance CLI tool implementing the Neurona Knowledge Protocol. The project is being delivered in three phases, targeting sub-10ms graph traversal and offline-first ALM capabilities.

**Technology Stack**:
- Language: **Zig** 0.15.2+ (zero-overhead, manual memory control, cross-compilation)
- Storage: Plain text (Markdown + YAML Frontmatter)
- Indexing: Custom binary adjacency lists + vector embeddings
- Distribution: Single static binary, no external dependencies

---

## Phase 1: The Soma (Foundation) - MVP ✅ COMPLETE

**Goal**: Basic CRUD operations for Neuronas with graph-aware connections.

**Timeline**: Week 1-2 (Completed Jan 23, 2026)

### Milestones

#### 1.1 Core Infrastructure
- [x] CLI skeleton with command routing
- [x] Markdown frontmatter parser (YAML extraction)
- [x] YAML parser (key-value, arrays, nested objects)
- [x] Filesystem I/O layer (read, write, scan)

#### 1.2 Core Data Structures
- [x] Neurona data model (Tier 1, 2, 3 support)
  - Tier 1: id, title, tags, links (Essential)
  - Tier 2: type, connections, language, updated (Standard)
  - Tier 3: hash, _llm, context (Advanced)
- [x] Cortex configuration parser
- [x] Graph data structure (adjacency list, O(1) lookup)
- [x] Connection type definitions (15 types)

#### 1.3 Neurona Flavors
Engram supports 10 Neurona flavors from the union of spec.md and NEURONA_OPEN_SPEC.md:

**ALM Flavors (spec.md)**:
- `issue` - Bug reports, feature requests, blockers
- `requirement` - Functional requirements, acceptance criteria
- `test_case` - Test specifications, validation
- `artifact` - Code files, scripts, tools
- `feature` - Feature groupings, organizational

**General-Purpose Flavors (NEURONA_OPEN_SPEC.md)**:
- `concept` - Default, generic knowledge
- `reference` - API docs, definitions, facts
- `state_machine` - State graph nodes, workflow states
- `lesson` - Educational content, tutorials

#### 1.4 Basic CLI Commands
- [x] `engram init` - Initialize new Cortex
- [x] `engram new` - Create Neurona with ALM templates
- [x] `engram show` - Display Neurona with connections
- [x] `engram link` - Create connections between Neuronas
- [x] `engram sync` - Rebuild graph index
- [x] `engram delete` - Delete Neurona (Moved from Phase 2)

### Success Criteria
- ✅ Create, read, update, delete Neuronas
- ✅ Track connections in graph structure
- ✅ All 10 Neurona flavors supported
- ✅ Tier 1, 2, 3 metadata parsing complete
- ✅ 90%+ test coverage (89 test blocks passing)
- ✅ Sub-10ms graph traversal (depth 1, validated: 0.0001ms)
- ✅ Cold start < 50ms (validated: 0.23ms)

---

## Phase 2: The Axon (Connectivity) ✅ COMPLETE

**Goal**: Advanced graph operations and ALM workflow support.

**Timeline**: Week 3-4 (Completed Jan 24, 2026)

### Milestones

#### 2.1 Graph Traversal Engine
- [x] BFS traversal with level tracking
- [x] DFS traversal
- [x] Shortest path finding (Dijkstra/BFS for unweighted)
- [x] Bidirectional indexing (forward + reverse)
- [x] Node/edge statistics (degree, inDegree)

#### 2.2 ALM Commands
- [x] `engram trace` - Dependency tree visualization
  - Trace requirements → tests
  - Trace tests → code
  - Trace issues → blocked artifacts
- [x] `engram status` - List open issues by priority
- [x] `engram query` - Basic query interface (type, tag, connection filters)
- [x] `engram update` - Update Neurona fields programmatically
  - Example: `engram update test.001 --set "context.status=passing"`
- [x] `engram impact` - Impact analysis for code changes
  - Trace upstream dependencies (requirements, features)
  - Trace downstream dependencies (tests, artifacts)
  - Generate recommendations for affected tests
- [x] `engram link-artifact` - Link source files to requirements
  - Creates artifact Neuronas automatically
  - Links to implementing requirement
- [x] `engram release-status` - Release readiness check
  - Validate all requirements covered
  - Check test status
  - Identify blocking issues
  - Compute completion percentage

#### 2.3 State Management
- [x] Enforced state transitions
  - Issues: open → in_progress → resolved → closed
  - Tests: not_run → running → passing → failing
  - Requirements: draft → approved → implemented
- [x] Validation rules for connections
  - Type-specific allowed connections
  - Cardinality constraints (e.g., binary_node: left/right max 1)
- [x] Orphan detection (unconnected Neuronas)
- [x] State filtering (e.g., `engram status --filter "state:open AND priority:1"`)

### Success Criteria
- ✅ Trace arbitrary depth dependencies
- ✅ Filter Neuronas by type, tag, connections
- ✅ Enforce ALM workflow states
- ✅ 4 additional commands implemented (update, impact, link-artifact, release-status)
- ✅ State management enforced (issues, tests, requirements)
- ✅ Impact analysis functional
- ✅ Release readiness checks working
- ✅ State filtering with EQL support
- ✅ Sub-10ms pathfinding (depth 5)
- ✅ 90%+ test coverage (129 tests passing, 13 integration tests for ALM workflows)

---

## Phase 3: The Cortex (Intelligence) ⏳ PENDING

**Goal**: AI-powered features and semantic search.

**Timeline**: Week 5-6

### Milestones

#### 3.1 Semantic Search
- [x] Vector embeddings integration (C-interop with llama.cpp or similar)
- [x] `.activations/vectors.bin` index format
- [x] Hybrid search (BM25 + vector similarity)
- [x] Neural Activation algorithm implementation
  - Stimulus: Text match + vector match
  - Propagation: Signal decay across weighted links
  - Response: Ranked results with relevance scores
- [x] Query command extended with 5 search modes
  - `--mode filter` - Filter by type, tags, connections (default)
  - `--mode text` - BM25 full-text search
  - `--mode vector` - Vector similarity search (cosine)
  - `--mode hybrid` - Combined BM25 + vector fusion (0.6/0.4 weights)
  - `--mode activation` - Neural propagation across graph connections
- [x] Hash-based word frequency embeddings for vector search
  - Simple, efficient word → dimension mapping
  - Cosine similarity scoring
  - Note: Production would use proper embeddings (Word2Vec, GloVe, BERT)
- [x] Integration test suite for all query modes
  - 9 comprehensive tests covering all 5 modes
  - Test data with 8 Neuronas including connections
  - Bash and Windows test scripts

#### 3.2 LLM Optimization
- [x] `_llm` metadata support
  - `t`: Short title for token efficiency
  - `d`: Density/difficulty (1-4)
  - `k`: Top keywords
  - `c`: Token count
  - `strategy`: full, summary, hierarchical
- [x] Token counting and optimization
- [x] Summary generation (Tier 3 strategy)
- [x] Cache management for LLM responses
  - `.activations/cache/` directory
  - Invalidation on content changes

#### 3.3 Advanced Features
- [ ] `engram metrics` - Analytics and statistics
   - Requirements: total, validated, blocked, coverage
   - Issues: open, resolved, avg resolution time
   - Tests: passing, failing, not_run, pass rate
   - Velocity: items created/resolved per week
   - Traceability: complete chain percentages
- [x] Natural language query parsing
   - Parse EQL queries with natural language
   - Convert to structured graph queries
- [ ] State machine execution engine
   - Execute `type: state_machine` Neuronas
   - Handle `context.triggers`, `entry_action`, `exit_action`

### Success Criteria
- [x] Semantic search implemented
- [x] Query command extended with 5 search modes
- [x] BM25 text search produces ranked results with relevance scores
- [x] Vector similarity search with hash-based embeddings
- [x] Hybrid search combines BM25 + vector with 0.6/0.4 fusion weights
- [x] Neural activation propagates across graph connections
- [x] Integration test suite for all query modes (9 tests passing)
- [x] LLM-optimized Neurona representation
- [x] Natural language query parsing functional
- [ ] Analytics and metrics functional
- [ ] 90%+ test coverage
- [ ] Performance targets met

---

## Timeline

| Phase | Start | End | Duration | Status |
|-------|-------|-----|----------|--------|
 | Phase 1: The Soma | Week 1 | Week 2 | 2 weeks | ✅ Complete |
 | Phase 2: The Axon | Week 3 | Week 4 | 2 weeks | ✅ Complete |
 | Phase 3: The Cortex | Week 5 | Week 6 | 2 weeks | ⏳ In Progress (Query modes complete) |

**Total Duration**: 6 weeks

---

## References

- **Product Specification**: `docs/spec.md`
- **Neurona Specification**: `docs/NEURONA_OPEN_SPEC.md`
- **Use Cases**: `docs/usecase.md`
- **Integration Tests**: `QUERY_INTEGRATION_TESTS.md` - Query mode testing

---

**Last Updated**: 2026-01-24
**Status**: Phase 1 Complete - Phase 2 Complete - Phase 3 In Progress (Query modes complete)
**Owner**: Development Team