# Engram CLI Master Plan

**Version**: 1.0.0
**Status**: Phase 1 Complete - Phase 2 Complete - Phase 3 Pending
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
- [ ] Vector embeddings integration (C-interop with llama.cpp or similar)
- [ ] `.activations/vectors.bin` index format
- [ ] Hybrid search (BM25 + vector similarity)
- [ ] Neural Activation algorithm implementation
  - Stimulus: Text match + vector match
  - Propagation: Signal decay across weighted links
  - Response: Ranked results with relevance scores

#### 3.2 LLM Optimization
- [ ] `_llm` metadata support
  - `t`: Short title for token efficiency
  - `d`: Density/difficulty (1-4)
  - `k`: Top keywords
  - `c`: Token count
  - `strategy`: full, summary, hierarchical
- [ ] Token counting and optimization
- [ ] Summary generation (Tier 3 strategy)
- [ ] Cache management for LLM responses
  - `.activations/cache/` directory
  - Invalidation on content changes

#### 3.3 Advanced Features
- [ ] `engram run` - Execute code artifacts (sandboxed)
  - Validate `context.safe_to_exec: true`
  - Spawn subprocess with timeout
  - Capture output for logging
- [ ] `engram metrics` - Analytics and statistics
  - Requirements: total, validated, blocked, coverage
  - Issues: open, resolved, avg resolution time
  - Tests: passing, failing, not_run, pass rate
  - Velocity: items created/resolved per week
  - Traceability: complete chain percentages
- [ ] Natural language query parsing
  - Parse EQL queries with natural language
  - Convert to structured graph queries
- [ ] State machine execution engine
  - Execute `type: state_machine` Neuronas
  - Handle `context.triggers`, `entry_action`, `exit_action`

### Success Criteria
- [ ] Semantic search over 10K Neuronas < 50ms
- [ ] Neural Activation algorithm complete
- [ ] LLM-optimized Neurona representation
- [ ] Safe code artifact execution
- [ ] Analytics and metrics functional
- [ ] 90%+ test coverage

---

## Architecture

### Application Directory Structure

```
Engram/                                 # Repository root
├── docs/                               # Documentation
│   ├── spec.md                         # Product specification
│   ├── NEURONA_OPEN_SPEC.md            # Neurona specification
│   ├── PLAN.md                         # This master plan
│   └── usecase.md                      # Use cases
│
├── src/                                # Source code
│   ├── main.zig                        # CLI entry point
│   ├── root.zig                        # Library exports
│   │
│   ├── cli/                            # Command implementations
│   │   ├── init.zig                   # Initialize Cortex
│   │   ├── new.zig                    # Create Neurona
│   │   ├── show.zig                   # Display Neurona
│   │   ├── link.zig                   # Create connection
│   │   ├── sync.zig                   # Rebuild index
│   │   ├── delete.zig                 # Delete Neurona
│   │   ├── trace.zig                  # Trace dependencies
│   │   ├── status.zig                 # List status
│   │   ├── query.zig                  # Query interface
│   │   ├── update.zig                 # Phase 2: Update fields
│   │   ├── impact.zig                 # Phase 2: Impact analysis
│   │   ├── link_artifact.zig          # Phase 2: Link artifacts
│   │   ├── release_status.zig         # Phase 2: Release readiness
│   │   ├── metrics.zig                # Phase 3: Analytics
│   │   └── run.zig                    # Phase 3: Execute artifacts
│   │
│   ├── core/                           # Core data structures
│   │   ├── neurona.zig                # Neurona data model
│   │   ├── cortex.zig                 # Cortex configuration
│   │   ├── graph.zig                  # Graph data structure
│   │   └── activation.zig             # Phase 3: Neural activation
│   │
│   ├── storage/                        # Persistence layer
│   │   ├── filesystem.zig             # File I/O operations
│   │   ├── index.zig                  # Index management
│   │   └── tfidf.zig                  # Phase 3: BM25 search
│   │
│   └── utils/                          # Utilities
│       ├── id_generator.zig            # ID generation
│       ├── timestamp.zig               # ISO 8601 timestamps
│       ├── editor.zig                  # Cross-platform editor
│       ├── frontmatter.zig             # Frontmatter extraction
│       └── yaml.zig                    # YAML parser
│
├── tests/                              # Tests
│   ├── unit/                         # Unit tests
│   ├── integration/                  # Integration tests
│   └── fixtures/                      # Test fixtures
│       └── sample_cortex/            # Sample cortex data
│
└── build.zig                          # Build configuration
```

### Cortex Directory Structure (Generated by CLI)

Per NEURONA_OPEN_SPEC.md, the CLI creates and manages this structure:

```
my_cortex/                             # Cortex root
│
├── cortex.json                        # DNA: Identity & capabilities
├── README.md                          # Human readable overview
│
├── neuronas/                          # Soma: User-created Neuronas
│   ├── logic.modal.md
│   ├── math.set.md
│   ├── req.auth.oauth2.md
│   ├── test.auth.oauth2.001.md
│   └── issue.auth.001.md
│
├── .activations/                      # Memory: System-generated indices (Git-ignored)
│   ├── graph.idx                      # Adjacency list (O(1) traversal)
│   ├── vectors.bin                    # Embeddings (Semantic search)
│   └── cache/                         # Computed LLM summaries / Activation states
│
└── assets/                            # Matter: Static binary files
    ├── diagrams/
    └── pdfs/
```

---

## Component Dependencies

### Phase 1 Dependencies
```
utils/yaml.zig → utils/frontmatter.zig → core/neurona.zig
utils/id_generator.zig → cli/new.zig
utils/timestamp.zig → core/neurona.zig, cli/new.zig
utils/editor.zig → cli/new.zig
core/neurona.zig → cli/new.zig, storage/filesystem.zig
core/cortex.zig → cli/init.zig
core/graph.zig → cli/sync.zig
storage/filesystem.zig → cli/show.zig, cli/sync.zig
```

### Phase 2 Dependencies
```
core/graph.zig → cli/trace.zig, cli/status.zig, cli/impact.zig
storage/index.zig → cli/query.zig, cli/status.zig, cli/release_status.zig
core/neurona.zig → cli/update.zig
storage/filesystem.zig → cli/link_artifact.zig
```

### Phase 3 Dependencies
```
core/activation.zig → cli/query.zig, cli/metrics.zig
storage/tfidf.zig → cli/query.zig
```

---

## Testing Strategy

### Target Coverage: 90%+

### Unit Tests
- Each module has comprehensive unit tests
- Test edge cases, error conditions
- Test memory safety (Zig's leak detection)
- Test Tier 1, 2, 3 parsing compliance
- Test all 10 Neurona flavor validation

### Integration Tests
- End-to-end command workflows
- Multi-step ALM scenarios (usecase.md flows)
- Graph traversal correctness
- State transition enforcement
- Cross-platform filesystem behavior

### Performance Tests
- Cold start time (< 50ms)
- Graph traversal (O(1) depth 1, < 10ms depth 5)
- Index build (10K files < 1s)
- Search (10K Neuronas < 50ms)
- Impact analysis performance (< 50ms)

---

## Platform Support

### Primary
- Windows (x86_64) - Development platform

### Secondary
- Linux (x86_64)
- macOS (Apple Silicon)
- macOS (Intel)

### Cross-Compilation
All builds use Zig's native cross-compilation:
```bash
zig build -Dtarget=x86_64-windows
zig build -Dtarget=x86_64-linux
zig build -Dtarget=aarch64-macos
```

---

## Performance Targets

### Phase 1 (The Soma)
- **Cold Start**: Load cortex.json in < 50ms
- **File Read**: Single Neurona < 10ms
- **Graph Traversal**: Depth 1 (adjacent nodes) in < 5ms (O(1))
- **Index Build**: 100 files < 100ms

### Phase 2 (The Axon)
- **Pathfinding**: Shortest path (depth 5) < 10ms
- **Directory Scan**: 10K files < 500ms
- **Query**: Filter + sort 10K Neuronas < 20ms
- **Impact Analysis**: Full trace in < 50ms

### Phase 3 (The Cortex)
- **Neural Activation**: Full propagation 10K Neuronas < 50ms
- **Semantic Search**: Vector similarity query < 50ms
- **LLM Summary**: Generate cached summary < 200ms

---

## Risk Mitigation

### Technical Risks

1. **Zig Language Maturity**
   - Risk: Zig is in active development, API changes
   - Mitigation: Pin Zig version (0.15.2+), document workarounds

2. **Memory Management**
   - Risk: Manual allocator management can cause leaks
   - Mitigation: Extensive testing, Zig's leak detection, strict code review

3. **Cross-Platform I/O**
   - Risk: Filesystem behavior differs between Windows/Unix
   - Mitigation: Use Zig's std.fs.Path abstraction, test on all platforms

4. **Graph Algorithm Complexity**
   - Risk: Complex algorithms (shortest path, activation) may be slow
   - Mitigation: Pre-computed indices, benchmark early, optimize hot paths

5. **Neurona Flavor Complexity**
   - Risk: Supporting 10 flavors with different validation rules may increase complexity
   - Mitigation: Use trait-based design, shared validation logic, extensive fixtures

6. **Command Proliferation**
   - Risk: Many commands (12+) may be overwhelming to users
   - Mitigation: Consistent CLI syntax, `--help` documentation, grouped options

### Project Risks

1. **Scope Creep**
   - Risk: Adding too many features before MVP
   - Mitigation: Strict phase boundaries, defer Phase 3 features

2. **Test Coverage**
   - Risk: Complex graph logic and state transitions hard to test
   - Mitigation: Property-based testing, comprehensive fixtures, scenario tests

---

## Success Criteria

### Phase 1: The Soma ✅ COMPLETE
- [x] All CRUD operations working
- [x] Graph structure persisted
- [x] 5 CLI commands implemented (init, new, show, link, sync)
- [x] All 10 Neurona flavors supported
- [x] Tier 1, 2, 3 metadata parsing complete
- [x] 90%+ test coverage
- [x] Performance targets met

### Phase 2: The Axon ✅ COMPLETE
- [x] All CRUD operations working
- [x] Graph structure persisted
- [x] 9 additional CLI commands implemented (delete, trace, status, query, update, impact, link-artifact, release-status)
- [x] All 10 Neurona flavors supported
- [x] Tier 1, 2, 3 metadata parsing complete
- [x] 90%+ test coverage (129 total tests passing, 13 integration tests)
- [x] Performance targets met (sub-10ms pathfinding)
- [x] Graph traversal engine complete
- [x] ALM workflow support (trace, status, query)
- [x] 4 additional commands implemented (update, impact, link-artifact, release-status)
- [x] State management enforced (issues, tests, requirements)
- [x] Impact analysis functional
- [x] Release readiness checks working
- [x] Sub-10ms pathfinding (depth 5)
- [x] 90%+ test coverage (Phase 2 features)
- [x] Performance targets met

### Phase 3: The Cortex ⏳ PENDING
- [ ] Semantic search implemented
- [ ] LLM optimization complete
- [ ] Code execution sandboxed
- [ ] Analytics and metrics functional
- [ ] Neural Activation algorithm working
- [ ] 90%+ test coverage
- [ ] Performance targets met

---

## Timeline

| Phase | Start | End | Duration | Status |
|-------|-------|-----|----------|--------|
| Phase 1: The Soma | Week 1 | Week 2 | 2 weeks | ✅ Complete |
| Phase 2: The Axon | Week 3 | Week 4 | 2 weeks | ✅ Complete |
| Phase 3: The Cortex | Week 5 | Week 6 | 2 weeks | ⏳ Pending |

**Total Duration**: 6 weeks

---

## References

- **Product Specification**: `docs/spec.md`
- **Neurona Specification**: `docs/NEURONA_OPEN_SPEC.md`
- **Use Cases**: `docs/usecase.md`

---

**Last Updated**: 2026-01-24
**Status**: Phase 1 Complete - Phase 2 Complete - Phase 3 Pending
**Owner**: Development Team