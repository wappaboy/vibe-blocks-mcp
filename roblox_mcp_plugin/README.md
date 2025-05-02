# Vibe Blocks MCP Companion Plugin

This is the companion Roblox Studio plugin for the Vibe Blocks MCP project. The plugin enables direct communication between the Python backend server and Roblox Studio, allowing for real-time interaction with the Studio environment.

## File Structure

- `default.project.json` - Rojo project configuration file (specifies the project name `VibeBlocksMCP_Companion`)
- `src/Plugin.server.lua` - Main plugin script containing all command handlers

## Building the Plugin

### Prerequisites

1. [Rojo](https://rojo.space/) - Install Rojo 7.0 or later
   - Rojo is a build system that bridges the gap between Roblox Studio and external code editors

### Build Instructions

1. **Using Command Line**:
   ```bash
   # Navigate to this plugin directory (roblox_mcp_plugin)
   cd roblox_mcp_plugin
   
   # Build the plugin (.rbxm file)
   rojo build default.project.json -o VibeBlocksMCP_Companion.rbxm
   ```

2. **Using Rojo VSCode Extension**:
   - Open this plugin folder in VSCode
   - Right-click on `default.project.json`
   - Select "Rojo: Build" from the context menu
   - Choose a location to save the output file (name it `VibeBlocksMCP_Companion.rbxm`)

### Installing the Plugin in Roblox Studio

1. In Roblox Studio, go to the "Plugins" tab
2. Click on "Plugins Folder" button
3. Copy the built `VibeBlocksMCP_Companion.rbxm` file to this folder
4. Restart Roblox Studio
5. The plugin should now appear in your Plugins tab

## Development and Modification

When developing or modifying the plugin:

1. Make your changes to the `Plugin.server.lua` file
2. Rebuild the plugin using the instructions above (outputting `VibeBlocksMCP_Companion.rbxm`)
3. If using Rojo's live sync feature for development:
   ```bash
   rojo serve default.project.json
   ```
   Then connect to the Rojo server from within Studio using the Rojo plugin.

## Output File Naming

For consistency, always name the output file `VibeBlocksMCP_Companion.rbxm` when building the plugin. This matches the project name defined in `default.project.json`.

## Plugin Functionality

This plugin enables communication with the Vibe Blocks MCP server and implements handlers for various commands including:

- Instance creation, deletion, and property manipulation
- Script management (create, edit, delete)
- Environment settings
- Animation playback
- NPC spawning
- Studio log forwarding
- Execution of Luau code within Studio

See the main project's `README.md` file for details on all supported commands. 