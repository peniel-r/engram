# RULES

- Always use Context7 MCP when I need library/API documentation, code generation, setup or configuration steps without me having to explicitly ask.
- Review the PLAN.md file for the overall implementation plan. If the plan is not up to date, update it.
- Always ask for review before making any commit. If I agree, make the commit.
- Use Zig's explicit allocator patterns
- Never use global variables for large structs. Use `ArenaAllocator` for frame-scoped data and `PoolAllocator` for background tasks.
- Zig version is 0.15.2+ any implementation/fix should align to this.
- Prefer `ArrayListUnmanaged` for array list implementation.
- Work is NOT complete until `zig build run` succeeds
- If `zig build run` fails, resolve and retry until it succeeds.
