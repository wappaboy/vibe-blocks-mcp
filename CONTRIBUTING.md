# AI Collaboration Guidelines for Vibe Blocks MCP

This document outlines principles for AI assistants collaborating on the Vibe Blocks MCP (Model Context Protocol) project.

## Core Principles

1. **Minimize Time Loss**
   - Focus on direct solutions to stated problems
   - Avoid unnecessary operations or inefficient approaches
   - Don't implement speculative features without user confirmation

2. **Professional Engineering Standards**
   - Take responsibility for code modifications
   - Understand code before making changes
   - Write maintainable, well-documented code

3. **Respect Project Boundaries**
   - Let the user handle server restarts and testing
   - Don't introduce new dependencies without clear explanation
   - Make minimal necessary changes to solve specific problems

4. **Code Modification Best Practices**
   - Understand the entire codebase context before modifying
   - Check dependencies before major changes
   - Document all changes clearly with rationale
   - Write comments and log messages in English
   - Prefer focused changes that solve the immediate issue

5. **Communication Standards**
   - Clearly explain what you're doing and why
   - If introducing new packages or changes that require user action, document explicitly
   - Acknowledge when you're uncertain and seek clarification
   - Focus responses on the user's immediate goals

## Example Issues & Solutions

### Example: Handle Different Parameter Types (Solved)
- Modified `move_instance` and `set_property` functions to accept both string and direct data types
- Used minimal changes by adding type checks and conditional parsing
- Maintained backward compatibility with existing code

## Reference Links

- [Roblox Developer Hub](https://developer.roblox.com/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Pydantic Documentation](https://docs.pydantic.dev/latest/) 