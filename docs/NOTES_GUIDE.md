# Engram Notes System Guide

**Version**: 1.0.0  
**Last Updated**: February 15, 2026

---

## Overview

Engram's Notes System extends the ALM (Application Lifecycle Management) platform with a powerful knowledge management system. It enables you to create interconnected notes, track learning progress, and build a personal knowledge graph.

### Key Features

- **Three Note Types**: Concept, Reference, and Lesson notes with specialized metadata
- **Five Connection Types**: builds_on, contradicts, cites, example_of, proves
- **Wikilink Support**: Easy linking with `[[link]]` syntax
- **Daily Notes**: Automatic daily journaling with date-based linking
- **Knowledge Graph**: Automatic connection tracking and visualization

---

## Note Types

### 1. Concept Notes

Concept notes are the building blocks of your knowledge base. They represent fundamental ideas, definitions, and abstractions.

**Use Cases**:
- Define terminology and concepts
- Document theoretical frameworks
- Capture abstract ideas
- Explain principles and laws

**Context Fields**:
```yaml
context:
  definition: "Clear definition of the concept"
  difficulty: 3  # 1-5 scale
  examples: ["Example 1", "Example 2"]
```

**Example**:
```yaml
---
id: recursion
title: Recursion
type: concept
tags: [programming, algorithm]
context:
  definition: "A programming technique where a function calls itself"
  difficulty: 4
  examples: ["factorial", "tree traversal"]
updated: "2026-02-15T00:00:00Z"
language: en
---

# Recursion

Recursion is a method of solving a problem where the solution depends on solutions to smaller instances of the same problem.

## Examples

### Factorial
```
factorial(n) = n * factorial(n-1)
```

### Tree Traversal
Recursion is natural for traversing tree structures.
```

---

### 2. Reference Notes

Reference notes capture information from external sources such as books, articles, papers, or websites.

**Use Cases**:
- Cite research papers
- Document book summaries
- Track website resources
- Record video or podcast references

**Context Fields**:
```yaml
context:
  source: "Source name or title"
  url: "https://example.com"  # optional
  author: "Author name"  # optional
  citation: "Full citation"  # optional
```

**Example**:
```yaml
---
id: ref.clean-code
title: Clean Code: A Handbook of Agile Software Craftsmanship
type: reference
tags: [book, software-engineering]
context:
  source: "Clean Code: A Handbook of Agile Software Craftsmanship"
  author: "Robert C. Martin"
  citation: "Martin, R. C. (2008). Clean Code. Prentice Hall."
updated: "2026-02-15T00:00:00Z"
language: en
---

# Clean Code

A comprehensive guide to writing maintainable, readable, and efficient code.

## Key Principles

1. **Meaningful Names**: Names should reveal intent
2. **Functions Should Be Small**: Do one thing well
3. **DRY**: Don't Repeat Yourself
4. **Comments**: Explain why, not what

## Notable Quotes

> "Clean code is simple and direct. Clean code reads like well-written prose." - Robert C. Martin
```

---

### 3. Lesson Notes

Lesson notes document learning experiences, educational content, or skills acquired.

**Use Cases**:
- Track completed courses or tutorials
- Document learning objectives and outcomes
- Record key takeaways from sessions
- Plan future learning goals

**Context Fields**:
```yaml
context:
  learning_objectives: "What you aim to learn"
  prerequisites: "Required prior knowledge"
  key_takeaways: ["Point 1", "Point 2"]
  difficulty: 2  # 1-5 scale
  estimated_time: "2 hours"  # optional
```

**Example**:
```yaml
---
id: lesson.zig-pointers
title: Understanding Zig Pointers
type: lesson
tags: [zig, learning, programming]
context:
  learning_objectives: "Master pointer concepts in Zig"
  prerequisites: "Basic Zig syntax"
  key_takeaways: [
    "Pointers are explicit in Zig",
    "Use & for address-of operator",
    "Use * for dereference operator"
  ]
  difficulty: 3
  estimated_time: "3 hours"
updated: "2026-02-15T00:00:00Z"
language: en
---

# Understanding Zig Pointers

## Learning Objectives

By the end of this lesson, you should be able to:
- Declare and use pointers in Zig
- Pass pointers to functions
- Understand memory safety concepts

## Prerequisites

- Basic Zig syntax
- Understanding of memory concepts

## Key Takeaways

1. Pointers are explicit in Zig - no automatic dereferencing
2. Use `&` to get address of a variable
3. Use `*` to access value at pointer address
4. Zig's safety features prevent common pointer errors

## Practice Exercise

Create a function that swaps two values using pointers.
```

---

## Connection Types

Engram provides five connection types specifically for notes:

### 1. builds_on

Indicates that this note extends or develops another concept.

**Example**: "Advanced Algorithms" builds_on "Basic Algorithms"

**Usage**:
```bash
engram link advanced-algorithms basic-algorithms --type builds_on
```

### 2. contradicts

Notes that oppose or conflict with another view or concept.

**Example**: "Declarative Programming" contradicts "Imperative Programming"

**Usage**:
```bash
engram link declarative imperative --type contradicts
```

### 3. cites

References an external source or another note.

**Example**: "My Notes on Clean Code" cites "ref.clean-code"

**Usage**:
```bash
engram link my-notes ref.clean-code --type cites
```

### 4. example_of

This note is a concrete example of an abstract concept.

**Example**: "Binary Search Implementation" example_of "Binary Search"

**Usage**:
```bash
engram link binary-search-impl binary-search --type example_of
```

### 5. proves

This note demonstrates or validates another concept or theory.

**Example**: "Proof by Induction Example" proves "Mathematical Induction"

**Usage**:
```bash
engram link induction-proof induction --type proves
```

---

## Wikilink System

Wikilinks provide a quick way to create links between notes using `[[link]]` syntax.

### Syntax

**Simple Link**:
```markdown
This connects to [[concept]].
```

**Link with Display Text**:
```markdown
See [[concept|Concept A]] for details.
```

### Conversion to Markdown

When rendered, wikilinks are automatically converted to markdown links:

```markdown
[[concept]] → [concept](#concept)
[[concept|Concept A]] → [Concept A](#concept)
```

### Extracting Connections

The wikilink parser can extract connection suggestions from your text:

```bash
engram extract-connections my-note.md
```

This analyzes `[[link]]` syntax and suggests appropriate connections.

### Counting Wikilinks

Check how many wikilinks are in a note:

```bash
engram count-wikilinks my-note.md
```

---

## Daily Notes

Daily notes provide a structured journaling experience with automatic date-based linking.

### Creating Today's Daily Note

```bash
engram daily
```

### Creating a Specific Date

```bash
engram daily --date 2026-02-15
```

### Custom Title

```bash
engram daily --title "February 15, 2026"
```

### Features

- **Automatic Adjacent Linking**: Links to previous/next day's notes if they exist
- **Bidirectional Links**: Creates reverse connections automatically
- **Structured Template**: Includes sections for Tasks, Notes, Ideas, and References
- **Date Validation**: Ensures valid dates (leap years, month lengths)

### Daily Note Template

```markdown
# YYYY-MM-DD

## Tasks
- [ ] Task 1
- [ ] Task 2

## Notes
Write your daily notes here.

## Ideas
Capture ideas and insights here.

## References
* [[Previous Note]]
* [[Next Note]]
```

---

## Workflow Examples

### Example 1: Building a Knowledge Base

1. **Create Concept Notes**:
   ```bash
   engram new concept "Recursion" \
     --context.definition "Function that calls itself" \
     --context.difficulty 4
   ```

2. **Add Examples**:
   ```bash
   engram update recursion \
     --set context.examples='["factorial", "tree traversal"]'
   ```

3. **Create Related Concepts**:
   ```bash
   engram new concept "Iteration"
   ```

4. **Link Concepts**:
   ```bash
   engram link iteration recursion --type contradicts
   ```

### Example 2: Research Notes

1. **Create Reference Note**:
   ```bash
   engram new reference "Clean Code Book" \
     --context.source "Clean Code" \
     --context.author "Robert C. Martin"
   ```

2. **Create Lesson Note**:
   ```bash
   engram new lesson "Learning Clean Code Principles" \
     --context.learning_objectives "Master clean code principles" \
     --context.difficulty 3
   ```

3. **Link to Reference**:
   ```bash
   engram link lesson-clean ref.clean-code --type cites
   ```

### Example 3: Daily Journaling

1. **Create Daily Note**:
   ```bash
   engram daily
   ```

2. **Use Wikilinks**:
   ```markdown
   Today I learned about [[recursion]].
   Practiced [[binary-search]] implementation.
   ```

3. **Auto-Generate Connections**:
   ```bash
   engram update 2026-02-15 --process-wikilinks
   ```

---

## Best Practices

### 1. Use Consistent Naming

- Use lowercase with hyphens for IDs
- Be descriptive but concise
- Example: `clean-code-principles`, `zig-pointer-basics`

### 2. Choose Appropriate Connection Types

- Use `builds_on` for extending concepts
- Use `contradicts` for opposing views
- Use `cites` for referencing sources
- Use `example_of` for concrete instances
- Use `proves` for demonstrations/proofs

### 3. Leverage Wikilinks

- Use `[[link]]` for quick inline references
- Use `[[link|Display Text]]` for better readability
- Let the system auto-generate connections

### 4. Structured Learning

- Create **Concept** notes for ideas
- Create **Reference** notes for sources
- Create **Lesson** notes for learning experiences
- Connect them appropriately

### 5. Regular Review

- Use `engram query "type:concept AND context.difficulty:gt:3"` to find complex concepts
- Review daily notes weekly
- Update connections as your understanding grows

---

## Query Examples

### Find All Notes

```bash
engram query "type:concept OR type:reference OR type:lesson"
```

### Find High-Difficulty Concepts

```bash
engram query "type:concept AND context.difficulty:gt:3"
```

### Find Citations

```bash
engram query "link(cites, type:reference)"
```

### Find Build Chains

```bash
engram trace some-concept --type builds_on --depth 5
```

---

## Integration with ALM Features

### Notes and Requirements

Connect notes to requirements for context:

```bash
engram link req.auth.001 lesson.auth-concepts --type cites
```

### Notes and Issues

Document issues with notes:

```bash
engram link issue.001 ref.bug-pattern --type cites
```

### Notes and Tests

Link lessons to test cases:

```bash
engram link test.auth.001 lesson.auth-testing --type validates
```

---

## Tips and Tricks

1. **Batch Creation**: Use scripts to create multiple related notes
2. **Template Notes**: Create a note as a template, then copy it
3. **Tag Consistency**: Use tags like `[learning]`, `[reference]`, `[concept]`
4. **Weight Management**: Use higher weights (90-100) for strong connections
5. **Regular Sync**: Run `engram sync` to update the knowledge graph

---

## Troubleshooting

### Daily Note Already Exists

If you try to create a daily note that already exists:

```bash
engram daily --date 2026-02-15
# Warning: Daily note already exists for 2026-02-15
# Info: To edit existing note, run: engram show 2026-02-15
```

### Invalid Date Format

Ensure dates are in `YYYY-MM-DD` format:

```bash
# Correct
engram daily --date 2026-02-15

# Incorrect
engram daily --date 02/15/2026
engram daily --date 2026/02/15
```

### Connection Type Not Found

Use the exact connection type name:

```bash
# Correct
engram link a b --type builds_on

# Incorrect
engram link a b --type buildsOn
engram link a b --type builds-on
```

---

## API Reference

### Creating Notes

```bash
engram new <type> <title> [options]

Types:
- concept      - Building block of knowledge
- reference    - External source
- lesson       - Learning experience

Options:
  --context.definition <text>       (concept)
  --context.difficulty <1-5>       (concept, lesson)
  --context.examples <list>         (concept)
  --context.source <text>           (reference)
  --context.url <text>              (reference)
  --context.author <text>           (reference)
  --context.citation <text>         (reference)
  --context.learning_objectives <text> (lesson)
  --context.prerequisites <text>     (lesson)
  --context.estimated_time <text>    (lesson)
```

### Daily Notes

```bash
engram daily [options]

Options:
  --date <YYYY-MM-DD>    Specific date (default: today)
  --title <text>          Custom title
  --no-bidirectional      Skip reverse links
  --verbose               Show details
  --cortex <path>         Cortex directory
```

### Linking Notes

```bash
engram link <source> <target> --type <connection_type> [options]

Connection Types:
  builds_on      - Extends another concept
  contradicts    - Opposes another view
  cites          - References external source
  example_of     - Concrete example
  proves         - Demonstrates/validates

Options:
  --weight <1-100>  Connection weight (default: 50)
  --bidirectional     Create reverse link
```

---

## Future Enhancements

Planned features for future versions:

- [ ] Graph visualization UI for knowledge graphs
- [ ] Advanced connection type inference
- [ ] Automatic difficulty calculation
- [ ] Learning progress tracking
- [ ] Spaced repetition suggestions
- [ ] Multi-language support
- [ ] Export to other note systems (Obsidian, Roam)
- [ ] Mobile app support

---

## Contributing

Contributions to the Notes System are welcome! Areas of contribution:

- New connection types
- Improved wikilink parsing
- Better templates
- Additional metadata fields
- Documentation improvements

See `AGENTS.md` for development guidelines.

---

## License

Part of the Engram ALM System. See LICENSE for details.