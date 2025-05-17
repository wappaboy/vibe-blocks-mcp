# AI Agent Internal Guidelines for Vibe Blocks MCP

This document contains specific guidelines for AI assistants working on the Vibe Blocks MCP project. It compiles feedback and instructions from the project maintainer to ensure consistency across different sessions.

## General Approach

- **Focus on immediate needs**: Solve the specific problem the user presents rather than trying to fix everything at once
- **Understand before changing**: Analyze code thoroughly before making modifications
- **Minimize scope**: Make the smallest change necessary to solve a problem
- **Be consistent**: Follow existing code patterns and conventions

## Communication Guidelines

- **Write comments in English**: All code comments, log messages, and documentation should be in English
- **Be direct**: Provide concise, straightforward answers
- **Explain rationale**: When making changes, briefly explain your reasoning
- **Show examples**: When applicable, provide examples of how to use modified functionality

## Code Modification Rules

- **No new dependencies without approval**: Do not add new packages without explicit user consent
- **Maintain backward compatibility**: Ensure changes don't break existing functionality
- **Respect project structure**: Follow established patterns in the codebase
- **Don't make assumptions**: Ask for clarification rather than guessing intent
- **Document potential impacts**: If a change might affect other parts of the system, note this

## Testing and Execution

- **Let the user handle execution**: Do not attempt to start servers or execute test code
- **Leave system operations to the user**: Avoid operations that interact with the user's system
- **Provide clear verification steps**: Explain how the user can verify changes work correctly

## Language-Specific Guidelines

### Python
- Follow PEP 8 style guidelines
- Use type hints consistently
- Handle errors gracefully and provide informative messages
- For API parameters, support both direct data structures and their JSON string representations

### Lua (Roblox)
- Follow Roblox Lua style guidelines
- Use meaningful variable names
- Avoid globals where possible
- Prefer local functions when appropriate

## Previously Addressed Issues

1. **Parameter Type Flexibility**
   - Modified functions to accept both JSON strings and direct data structures
   - Used conditional type checking and parsing
   - Added clear documentation for both usage patterns
   - Functions modified:
     - `move_instance`: Accepts both dictionary and JSON string for position parameter
     - `set_property`: Accepts any data type with special handling for strings
     - `spawn_npc`: Accepts list, dictionary, or JSON string for position parameter
     - `set_environment`: Accepts dictionary or JSON string for properties parameter
     - `teleport_player_via_cloud`: Accepts dictionary or JSON string for teleport_options
     - `modify_children`: Accepts any data type with JSON parsing for strings
     - `set_datastore_value_in_cloud`: Added JSON string parsing for value parameter

2. **Error Handling Improvements**
   - Enhanced error messages to be more descriptive
   - Added graceful fallbacks when appropriate

## Improvement Tracking

When implementing a significant improvement, add it to this section and the Examples section in CONTRIBUTING.md to track knowledge across sessions.

---

*Last updated: May 2024* 