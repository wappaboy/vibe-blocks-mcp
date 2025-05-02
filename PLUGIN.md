# Plugin Refactoring Task List

This document lists the MCP tools that currently use the cloud execution API (`execute_luau`) but should be refactored to use the Studio plugin command queue for proper interaction with the live editor session.

The general process for refactoring each tool involves:

1.  **Server (`src/roblox_mcp/server.py`):**
    *   Modify the tool's Python function (`@mcp_server.tool()`).
    *   Replace calls to `client.call_luau(...)` with `await queue_command_and_wait(...)`.
    *   Construct the `command` dictionary with a unique `action` key (e.g., `"find_instances"`) and a `data` payload containing necessary parameters (e.g., `class_name`, `search_root`).
    *   Process the dictionary result returned by `queue_command_and_wait`, checking for `"error"` or the expected result key (e.g., `"instances"`).
    *   Format the result into a user-friendly string for the tool output.
2.  **Plugin (`roblox_mcp_plugin/src/Plugin.server.lua`):**
    *   Define a new Lua handler function (e.g., `local function handleFindInstances(data)`) *before* the `COMMAND_HANDLERS` table.
    *   Implement the core logic within the handler to perform the action in Studio (e.g., `root:GetDescendants()`, `target:Destroy()`, `target[propName] = value`, etc.).
    *   Extract the `request_id` from the `data` table passed to the handler.
    *   Prepare a `resultPayload` table containing either the successful result (e.g., `{ instances = ... }`) or an error (e.g., `{ error = "..." }`). Use the `serializeValue` helper if needed for complex data types.
    *   Call `sendResultToServer(requestId, resultPayload)` to send the outcome back to the server.
    *   Register the new handler in the `COMMAND_HANDLERS` table (e.g., `find_instances = handleFindInstances`).

---

## Tasks:

- [x] **`find_instances`**
    - **Server:** Queue command `{"action": "find_instances", "data": {"class_name": ..., "name_contains": ..., "search_root": ...}}`. Wait for result `{ "instances": [...] }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleFindInstances`. Logic to find descendants matching criteria. Serialize results (name, className, path) in a list. Send back.

- [x] **`delete_instance`**
    - **Server:** Queue command `{"action": "delete_instance", "data": {"object_name": ...}}`. Wait for result `{ "success": true }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleDeleteInstance`. Logic to find object by path and call `:Destroy()`. Send back success/error status.

- [x] **`set_property`**
    - **Server:** Queue command `{"action": "set_property", "data": {"object_name": ..., "property_name": ..., "value": ...}}`. Wait for result `{ "success": true }` or `{ "error": "..." }`. (*Note: Python `value` needs appropriate conversion before sending if it's not a basic type expected by the plugin's Lua type handling*).
    - **Plugin:** Add `handleSetProperty`. Logic to find object, find property, handle basic Lua type assignment (string, number, boolean, nil). Need robust type handling for common Roblox types (Vector3, Color3, BrickColor, Enum, Instance assignment) likely using `pcall` and checking `typeof(value)`. Send back success/error status.

- [x] **`move_instance`**
    - **Server:** Queue command `{"action": "move_instance", "data": {"object_name": ..., "position": '{"x": X, "y": Y, "z": Z}'}}` (ensure position is a JSON string representing the dictionary, e.g., `'{"x": X, "y": Y, "z": Z}'`). Wait for result `{ "success": true }` or `{ "error": "..." }`. (Alternatively, keep calling the refactored `set_property` tool).
    - **Plugin:** Add `handleMoveInstance`. Logic to find object, check if Model+PrimaryPart or BasePart, set Position/CFrame. Send back success/error status.

- [x] **`clone_instance`**
    - **Server:** Queue command `{"action": "clone_instance", "data": {"object_name": ..., "new_name": ..., "parent_name": ...}}`. Wait for result `{ "success": true, "clone_name": ..., "clone_path": ... }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleCloneInstance`. Logic to find original, call `:Clone()`, find target parent (or use original's), set new parent, set new name. Send back success/error status and new details.

- [x] **`create_script`**
    - **Server:** Queue command `{"action": "create_script", "data": {"script_name": ..., "script_code": ..., "script_type": ..., "parent_name": ...}}`. Wait for result `{ "success": true, "name": ..., "path": ... }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleCreateScript`. Logic to find parent, call `Instance.new()`, set Name, Source, Parent. Send back success/error status and details.

- [x] **`set_environment`**
    - **Server:** Queue command `{"action": "set_environment", "data": {"target": "Lighting" | "Terrain", "properties": {...}}}`. Wait for result `{ "success": true }` or `{ "error": "..." }`. (*Note: Value conversion needed as with `set_property`*).
    - **Plugin:** Add `handleSetEnvironment`. Logic to get Lighting service or Terrain object, iterate through properties, set values with type handling. Send back success/error status.

- [x] **`spawn_npc`**
    - **Server:** Queue command `{"action": "spawn_npc", "data": {"model_asset_id": ..., "template_model_name": ..., "position": {...}, "parent_name": ..., "new_name": ...}}`. Wait for result `{ "success": true, "name": ..., "path": ... }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleSpawnNpc`. Logic to either call `InsertService:LoadAsset()` or find/clone template, parent the result, set name, attempt to set position. Send back success/error status and details.

- [x] **`play_animation`**
    - **Server:** Queue command `{"action": "play_animation", "data": {"target_name": ..., "animation_id": ...}}`. Wait for result `{ "success": true }` or `{ "error": "..." }`.
    - **Plugin:** Add `handlePlayAnimation`. Logic to find target, find Humanoid/AnimationController, create temp `Animation` instance, load it (`LoadAnimation`), call `:Play()` on the track. Send back success/error status. 

## New Script Management Tools:

- [x] **`edit_script`**
    - **Server:** Queue command `{"action": "edit_script", "data": {"script_path": ..., "script_code": ...}}`. Wait for result `{ "success": true }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleEditScript`. Logic to find script by path, validate it's a Script/LocalScript, update its Source property. Send back success/error status.

- [x] **`delete_script`**
    - **Server:** Queue command `{"action": "delete_script", "data": {"script_path": ...}}`. Wait for result `{ "success": true }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleDeleteScript`. Logic to find script by path, validate it's a Script/LocalScript, call `:Destroy()`. Send back success/error status.

## Proposed New Tools

- [ ] **`rotate_instance`**
    - **Server:** Queue command `{"action": "rotate_instance", "data": {"object_name": ..., "rotation_type": "euler"|"cframe_delta", "rotation_values": [... or CFrame components]}}`. Wait for result `{ "success": true }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleRotateInstance`. Find object (Model or BasePart). If Model, use PrimaryPart. Apply rotation using `target:SetPrimaryPartCFrame(target.PrimaryPart.CFrame * CFrame.Angles(...))` or similar for CFrame delta. Send back success/error.

- [ ] **`group_instances`**
    - **Server:** Queue command `{"action": "group_instances", "data": {"instance_paths": [...], "new_group_name": ..., "parent_name": ...}}`. Wait for result `{ "success": true, "model_name": ..., "model_path": ... }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleGroupInstances`. Find parent. Create new `Model`. Find each instance by path, validate, and set its Parent to the new Model. Set Model Name and Parent. Potentially call `model:MakeJoints()`? Send back success/error and model details.

- [ ] **`ungroup_model`**
    - **Server:** Queue command `{"action": "ungroup_model", "data": {"model_path": ...}}`. Wait for result `{ "success": true }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleUngroupModel`. Find the Model. Get its Parent. Iterate through Model children (`model:GetChildren()`) and set their Parent to the Model's original parent. Call `model:Destroy()`. Send back success/error.

- [ ] **`fill_terrain_block`** (Example for `edit_terrain`)
    - **Server:** Queue command `{"action": "fill_terrain_block", "data": {"material": "Enum.Material...", "position": {...}, "size": {...}}}`. Wait for result `{ "success": true }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleFillTerrainBlock`. Get Terrain service. Construct CFrame and Size from position/size data. Call `Terrain:FillBlock(cframe, size, materialEnum)`. Send back success/error.

- [ ] **`create_particle_emitter`**
    - **Server:** Queue command `{"action": "create_particle_emitter", "data": {"parent_path": ..., "properties": {...}}}`. Wait for result `{ "success": true, "emitter_name": ..., "emitter_path": ... }` or `{ "error": "..." }`. (Properties might include Texture, Color, Size, Rate, etc., requiring type conversion).
    - **Plugin:** Add `handleCreateParticleEmitter`. Find parent part. Create `Instance.new("ParticleEmitter")`. Apply properties (use `convertToRobloxType` helper, may need extensions for sequences). Set Parent. Send back success/error and emitter details.

- [ ] **`play_sound`**
    - **Server:** Queue command `{"action": "play_sound", "data": {"sound_id": "rbxassetid://...", "parent_path": ... | "position": {...}, "properties": {...}}}`. Wait for result `{ "success": true, "sound_instance_path": ... }` or `{ "error": "..." }`. (Properties: Volume, TimePosition, Looped, etc.).
    - **Plugin:** Add `handlePlaySound`. Create `Instance.new("Sound")`. Set SoundId and other properties. If `parent_path` provided, find parent and set Sound.Parent. If `position` provided, parent to Workspace or Terrain, set Position. Call `sound:Play()`. Return success/error and the path to the temporary Sound instance (e.g., `Workspace.Sound_xyz`). Consider how to manage/clean up these sounds.

- [ ] **`create_ui_element`** (Example: TextLabel)
    - **Server:** Queue command `{"action": "create_ui_element", "data": {"element_type": "TextLabel", "parent_path": "StarterGui.MyScreenGui", "properties": {"Text": "Hello", "Size": "UDim2.new(0, 100, 0, 50)", ...}}}`. Wait for result `{ "success": true, "element_name": ..., "element_path": ... }` or `{ "error": "..." }`. (Needs careful property formatting/conversion, especially UDim2).
    - **Plugin:** Add `handleCreateUIElement`. Find parent (might need to create ScreenGui first if it doesn't exist). Create `Instance.new(elementType)`. Apply properties (need robust conversion for UDim2, Color3, etc.). Set Parent. Send back success/error and element details.

- [ ] **`find_path`**
    - **Server:** Queue command `{"action": "find_path", "data": {"start_pos": {...}, "end_pos": {...}, "agent_params": {...}}}`. Wait for result `{ "success": true, "path_status": "Enum.PathStatus...", "waypoints": [{x,y,z}, ...] }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleFindPath`. Get `PathfindingService`. Create path `p = service:CreatePath(agentParams)`. Compute `p:ComputeAsync(startVec3, endVec3)`. Check status. If success, iterate `p:GetWaypoints()`, convert Vector3s to tables `{x,y,z}`, return status and waypoint list. Send back result.

- [ ] **`create_remote_event`**
    - **Server:** Queue command `{"action": "create_remote_event", "data": {"event_name": ..., "parent_path": "ReplicatedStorage"}}`. Wait for result `{ "success": true, "event_name": ..., "event_path": ... }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleCreateRemoteEvent`. Find parent (default ReplicatedStorage). Create `Instance.new("RemoteEvent")`. Set Name and Parent. Send back success/error and event details.

- [ ] **`set_primary_part`**
    - **Server:** Queue command `{"action": "set_primary_part", "data": {"model_path": ..., "part_path": ...}}`. Wait for result `{ "success": true }` or `{ "error": "..." }`.
    - **Plugin:** Add `handleSetPrimaryPart`. Find model by path, find part by path. Validate both are found, model is a Model, part is a BasePart, and part is descendant of model. Set `model.PrimaryPart = part`. Send back success/error status.

- [ ] **`execute_luau_in_studio`**
    - **Server:** Queue command `{"action": "execute_script_in_studio", "data": {"script_code": ...}}`. Wait for result `{ "output_lines": [...], "return_values": [...], "error_message": ... }`.
    - **Plugin:** Add `handleExecuteScriptInStudio`. Use `loadstring` to compile code. Override `print`. Use `pcall` to execute. Capture prints, return values (serialized), and errors. Restore `print`. Send results back.

- [ ] **`modify_children`**
    - **Server:** Queue command `{"action": "modify_children", "data": {"parent_path": ..., "property_name": ..., "property_value": ..., "child_name_filter": ..., "child_class_filter": ...}}`. `property_value` must be a JSON string like `set_property`. Wait for result `{ "affected_count": N, "errors": [...] }`.
    - **Plugin:** Add `handleModifyChildren`. Find parent. Loop `GetChildren()`. Apply name/class filters. For matching children, attempt to set `property_name` to `property_value` (using `pcall`, decoding JSON string value if needed, using `convertToRobloxType`). Report back affected count and list of errors. 