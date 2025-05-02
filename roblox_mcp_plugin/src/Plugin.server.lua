--[[ Plugin Main Script ]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService") -- Added LogService

local SERVER_URL = "http://localhost:8000/plugin_command" -- TODO: Make configurable
local POLLING_INTERVAL = 2 -- Seconds

-- --- NEW: Result Reporting Configuration --- --
local SERVER_RESULT_ENDPOINT = "http://localhost:8000/plugin_report_result" -- Endpoint for sending results back
-- --- END: Result Reporting Configuration --- --

-- --- NEW: Logging Configuration --- --
local SERVER_LOG_ENDPOINT = "http://localhost:8000/receive_studio_logs" -- Endpoint for sending logs
local SEND_INTERVAL = 1.5 -- Minimum seconds between log sends to avoid spam
local MAX_LOG_BATCH_SIZE = 50 -- Max logs to send in one batch

local logsToSend = {} -- Buffer for logs waiting to be sent
local isSendingLogs = false -- Flag to prevent concurrent sends
local lastLogSendTime = 0
-- --- END: Logging Configuration --- --

local lastPollTime = 0

print("Vibe Blocks MCP Companion Plugin Loaded")

-- --- Helper: Send Result Back to Server --- --
local function sendResultToServer(requestId, resultData)
	if not requestId then
		print("Vibe Blocks MCP Plugin: Error - Cannot send result without a request ID.")
		return
	end
	
	local payload = {
		request_id = requestId,
		result = resultData -- This should be a table (will be JSON encoded)
	}
	
	local success, encodedPayload = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	
	if not success then
		print("Vibe Blocks MCP Plugin: Error - Failed to JSON encode result payload for request ID " .. requestId .. ": " .. tostring(encodedPayload)) -- encodedPayload is error message here
		return
	end
	
	print("Vibe Blocks MCP Plugin: Sending result for request ID " .. requestId .. " to " .. SERVER_RESULT_ENDPOINT)
	
	local postSuccess, postError = pcall(function()
		-- Use PostAsync for non-blocking request
		HttpService:PostAsync(SERVER_RESULT_ENDPOINT, encodedPayload, Enum.HttpContentType.ApplicationJson)
	end)
	
	if not postSuccess then
		print("Vibe Blocks MCP Plugin: Error - Failed to POST result to server for request ID " .. requestId .. ": " .. tostring(postError))
		-- Maybe implement retry logic later if needed
	else
		print("Vibe Blocks MCP Plugin: Successfully posted result for request ID " .. requestId)
	end
end
-- --- End Helper: Send Result --- --

local function findObjectFromPath(pathString)
	-- Simple path traversal (game, workspace, or starts with game/workspace)
	local parts = pathString:split(".")
	local currentObject
	local firstPartLower = string.lower(parts[1])

	-- Check if the path starts explicitly with game or workspace
	if firstPartLower == "game" then
		currentObject = game
		table.remove(parts, 1) -- Remove 'game' from parts to traverse
	elseif firstPartLower == "workspace" then
		currentObject = workspace
		table.remove(parts, 1) -- Remove 'workspace' from parts to traverse
	else
		-- Default to starting search from 'game' for other services (ServerStorage, etc.)
		currentObject = game
	end

	-- Traverse the remaining parts
	for _, partName in ipairs(parts) do
		if currentObject then
			currentObject = currentObject:FindFirstChild(partName)
		else
			return nil -- Path became invalid
		end
	end
	return currentObject
end

-- --- NEW: Helper to Convert Python/JSON values to Roblox Types ---
-- Returns: robloxValue, errorMessage (errorMessage is nil on success)
local function convertToRobloxType(propertyName, valueFromPython)
	local propNameLower = string.lower(propertyName or "") -- Safe lowercasing

	-- 1. Determine Expected Type based on Property Name
	local expectedType = "unknown"
	if propNameLower == "position" or propNameLower == "size" or propNameLower == "velocity" or propNameLower == "rotvelocity" or propNameLower == "orientation" then
		expectedType = "Vector3"
	elseif propNameLower == "color" then
		expectedType = "Color3"
	elseif propNameLower == "brickcolor" then
		expectedType = "BrickColor"
	elseif propNameLower == "cframe" then
		expectedType = "CFrame"
	elseif propNameLower == "material" then
		expectedType = "Enum.Material"
	elseif propNameLower == "shape" or propNameLower == "parttype" or propNameLower == "formfactor" then
		expectedType = "Enum.PartType" -- FormFactor maps to PartType Enum
	-- Add more specific property -> type mappings here (e.g., UDim2, NumberSequence)
	end

	-- 2. Handle Conversion based on Input Type and Expected Type
	local inputType = typeof(valueFromPython)

	if expectedType == "Vector3" then
		if inputType == "table" then
			if type(valueFromPython.x) == "number" and type(valueFromPython.y) == "number" and type(valueFromPython.z) == "number" then
				return Vector3.new(valueFromPython.x, valueFromPython.y, valueFromPython.z), nil
			elseif type(valueFromPython[1]) == "number" and type(valueFromPython[2]) == "number" and type(valueFromPython[3]) == "number" and #valueFromPython == 3 then
				return Vector3.new(valueFromPython[1], valueFromPython[2], valueFromPython[3]), nil
			else
				return nil, "Invalid table format for Vector3. Expected {x,y,z} or array [1,2,3]."
			end
		else
			return nil, "Incorrect input type for Vector3. Expected table, got " .. inputType
		end
	elseif expectedType == "Color3" then
		if inputType == "table" then
			-- Prefer {r,g,b} format (assume 0-1 range from JSON)
			if type(valueFromPython.r) == "number" and type(valueFromPython.g) == "number" and type(valueFromPython.b) == "number" then
				return Color3.new(valueFromPython.r, valueFromPython.g, valueFromPython.b), nil
			-- Accept array [r,g,b] format (assume 0-1 range from JSON)
			elseif type(valueFromPython[1]) == "number" and type(valueFromPython[2]) == "number" and type(valueFromPython[3]) == "number" and #valueFromPython == 3 then
				-- Check if values seem to be in 0-255 range (common mistake)
				if valueFromPython[1] > 1 or valueFromPython[2] > 1 or valueFromPython[3] > 1 then
					print("Vibe Blocks MCP Plugin: Warning - Color3 array values > 1 detected for '"..propertyName.."'. Assuming 0-255 range and using Color3.fromRGB.")
					return Color3.fromRGB(math.floor(valueFromPython[1]), math.floor(valueFromPython[2]), math.floor(valueFromPython[3])), nil
				else
					return Color3.new(valueFromPython[1], valueFromPython[2], valueFromPython[3]), nil
				end
			else
				return nil, "Invalid table format for Color3. Expected {r,g,b} or array [r,g,b] (0-1 range preferred)."
			end
		else
			return nil, "Incorrect input type for Color3. Expected table, got " .. inputType
		end
	elseif expectedType == "BrickColor" then
		if inputType == "string" or inputType == "number" then
			-- BrickColor.new handles invalid names/numbers gracefully by returning grey
			return BrickColor.new(valueFromPython), nil
		else
			return nil, "Incorrect input type for BrickColor. Expected string or number, got " .. inputType
		end
	elseif expectedType == "CFrame" then
		if inputType == "table" then
			-- Support 12-number array format: [x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22]
			local allNumbers = true
			if #valueFromPython == 12 then
				for i = 1, 12 do
					if type(valueFromPython[i]) ~= "number" then
						allNumbers = false
						break
					end
				end
				if allNumbers then
					return CFrame.new(
						valueFromPython[1], valueFromPython[2], valueFromPython[3],
						valueFromPython[4], valueFromPython[5], valueFromPython[6],
						valueFromPython[7], valueFromPython[8], valueFromPython[9],
						valueFromPython[10], valueFromPython[11], valueFromPython[12]
					), nil
				else
					return nil, "Invalid CFrame array. Expected 12 numbers."
				end
			-- Add support for other CFrame formats here if needed (e.g., Position+LookVector dict)
			else
				return nil, "Invalid table format for CFrame. Expected array of 12 numbers."
			end
		else
			return nil, "Incorrect input type for CFrame. Expected table, got " .. inputType
		end
	elseif string.sub(expectedType, 1, 5) == "Enum." then -- Handle Enums
		local enumTypeName = string.sub(expectedType, 6) -- Get "Material", "PartType", etc.
		local enumType = Enum[enumTypeName]
		if not enumType then
			return nil, "Internal Error: Unknown Enum type '" .. enumTypeName .. "'"
		end

		if inputType == "string" then
			-- If it already starts with "Enum.", try direct lookup
			if string.sub(valueFromPython, 1, 5) == "Enum." then
				local parts = valueFromPython:split(".")
				if #parts == 3 and parts[2] == enumTypeName then
					local enumItem = enumType[parts[3]]
					if enumItem then
						return enumItem, nil
					else
						return nil, "Invalid Enum item name '" .. parts[3] .. "' in full Enum path."
					end
				else
					return nil, "Invalid full Enum path format: " .. valueFromPython
				end
			else
				-- Try lookup by string name directly using index
				local enumItem = enumType[valueFromPython] -- Use direct indexing
				-- Alternative: iterate through enumType:GetEnumItems() and compare names (case-insensitive?)
				if enumItem then
					return enumItem, nil
				else
					return nil, "Could not find Enum item '" .. valueFromPython .. "' in Enum." .. enumTypeName
				end
			end
		elseif inputType == "number" then
			-- Try lookup by enum value/number
			for _, item in ipairs(enumType:GetEnumItems()) do
				if item.Value == valueFromPython then
					return item, nil
				end
			end
			return nil, "Could not find Enum item with value " .. tostring(valueFromPython) .. " in Enum." .. enumTypeName
		else
			return nil, "Incorrect input type for Enum." .. enumTypeName .. ". Expected string or number, got " .. inputType
		end
	end

	-- 3. If no specific type matched or conversion wasn't needed, return the original value
	-- This handles basic types: string, number, boolean, nil, and tables for non-special properties
	if inputType == "string" or inputType == "number" or inputType == "boolean" or inputType == "nil" or inputType == "table" then
		return valueFromPython, nil
	else
		-- Should not happen for standard JSON types, but catch anyway
		return nil, "Unsupported input value type: " .. inputType
	end
end
-- --- END Helper: Convert Roblox Value --- --

local function handleSetEnvironment(data)
	local targetName = data.target
	local properties = data.properties
    local requestId = data.request_id -- Extract request ID

	local resultPayload = {} -- Initialize result payload

	if not targetName or not properties or type(properties) ~= "table" then
		resultPayload.error = "Missing/invalid 'target' or 'properties' in set_environment data."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local targetService
	local serviceSuccess, serviceOrError = pcall(function()
		if string.lower(targetName) == "lighting" then
			return game:GetService("Lighting")
		elseif string.lower(targetName) == "terrain" then
			return workspace:FindFirstChildOfClass("Terrain")
		else
			error("Unsupported target for set_environment: " .. targetName)
		end
	end)

	if not serviceSuccess then
		resultPayload.error = "Error finding target service: " .. tostring(serviceOrError)
		print("Vibe Blocks MCP Plugin: " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end
	
	targetService = serviceOrError -- Assign the found service
	if not targetService then
		resultPayload.error = "Could not find target service instance: " .. targetName
		print("Vibe Blocks MCP Plugin: " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	print("Vibe Blocks MCP Plugin: Setting properties on " .. targetService.Name .. ":")
	local allPropertiesSuccess = true
	local propertyErrors = {}

	for propName, propValue in pairs(properties) do
		local success, err = pcall(function()
			-- Basic type handling - TODO: Expand this like handleSetProperty
			if type(propValue) == "number" then
				targetService[propName] = propValue
				print("  - Set " .. propName .. " to " .. tostring(propValue))
			elseif type(propValue) == "boolean" then
				targetService[propName] = propValue
				print("  - Set " .. propName .. " to " .. tostring(propValue))
			elseif type(propValue) == "string" then
				targetService[propName] = propValue
				print("  - Set " .. propName .. " to '" .. propValue .. "'")
			elseif type(propValue) == "table" then
				-- Placeholder for complex types
				error("Table values not fully supported yet in set_environment")
			else
				error("Unsupported value type: " .. type(propValue))
			end
		end)
		if not success then
			allPropertiesSuccess = false
			propertyErrors[propName] = tostring(err)
			print("  - Error setting property " .. propName .. ": " .. tostring(err))
		end
	end
	
	if allPropertiesSuccess then
		resultPayload.success = true
		print("Vibe Blocks MCP Plugin: Finished setting environment properties successfully.")
	else
		-- Still technically a success for the operation, but report errors
		resultPayload.success = false -- Mark as partial failure if any prop failed
		resultPayload.errors = propertyErrors
		resultPayload.error = "Failed to set one or more properties." -- General error message
		print("Vibe Blocks MCP Plugin: Finished setting environment properties with errors.")
	end

	-- Send final result
	if requestId then sendResultToServer(requestId, resultPayload) end
end

local function handleCreateInstance(data)
	local className = data.class_name
	local parentName = data.parent_name or "Workspace" -- Default to Workspace
	local properties = data.properties or {} -- Default to empty table
    local requestId = data.request_id -- Extract request ID

	local resultPayload = {} -- Initialize result payload

	if not className then
		resultPayload.error = "Missing 'class_name' in create_instance data."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	-- Find the parent
	local parentObject = findObjectFromPath(parentName)
	if not parentObject then
		resultPayload.error = "Could not find parent object for create_instance: " .. parentName
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	print(string.format("Vibe Blocks MCP Plugin: Creating instance of '%s' under '%s'", className, parentObject:GetFullName()))

	local success, newInstanceOrError = pcall(function()
		local inst = Instance.new(className)
		inst.Parent = parentObject -- Parent first

		-- Apply properties using the new converter
		for propName, propValue in pairs(properties) do
			print(string.format("  - Applying property '%s' with value type: %s", propName, type(propValue)))
			local robloxValue, convertError = convertToRobloxType(propName, propValue)

			if convertError then
				-- If conversion fails, wrap the error (will be caught by outer pcall)
				error(string.format("Error converting value for property '%s': %s", propName, convertError))
			else
				-- Assign the converted value
				local setSuccess, setError = pcall(function()
					inst[propName] = robloxValue
				end)
				if not setSuccess then
					-- If setting the converted value fails, wrap the error
					error(string.format("Error setting property '%s' after conversion: %s", propName, tostring(setError)))
				end
			end
		end
		return inst -- Return the instance if all properties were set successfully
	end)

	if success then
		local newInstance = newInstanceOrError
		resultPayload.success = true
		resultPayload.name = newInstance.Name
		resultPayload.path = newInstance:GetFullName()
		print("Vibe Blocks MCP Plugin: Finished creating instance " .. resultPayload.path)
	else
		resultPayload.error = "Failed to create instance: " .. tostring(newInstanceOrError)
		print("Vibe Blocks MCP Plugin: " .. resultPayload.error)
	end

	-- Send final result
	if requestId then sendResultToServer(requestId, resultPayload) end
end

local function handleDeleteInstance(data)
	local objectName = data.object_name
	if not objectName then
		print("Vibe Blocks MCP Plugin: Error - Missing 'object_name' in delete_instance data.")
		return
	end

	local target = findObjectFromPath(objectName)
	if not target then
		print("Vibe Blocks MCP Plugin: Error - Could not find object to delete: " .. objectName)
		return
	end

	local fullName = target:GetFullName()
	print("Vibe Blocks MCP Plugin: Deleting instance " .. fullName)
	local success, err = pcall(function()
		target:Destroy()
	end)
	if success then
		print("Vibe Blocks MCP Plugin: Successfully deleted " .. fullName)
	else
		print("Vibe Blocks MCP Plugin: Error deleting " .. fullName .. ": " .. tostring(err))
	end
end

local function handleSetProperty(data)
	local objectName = data.object_name
	local propertyName = data.property_name
	local propertyValue = data.value
    local requestId = data.request_id -- Extract request ID

	local resultPayload = {} -- Initialize result payload

	if not objectName or not propertyName then
		resultPayload.error = "Missing 'object_name' or 'property_name' in set_property data."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local target = findObjectFromPath(objectName)
	if not target then
		resultPayload.error = "Could not find object to set property on: " .. objectName
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local fullName = target:GetFullName()
	print(string.format("Vibe Blocks MCP Plugin: Setting property '%s' on '%s'", propertyName, fullName))

	local success, err = pcall(function()
		-- <<< Debug logging remains >>>
		print("  - Debug: typeof(propertyValue):", typeof(propertyValue))
		local debugSuccess, debugEncoded = pcall(function() return HttpService:JSONEncode(propertyValue) end)
		if debugSuccess then
			print("  - Debug: propertyValue JSON:", debugEncoded)
		else
			print("  - Debug: propertyValue raw:", tostring(propertyValue))
		end

		-- <<< NEW: Attempt to decode if value is string >>>
		local valueToConvert = propertyValue
		if typeof(valueToConvert) == "string" then
			-- Only attempt decode if it looks like an array or object string
			if string.sub(valueToConvert, 1, 1) == "[" or string.sub(valueToConvert, 1, 1) == "{" then
				local decodeSuccess, decodedTable = pcall(function()
					return HttpService:JSONDecode(valueToConvert)
				end)
				if decodeSuccess and typeof(decodedTable) == "table" then
					print("  - Info: Successfully JSONDecoded string value to table.")
					valueToConvert = decodedTable -- Use the decoded table instead
				else
					-- Log if decoding failed but maybe shouldn't have
					print("  - Warning: Value is string resembling table/array, but failed to decode or wasn't table type. Error:", tostring(decodedTable))
				end
			else
				print("  - Info: Value is string, but doesn't start with [ or {. Proceeding with raw string.")
			end
		end
		-- <<< END NEW >>>

		-- Convert the incoming value using the helper
		local robloxValue, convertError = convertToRobloxType(propertyName, valueToConvert)
		if convertError then
			-- Raise an error if conversion fails
			error("Value conversion failed: " .. convertError)
		end

		-- Assign the converted Roblox value
		target[propertyName] = robloxValue
		print(string.format("  - Successfully set '%s' to value of type %s", propertyName, typeof(robloxValue)))
	end)

	if success then
		resultPayload.success = true
		print("Vibe Blocks MCP Plugin: Finished setting property successfully.")
	else
		resultPayload.error = "Failed to set property: " .. tostring(err)
		print("  - Error setting property: " .. tostring(err))
	end

	-- Send final result
	if requestId then sendResultToServer(requestId, resultPayload) end
end

local function handleMoveInstance(data)
	local objectName = data.object_name
	local positionTable = data.position
    local requestId = data.request_id -- Extract request ID

	local resultPayload = {} -- Initialize result payload

	if not objectName or not positionTable or type(positionTable) ~= "table" then
		resultPayload.error = "Missing/invalid 'object_name' or 'position' in move_instance data."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	if type(positionTable.x) ~= "number" or type(positionTable.y) ~= "number" or type(positionTable.z) ~= "number" then
		resultPayload.error = "Invalid 'position' table format (expected {x=num, y=num, z=num})."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local target = findObjectFromPath(objectName)
	if not target then
		resultPayload.error = "Could not find object to move: " .. objectName
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local newPosition = Vector3.new(positionTable.x, positionTable.y, positionTable.z)
	local fullName = target:GetFullName()
	print(string.format("Vibe Blocks MCP Plugin: Moving '%s' to %s", fullName, tostring(newPosition)))

	local success, err = pcall(function()
		if target:IsA("Model") and target.PrimaryPart then
			local currentCFrame = target:GetPrimaryPartCFrame()
			target:SetPrimaryPartCFrame(CFrame.new(newPosition) * (currentCFrame - currentCFrame.Position))
		elseif target:IsA("BasePart") then
			target.Position = newPosition
		else
			error("Target is not a Model with PrimaryPart or a BasePart.")
		end
	end)

	if success then
		resultPayload.success = true
		print("Vibe Blocks MCP Plugin: Successfully moved " .. fullName)
	else
		resultPayload.error = "Failed to move object: " .. tostring(err)
		print("Vibe Blocks MCP Plugin: Error moving " .. fullName .. ": " .. tostring(err))
	end

	-- Send final result
	if requestId then sendResultToServer(requestId, resultPayload) end
end

local function handleCloneInstance(data)
	local objectName = data.object_name
	local newName = data.new_name -- Optional
	local parentName = data.parent_name -- Optional
    local requestId = data.request_id -- Extract request ID

	local resultPayload = {} -- Initialize result payload

	if not objectName then
		resultPayload.error = "Missing 'object_name' in clone_instance data."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local original = findObjectFromPath(objectName)
	if not original then
		resultPayload.error = "Could not find original object to clone: " .. objectName
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local originalFullName = original:GetFullName()
	print("Vibe Blocks MCP Plugin: Cloning " .. originalFullName)

	local cloneSuccess, clone = pcall(function()
		return original:Clone()
	end)

	if not cloneSuccess then
		resultPayload.error = "Failed to clone object: " .. tostring(clone) -- clone is error message here
		print("Vibe Blocks MCP Plugin: Error cloning " .. originalFullName .. ": " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end
	
	print("  - Clone successful.")

	-- Handle parenting
	local parentObject = original.Parent -- Default
	local parentError = nil
	if parentName then
		local specifiedParent = findObjectFromPath(parentName)
		if specifiedParent then
			parentObject = specifiedParent
		else
			parentError = "Specified parent not found, using original parent."
			print("  - Warning: " .. parentError)
		end
	end
	
	local setParentSuccess, setParentErr = pcall(function() clone.Parent = parentObject end)
	if not setParentSuccess then
		resultPayload.error = "Failed to set parent on clone: " .. tostring(setParentErr)
		print("Vibe Blocks MCP Plugin: " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		pcall(function() clone:Destroy() end) -- Clean up clone
		return
	end
	print("  - Parent set to: " .. (parentObject and parentObject:GetFullName() or "nil"))

	-- Handle naming
	if newName then
		local setNameSuccess, setNameErr = pcall(function() clone.Name = newName end)
		if not setNameSuccess then
			resultPayload.error = "Failed to set name on clone: " .. tostring(setNameErr)
			print("Vibe Blocks MCP Plugin: " .. resultPayload.error)
			-- Don't destroy the clone here, parent was set successfully
		else
			print("  - Name set to: " .. newName)
		end
	else
		print("  - Using default clone name: " .. clone.Name)
	end
	
	-- If we reached here without a major error, report success
	if not resultPayload.error then
		resultPayload.success = true
		resultPayload.clone_name = clone.Name
		resultPayload.clone_path = clone:GetFullName()
		if parentError then resultPayload.parent_error = parentError end -- Include the parent warning
		print("Vibe Blocks MCP Plugin: Finished cloning. New instance at " .. resultPayload.clone_path)
	end
	
	-- Send final result (success or naming error)
	if requestId then sendResultToServer(requestId, resultPayload) end
end

local function handleCreateScript(data)
	local scriptName = data.script_name
	local scriptCode = data.script_code
	local scriptType = data.script_type or "Script" -- Default to Script
	local parentName = data.parent_name or "Workspace" -- Default to Workspace
    local requestId = data.request_id -- Extract request ID

	local resultPayload = {} -- Initialize result payload

	if not scriptName or not scriptCode then
		resultPayload.error = "Missing 'script_name' or 'script_code' in create_script data."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	if scriptType ~= "Script" and scriptType ~= "LocalScript" then
		resultPayload.error = "Invalid 'script_type': " .. scriptType .. ". Must be 'Script' or 'LocalScript'."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local parentObject = findObjectFromPath(parentName)
	if not parentObject then
		resultPayload.error = "Could not find parent object for create_script: " .. parentName
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	print(string.format("Vibe Blocks MCP Plugin: Creating %s named '%s' under '%s'", scriptType, scriptName, parentObject:GetFullName()))

	local success, newScriptOrError = pcall(function()
		local newScript = Instance.new(scriptType)
		newScript.Name = scriptName
		newScript.Source = scriptCode
		newScript.Parent = parentObject -- Parent last after setting properties
		return newScript
	end)

	if success then
		local newScript = newScriptOrError
		resultPayload.success = true
		resultPayload.name = newScript.Name
		resultPayload.path = newScript:GetFullName()
		print("Vibe Blocks MCP Plugin: Successfully created script " .. resultPayload.path)
	else
		resultPayload.error = string.format("Failed creating %s '%s': %s", scriptType, scriptName, tostring(newScriptOrError))
		print("Vibe Blocks MCP Plugin: " .. resultPayload.error)
	end

	-- Send final result
	if requestId then sendResultToServer(requestId, resultPayload) end
end

local function handleSpawnNpc(data)
	local modelAssetId = data.model_asset_id
	local templateModelName = data.template_model_name
	local positionTable = data.position -- Optional, will be validated later
	local parentName = data.parent_name or "Workspace"
	local newName = data.new_name -- Optional
    local requestId = data.request_id -- Extract request ID

	local resultPayload = {} -- Initialize result payload

	if not modelAssetId and not templateModelName then
		resultPayload.error = "Missing 'model_asset_id' or 'template_model_name' in spawn_npc data."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local parentObject = findObjectFromPath(parentName)
	if not parentObject then
		resultPayload.error = "Could not find parent object for spawn_npc: " .. parentName
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	-- Validate position table if provided
	local newPosition = nil
	if positionTable then
		if type(positionTable) ~= "table" or type(positionTable.x) ~= "number" or type(positionTable.y) ~= "number" or type(positionTable.z) ~= "number" then
			resultPayload.error = "Invalid 'position' table format (expected {x=num, y=num, z=num})."
			print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
			if requestId then sendResultToServer(requestId, resultPayload) end
			return
		else
			newPosition = Vector3.new(positionTable.x, positionTable.y, positionTable.z)
		end
	end

	local npcModel = nil
	local loadSuccess, loadResultOrError

	-- Load or Clone NPC Model
	if modelAssetId then
		print("Vibe Blocks MCP Plugin: Spawning NPC from Asset ID: " .. tostring(modelAssetId))
		loadSuccess, loadResultOrError = pcall(function()
			local insertService = game:GetService("InsertService")
			local asset = insertService:LoadAsset(modelAssetId)
			if asset:IsA('Model') and #asset:GetChildren() == 1 then return asset:GetChildren()[1] else return asset end
		end)
		if not loadSuccess then
			resultPayload.error = "Error loading asset ID " .. tostring(modelAssetId) .. ": " .. tostring(loadResultOrError)
		end
	elseif templateModelName then
		print("Vibe Blocks MCP Plugin: Spawning NPC by cloning template: " .. templateModelName)
		local template = findObjectFromPath(templateModelName)
		if not template then
			resultPayload.error = "Template model not found: " .. templateModelName
		else
			loadSuccess, loadResultOrError = pcall(function() return template:Clone() end)
			if not loadSuccess then
				resultPayload.error = "Error cloning template " .. templateModelName .. ": " .. tostring(loadResultOrError)
			end
		end
	end

	-- Check if loading/cloning failed
	if not loadSuccess or not loadResultOrError or not loadResultOrError:IsA("Instance") then
		if not resultPayload.error then resultPayload.error = "Failed to obtain a valid instance for the NPC." end
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end
	npcModel = loadResultOrError

	-- Set Name, Parent, and Position
	local setupSuccess, setupError = pcall(function()
		if newName then npcModel.Name = newName end
		npcModel.Parent = parentObject
		print("  - NPC Parent set to: " .. parentObject:GetFullName())

		-- Attempt to position
		if newPosition then
			if npcModel:IsA("Model") and npcModel.PrimaryPart then
				local currentCFrame = npcModel:GetPrimaryPartCFrame()
				npcModel:SetPrimaryPartCFrame(CFrame.new(newPosition) * (currentCFrame - currentCFrame.Position))
				print("  - Positioned using SetPrimaryPartCFrame")
			elseif npcModel:IsA("BasePart") then
				npcModel.Position = newPosition
				print("  - Positioned using Position property")
			else
				resultPayload.warning = "Could not automatically set position - NPC is not a Model with PrimaryPart or a BasePart."
				print("  - Warning: " .. resultPayload.warning)
			end
		else
			print("  - No position specified, skipping positioning.")
		end
	end)

	if not setupSuccess then
		resultPayload.error = "Error setting up NPC (Name/Parent/Position): " .. tostring(setupError)
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		pcall(function() npcModel:Destroy() end) -- Clean up the partially set up NPC
	else
		resultPayload.success = true
		resultPayload.name = npcModel.Name
		resultPayload.path = npcModel:GetFullName()
		print("Vibe Blocks MCP Plugin: Finished spawning NPC " .. resultPayload.path)
		if resultPayload.warning then -- Include position warning if it exists
			print("Vibe Blocks MCP Plugin: Spawn finished with warnings.")
		end
	end

	-- Send final result
	if requestId then sendResultToServer(requestId, resultPayload) end
end

local function handleScaleModel(data)
	local objectName = data.object_name
	local scaleFactor = data.scale_factor
    local requestId = data.request_id -- Extract request ID

	local resultPayload = {} -- Initialize result payload

	if not objectName or type(scaleFactor) ~= "number" or scaleFactor <= 0 then
		resultPayload.error = "Missing/invalid 'object_name' or 'scale_factor' in scale_model data."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local targetModel = findObjectFromPath(objectName)
	if not targetModel or not targetModel:IsA("Model") then
		resultPayload.error = "Could not find Model to scale: " .. objectName
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local fullName = targetModel:GetFullName()
	print(string.format("Vibe Blocks MCP Plugin: Scaling model '%s' by factor %.2f", fullName, scaleFactor))

	local success, err = pcall(function()
		local currentSize = targetModel:GetExtentsSize()
		local targetSize = currentSize * scaleFactor
		targetModel:ScaleTo(targetSize.X)
	end)

	if success then
		resultPayload.success = true
		print("Vibe Blocks MCP Plugin: Successfully scaled " .. fullName)
	else
		resultPayload.error = "Failed to scale model: " .. tostring(err)
		print("Vibe Blocks MCP Plugin: Error scaling " .. fullName .. ": " .. tostring(err))
	end
	
	-- Send final result
	if requestId then sendResultToServer(requestId, resultPayload) end
end

local function handlePlayAnimation(data)
	local targetName = data.target_name
	local animationId = data.animation_id
    local requestId = data.request_id -- Extract request ID

	local resultPayload = {} -- Initialize result payload

	if not targetName or not animationId or type(animationId) ~= "number" then
		resultPayload.error = "Missing/invalid 'target_name' or 'animation_id' in play_animation data."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local target = findObjectFromPath(targetName)
	if not target then
		resultPayload.error = "Could not find target object for play_animation: " .. targetName
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local animator = target:FindFirstChildOfClass("Humanoid") or target:FindFirstChildOfClass("AnimationController")
	if not animator then
		resultPayload.error = "Target object " .. targetName .. " does not contain a Humanoid or AnimationController."
		print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error)
		if requestId then sendResultToServer(requestId, resultPayload) end
		return
	end

	local animationAssetId = "rbxassetid://" .. tostring(animationId)
	print(string.format("Vibe Blocks MCP Plugin: Playing animation %s on %s", animationAssetId, target:GetFullName()))

	local animInstance = Instance.new("Animation")
	animInstance.Name = "MCP_TempAnimation"
	animInstance.AnimationId = animationAssetId

	local loadSuccess, trackOrError = pcall(function() return animator:LoadAnimation(animInstance) end)
	pcall(function() animInstance:Destroy() end) -- Clean up temp instance

	if not loadSuccess then
		resultPayload.error = "Error loading animation " .. animationAssetId .. ": " .. tostring(trackOrError)
		print("Vibe Blocks MCP Plugin: " .. resultPayload.error)
	else
		local animationTrack = trackOrError
		local playSuccess, playError = pcall(function() animationTrack:Play() end)

		if playSuccess then
			resultPayload.success = true
			resultPayload.message = "Animation track loaded and played."
			print("Vibe Blocks MCP Plugin: Successfully started animation track.")
		else
			resultPayload.error = "Error playing animation track: " .. tostring(playError)
			print("Vibe Blocks MCP Plugin: " .. resultPayload.error)
		end
	end

	-- Send final result
	if requestId then sendResultToServer(requestId, resultPayload) end
end

local function handleSendChat(data)
	local message = data.message
	-- local senderName = data.sender_name -- Placeholder for future use if needed

	if not message or type(message) ~= "string" then
		print("Vibe Blocks MCP Plugin: Error - Missing/invalid 'message' in send_chat data.")
		return
	end

	local textChatService = game:GetService("TextChatService")
	if not textChatService then
		print("Vibe Blocks MCP Plugin: Error - TextChatService not found.")
		return
	end

	-- Use RBXSystem channel for system messages
	local systemChannel = textChatService:FindFirstChild("RBXSystem")
	if not systemChannel or not systemChannel:IsA("TextChannel") then
		print("Vibe Blocks MCP Plugin: Error - Could not find RBXSystem TextChannel.")
		return
	end

	print("Vibe Blocks MCP Plugin: Sending system chat message: " .. message)
	local success, err = pcall(function()
		-- Use SendAsync for more general message sending
		systemChannel:SendAsync(message)
		-- Alternative: systemChannel:DisplaySystemMessage(message)
	end)

	if success then
		print("Vibe Blocks MCP Plugin: Successfully sent chat message.")
	else
		print("Vibe Blocks MCP Plugin: Error sending chat message: " .. tostring(err))
	end
end

local function handleTeleportPlayer(data)
	local playerName = data.player_name
	local destinationPlaceId = data.destination_place_id
	local teleportOptions = data.teleport_options -- Optional table
	local customLoadingScriptName = data.custom_loading_script -- Optional string name

	if not playerName or not destinationPlaceId or type(destinationPlaceId) ~= "number" then
		print("Vibe Blocks MCP Plugin: Error - Missing/invalid 'player_name' or 'destination_place_id' in teleport_player data.")
		return
	end

	local teleportService = game:GetService("TeleportService")
	local playersService = game:GetService("Players")
	local replicatedFirst = game:GetService("ReplicatedFirst")

	if not teleportService then
		print("Vibe Blocks MCP Plugin: Error - TeleportService not found.")
		return
	end
	
	-- Player finding only works in a running game instance
	local playerToTeleport = playersService:FindFirstChild(playerName)
	if not playerToTeleport then
		print("Vibe Blocks MCP Plugin: Warning - Player \"" .. playerName .. "\" not found (or command run outside active game).")
		-- Don't return error, as this might be run in edit mode intentionally
		return 
	end

	-- Construct TeleportOptions if provided
	local finalTeleportOptions
	if teleportOptions and type(teleportOptions) == "table" then
		local success, optionsInstance = pcall(function() return Instance.new("TeleportOptions") end)
		if success and optionsInstance then
			finalTeleportOptions = optionsInstance
			for key, value in pairs(teleportOptions) do
				local setSuccess, setError = pcall(function()
					-- Basic assignment, might need type checks for complex option values
					finalTeleportOptions[key] = value
				end)
				if not setSuccess then
					print("  - Warning: Failed to set TeleportOption '" .. key .. "': " .. tostring(setError))
				end
			end
		else
			print("Vibe Blocks MCP Plugin: Warning - Could not create TeleportOptions instance.")
		end
	end

	-- Find custom loading screen if provided
	local loadingScreenGui
	if customLoadingScriptName and type(customLoadingScriptName) == "string" then
		loadingScreenGui = replicatedFirst:FindFirstChild(customLoadingScriptName)
		if not loadingScreenGui or not loadingScreenGui:IsA("LocalScript") then
			print("Vibe Blocks MCP Plugin: Warning - Custom loading script '" .. customLoadingScriptName .. "' not found or not a LocalScript in ReplicatedFirst.")
			loadingScreenGui = nil -- Reset if not valid
		end
	end

	print(string.format("Vibe Blocks MCP Plugin: Attempting to teleport player %s to place %d", playerName, destinationPlaceId))

	local success, err = pcall(function()
		teleportService:TeleportAsync(destinationPlaceId, {playerToTeleport}, finalTeleportOptions, loadingScreenGui)
	end)

	if success then
		print("Vibe Blocks MCP Plugin: Teleport initiated successfully for " .. playerName)
	else
		print("Vibe Blocks MCP Plugin: Error initiating teleport for " .. playerName .. ": " .. tostring(err))
	end
end

local function handleSetPlayerPosition(data)
	local playerName = data.player_name
	local positionTable = data.position

	if not playerName or not positionTable or type(positionTable) ~= "table" then
		print("Vibe Blocks MCP Plugin: Error - Missing/invalid 'player_name' or 'position' in set_player_position data.")
		return
	end

	-- Validate position table
	if type(positionTable.x) ~= "number" or type(positionTable.y) ~= "number" or type(positionTable.z) ~= "number" then
		print("Vibe Blocks MCP Plugin: Error - Invalid 'position' table format (expected {x=num, y=num, z=num}).")
		return
	end

	-- Find the player's character in the Workspace
	local character = workspace:FindFirstChild(playerName)
	if not character or not character:IsA("Model") then
		print("Vibe Blocks MCP Plugin: Error - Could not find character Model in Workspace named: " .. playerName)
		-- It might also be in game.Players[playerName].Character, but workspace is usually safer for positioning
		return
	end

	-- Find the HumanoidRootPart
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		print("Vibe Blocks MCP Plugin: Error - Could not find HumanoidRootPart in character: " .. playerName)
		return
	end

	local newPosition = Vector3.new(positionTable.x, positionTable.y, positionTable.z)
	print(string.format("Vibe Blocks MCP Plugin: Setting position of %s's HumanoidRootPart to %s", playerName, tostring(newPosition)))

	local success, err = pcall(function()
		-- Set CFrame directly, preserves orientation if possible
		hrp.CFrame = CFrame.new(newPosition)
		-- Alternative if anchoring issues: hrp.Position = newPosition
	end)

	if success then
		print("Vibe Blocks MCP Plugin: Successfully set player position.")
	else
		print("Vibe Blocks MCP Plugin: Error setting player position: " .. tostring(err))
	end
end

-- --- NEW: Find Instances Handler --- --
local function handleFindInstances(data)
    local classNameFilter = data.class_name -- Can be nil
    local nameContainsFilter = data.name_contains -- Can be nil
    local searchRootName = data.search_root or "Workspace"
    local requestId = data.request_id

    local resultPayload = { instances = {} } -- Initialize with empty list
    local errorResult = nil

    local root = findObjectFromPath(searchRootName)

    if not root then
        errorResult = { error = "Search root not found: " .. searchRootName }
    else
        print(string.format("Vibe Blocks MCP Plugin: Finding instances under %s (%s) for request ID %s", root.Name, root.ClassName, requestId or "N/A"))
        print(string.format("  - Filters: ClassName='%s', NameContains='%s'", classNameFilter or "any", nameContainsFilter or "any"))
        
        local nameFilterLower = nameContainsFilter and nameContainsFilter:lower() or nil

        local findSuccess, findError = pcall(function()
            for _, descendant in ipairs(root:GetDescendants()) do
                -- ClassName check
                local classMatch = (classNameFilter == nil) or (descendant.ClassName == classNameFilter)

                -- Name check (case-insensitive)
                local nameMatch = (nameFilterLower == nil) or (string.find(descendant.Name:lower(), nameFilterLower) ~= nil)

                if classMatch and nameMatch then
                    -- No need to serialize here, just basic info
                    table.insert(resultPayload.instances, {
                        name = descendant.Name,
                        className = descendant.ClassName,
                        path = descendant:GetFullName()
                    })
                end
            end
        end)

        if not findSuccess then
            errorResult = { error = "Error during search: " .. tostring(findError) }
            print("  - Error during search: " .. tostring(findError))
        else
             print(string.format("  - Found %d matching instances.", #resultPayload.instances))
        end
    end

    -- Send results or error back
    if requestId then
        sendResultToServer(requestId, errorResult or resultPayload)
    else
        print("Vibe Blocks MCP Plugin: Warning - No request_id found in find_instances data. Cannot report result back.")
    end
end
-- --- END: Find Instances Handler --- --

-- --- NEW: List Children Handler --- --
local function handleListChildren(data)
    local parentName = data.parent_name or "Workspace" -- Use provided name or default
    local requestId = data.request_id -- Get the request ID sent by the server

    local parentObject = findObjectFromPath(parentName)
    local results = {}
    local errorResult = nil

    if not parentObject then
        local errMsg = "Error - Could not find parent object: " .. parentName
        print("Vibe Blocks MCP Plugin: " .. errMsg)
        errorResult = { error = errMsg }
    else
        print(string.format("Vibe Blocks MCP Plugin: Listing children of %s (%s) for request ID %s", parentObject.Name, parentObject.ClassName, requestId or "N/A"))
        local success, childrenOrError = pcall(function()
            return parentObject:GetChildren()
        end)

        if success then
            local children = childrenOrError
            for i, child in ipairs(children) do
                table.insert(results, {
                    name = child.Name,
                    className = child.ClassName,
                    path = child:GetFullName()
                })
                print(string.format("  - Found: %s (%s) Path: %s", child.Name, child.ClassName, child:GetFullName()))
            end
            print("Vibe Blocks MCP Plugin: Finished listing children for " .. parentName)
        else
            local errMsg = "Error getting children for " .. parentName .. ": " .. tostring(childrenOrError)
            print("Vibe Blocks MCP Plugin: " .. errMsg)
            errorResult = { error = errMsg }
        end
    end

    -- Send the result (or error) back to the server
    if requestId then
        sendResultToServer(requestId, errorResult or results) -- Use the previously added helper
    else
        print("Vibe Blocks MCP Plugin: Warning - No request_id found in list_children data. Cannot report result back.")
    end
end
-- --- END: List Children Handler --- --

-- --- Helper: Serialize Roblox Value to JSON-compatible Table/Primitive --- --
-- NOTE: Defined globally before handlers that might use it.
local function serializeValue(value)
	local valueType = typeof(value)

	if valueType == 'Vector3' then
		return {type='Vector3', x=value.X, y=value.Y, z=value.Z}
	elseif valueType == 'CFrame' then
		-- Simplified CFrame representation (Position + LookVector for basic orientation)
		-- Or return full components if needed
		local pos = value.Position
		local look = value.LookVector
		return {type='CFrame', position={x=pos.X, y=pos.Y, z=pos.Z}, lookVector={x=look.X, y=look.Y, z=look.Z}} 
	elseif valueType == 'Color3' then
		 return {type='Color3', r=value.R, g=value.G, b=value.B}
	elseif valueType == 'BrickColor' then
		return {type='BrickColor', name=value.Name, number=value.Number}
	elseif valueType == 'boolean' or valueType == 'number' or valueType == 'string' or valueType == 'nil' then
		return value -- These types are directly JSON compatible
	elseif string.find(valueType, "Enum.") then -- Check if it's an EnumItem
		return {type='EnumItem', fullValue=tostring(value), name=value.Name, value=value.Value}
	elseif valueType == 'Instance' then
		 return {type='Instance', name=value.Name, className=value.ClassName, path=value:GetFullName()}
	elseif valueType == 'RBXScriptConnection' then
		return {type='Connection', status=value.Connected and 'Connected' or 'Disconnected'} -- Basic info
	-- Add more types as needed: Vector2, UDim2, Rect, Ray, Region3, PhysicalProperties, etc.
	else
		-- Fallback: represent unknown types as a string
		return {type=valueType, value=tostring(value)}
	end
end
-- --- END Helper: Serialize Roblox Value --- --

-- --- NEW: Get Property Handler --- --
local function handleGetProperty(data)
    local objectName = data.object_name
    local propertyName = data.property_name
    local requestId = data.request_id

    local resultPayload = {}

    if not objectName or not propertyName then
        resultPayload.error = "Missing object_name or property_name in get_property data."
    else
        local target = findObjectFromPath(objectName)
        if not target then
            resultPayload.error = "Object not found: " .. objectName
        else
            print(string.format("Vibe Blocks MCP Plugin: Getting property '%s' on %s (%s) for request ID %s", propertyName, target.Name, target.ClassName, requestId or "N/A"))
            local success, value = pcall(function() 
                return target[propertyName] 
            end)

            if success then
                print(string.format("  - Raw value type: %s", typeof(value)))
                -- Serialize the value for JSON transport
                local serializeSuccess, serializedResult = pcall(serializeValue, value)
                if serializeSuccess then
                    resultPayload.value = serializedResult
                    print("  - Serialized value sent.")
                else
                    resultPayload.error = "Failed to serialize property value: " .. tostring(serializedResult) -- serializedResult is error message here
                    print("  - Error serializing: " .. tostring(serializedResult))
                end
            else
                resultPayload.error = "Error accessing property: " .. tostring(value) -- value is error message here
                print("  - Error accessing property: " .. tostring(value))
            end
        end
    end

    -- Send the result/error back to the server
    if requestId then
        sendResultToServer(requestId, resultPayload)
    else
        print("Vibe Blocks MCP Plugin: Warning - No request_id found in get_property data. Cannot report result back.")
    end
end
-- --- END: Get Property Handler --- --

-- --- NEW: Edit Script Handler --- --
local function handleEditScript(data)
    local scriptPath = data.script_path
    local newScriptCode = data.script_code
    local requestId = data.request_id

    local resultPayload = {}

    if not scriptPath or not newScriptCode then
        resultPayload.error = "Missing script_path or script_code in edit_script data."
    else
        local targetScript = findObjectFromPath(scriptPath)
        if not targetScript then
            resultPayload.error = "Script not found at path: " .. scriptPath
        elseif not (targetScript:IsA("Script") or targetScript:IsA("LocalScript")) then
             resultPayload.error = "Target object is not a Script or LocalScript: " .. targetScript.ClassName
        else
            print(string.format("Vibe Blocks MCP Plugin: Editing script '%s' for request ID %s", targetScript:GetFullName(), requestId or "N/A"))
            local success, err = pcall(function() 
                targetScript.Source = newScriptCode
            end)

            if success then
                resultPayload.success = true
                print("  - Script source updated successfully.")
            else
                resultPayload.error = "Error setting script source: " .. tostring(err)
                print("  - Error setting script source: " .. tostring(err))
            end
        end
    end

    -- Send the result/error back to the server
    if requestId then
        sendResultToServer(requestId, resultPayload)
    else
        print("Vibe Blocks MCP Plugin: Warning - No request_id found in edit_script data. Cannot report result back.")
    end
end
-- --- END: Edit Script Handler --- --

-- --- NEW: Delete Script Handler --- --
local function handleDeleteScript(data)
    local scriptPath = data.script_path
    local requestId = data.request_id

    local resultPayload = {}

    if not scriptPath then
        resultPayload.error = "Missing script_path in delete_script data."
    else
        local targetScript = findObjectFromPath(scriptPath)
        if not targetScript then
            resultPayload.error = "Script not found at path: " .. scriptPath
        elseif not (targetScript:IsA("Script") or targetScript:IsA("LocalScript")) then
             resultPayload.error = "Target object is not a Script or LocalScript: " .. targetScript.ClassName
        else
            local fullName = targetScript:GetFullName()
            print(string.format("Vibe Blocks MCP Plugin: Deleting script '%s' for request ID %s", fullName, requestId or "N/A"))
            local success, err = pcall(function() 
                targetScript:Destroy()
            end)

            if success then
                resultPayload.success = true
                print("  - Script deleted successfully.")
            else
                resultPayload.error = "Error deleting script: " .. tostring(err)
                print("  - Error deleting script: " .. tostring(err))
            end
        end
    end

    -- Send the result/error back to the server
    if requestId then
        sendResultToServer(requestId, resultPayload)
    else
        print("Vibe Blocks MCP Plugin: Warning - No request_id found in delete_script data. Cannot report result back.")
    end
end
-- --- END: Delete Script Handler --- --

-- --- NEW: Set Primary Part Handler --- --
local function handleSetPrimaryPart(data)
    local modelPath = data.model_path
    local partPath = data.part_path
    local requestId = data.request_id

    local resultPayload = {}

    if not modelPath or not partPath then
        resultPayload.error = "Missing model_path or part_path in set_primary_part data."
    else
        local model = findObjectFromPath(modelPath)
        local part = findObjectFromPath(partPath)

        if not model then
            resultPayload.error = "Model not found at path: " .. modelPath
        elseif not model:IsA("Model") then
            resultPayload.error = "Object at model_path is not a Model: " .. model.ClassName
        elseif not part then
            resultPayload.error = "Part not found at path: " .. partPath
        elseif not part:IsA("BasePart") then
            resultPayload.error = "Object at part_path is not a BasePart: " .. part.ClassName
        elseif not part:IsDescendantOf(model) then
            resultPayload.error = "Part at " .. partPath .. " is not a descendant of Model at " .. modelPath
        else
            print(string.format("Vibe Blocks MCP Plugin: Setting PrimaryPart of '%s' to '%s' for request ID %s", model:GetFullName(), part:GetFullName(), requestId or "N/A"))
            local success, err = pcall(function() 
                model.PrimaryPart = part
            end)

            if success then
                resultPayload.success = true
                print("  - PrimaryPart set successfully.")
            else
                resultPayload.error = "Error setting PrimaryPart property: " .. tostring(err)
                print("  - Error setting PrimaryPart: " .. tostring(err))
            end
        end
    end

    -- Send the result/error back to the server
    if requestId then
        sendResultToServer(requestId, resultPayload)
    else
        print("Vibe Blocks MCP Plugin: Warning - No request_id found in set_primary_part data. Cannot report result back.")
    end
end
-- --- END: Set Primary Part Handler --- --

-- --- NEW: Execute Script in Studio Handler --- --
local function handleExecuteScriptInStudio(data)
    local scriptCode = data.script_code
    local requestId = data.request_id

    local resultPayload = {
        output_lines = {},
        return_values = nil, -- Explicitly nil initially
        error_message = nil
    }

    if not scriptCode or type(scriptCode) ~= "string" then
        resultPayload.error_message = "Missing or invalid 'script_code' (must be a string)."
    else
        print(string.format("Vibe Blocks MCP Plugin: Executing script in Studio for request ID %s (Code: %s...)", requestId or "N/A", string.sub(scriptCode, 1, 50)))
        
        -- <<< NEW: Prepend standard globals to script code >>>
        local scriptToExecute = string.format("local game = game\nlocal Workspace = game:GetService(\"Workspace\")\n%s", scriptCode)
        print("  - Info: Prepended locals game/Workspace to script.")

        -- 1. Compile the MODIFIED script string
        local compiledFunc, compileError = loadstring(scriptToExecute)
        
        if not compiledFunc then
            resultPayload.error_message = "Compile Error: " .. tostring(compileError)
            print("  - Error during script compilation:", compileError)
        else
            -- 2. Prepare environment for execution (capture print)
            local capturedOutput = {}
            -- local originalPrint = print -- No longer need to save/restore global print
            
            -- <<< RE-INTRODUCE: Explicitly populate tempEnv with globals AND custom print >>>
            local tempEnv = {}
            -- Copy essential globals
            tempEnv.game = game
            tempEnv.workspace = workspace
            tempEnv.script = script 
            tempEnv.Instance = Instance
            tempEnv.Vector3 = Vector3
            tempEnv.Color3 = Color3
            tempEnv.BrickColor = BrickColor
            tempEnv.CFrame = CFrame
            tempEnv.Enum = Enum
            tempEnv.ipairs = ipairs
            tempEnv.pairs = pairs
            tempEnv.tostring = tostring
            tempEnv.tonumber = tonumber
            tempEnv.pcall = pcall -- Allow script to use pcall itself
            tempEnv.type = type
            tempEnv.select = select
            tempEnv.assert = assert
            tempEnv.warn = warn -- Capture warn?
            tempEnv.error = error -- Capture error?
            tempEnv.math = math
            tempEnv.table = table
            tempEnv.string = string
            tempEnv.os = os
            tempEnv.debug = debug
            
            -- Add our custom print DIRECTLY to the environment
            tempEnv.print = function(...)
                local args = {...}
                local lineParts = {}
                for i = 1, #args do
                    table.insert(lineParts, tostring(args[i]))
                end
                local line = table.concat(lineParts, "\t")
                table.insert(capturedOutput, line)
                -- Optional: print("  [Captured Print]:", line)
            end

            -- Set the environment for the function
            setfenv(compiledFunc, tempEnv)
            
            -- 3. Execute using pcall (should use print from tempEnv now)
            local executionSuccess, results = pcall(compiledFunc)

            -- 5. Process results
            resultPayload.output_lines = capturedOutput
            
            if not executionSuccess then
                resultPayload.error_message = "Runtime Error: " .. tostring(results) -- results is the error message here
                print("  - Error during script execution:", tostring(results))
            else 
                -- Execution succeeded, results contains return values
                print("  - Script execution successful.")
                local returnVals = {select("#", results), results} -- Get all return values
                if select("#", results) > 0 then
                    local serializedReturns = {}
                    for i = 1, select("#", results) do
                        local success, serialized = pcall(serializeValue, select(i, results))
                        if success then
                           table.insert(serializedReturns, serialized)
                        else
                           table.insert(serializedReturns, {type="SerializationError", error=tostring(serialized)})
                        end
                    end
                    resultPayload.return_values = serializedReturns
                    print("  - Captured", #serializedReturns, "return value(s).")
                else
                   print("  - Script returned no values.")
                end
            end
        end
    end

    -- Send the result/error back to the server
    if requestId then
        sendResultToServer(requestId, resultPayload)
    else
        print("Vibe Blocks MCP Plugin: Warning - No request_id found in execute_script_in_studio data. Cannot report result back.")
    end
end
-- --- END: Execute Script in Studio Handler --- --

-- --- NEW: Modify Children Handler --- --
local function handleModifyChildren(data)
    local parentPath = data.parent_path
    local propertyName = data.property_name
    local propertyValue = data.property_value -- This is already parsed Python object -> Lua table/primitive
    local nameFilter = data.child_name_filter
    local classFilter = data.child_class_filter
    local requestId = data.request_id

    local resultPayload = {
        affected_count = 0,
        errors = {},
        error_message = nil -- For fatal errors
    }

    -- 1. Find Parent
    local parentObject = findObjectFromPath(parentPath)
    if not parentObject then
        resultPayload.error_message = "Parent object not found at path: " .. parentPath
        print("Vibe Blocks MCP Plugin: Error - " .. resultPayload.error_message)
        if requestId then sendResultToServer(requestId, resultPayload) end
        return
    end

    print(string.format("Vibe Blocks MCP Plugin: Modifying children under '%s' for request ID %s", parentObject:GetFullName(), requestId or "N/A"))
    print(string.format("  - Filters: Name='%s', Class='%s'", nameFilter or "Any", classFilter or "Any"))
    print(string.format("  - Action: Set '%s'", propertyName))

    -- 2. Iterate and Modify Children
    local children = parentObject:GetChildren()
    for i, child in ipairs(children) do
        local childMatches = true

        -- Apply filters
        if nameFilter and child.Name ~= nameFilter then
            childMatches = false
        end
        if classFilter and child.ClassName ~= classFilter then
            childMatches = false
        end

        -- If filters pass, attempt modification
        if childMatches then
            local childFullName = child:GetFullName()
            print(string.format("  - Processing child: %s", childFullName))

            local success, err = pcall(function()
                 -- Reuse value processing logic from handleSetProperty
                local valueToConvert = propertyValue 
                if typeof(valueToConvert) == "string" then
                    if string.sub(valueToConvert, 1, 1) == "[" or string.sub(valueToConvert, 1, 1) == "{" then
                        local decodeSuccess, decodedTable = pcall(function() return HttpService:JSONDecode(valueToConvert) end)
                        if decodeSuccess and typeof(decodedTable) == "table" then
                            print("    - Info: Decoded string value for child.")
                            valueToConvert = decodedTable
                        else
                            print("    - Warning: String value for child looked like table/array but failed to decode.")
                        end
                    end
                end
                
                -- Convert value
                local robloxValue, convertError = convertToRobloxType(propertyName, valueToConvert)
                if convertError then
                    error("Value conversion failed: " .. convertError)
                end
                
                -- Assign value
                child[propertyName] = robloxValue
                print(string.format("    - Successfully set '%s' to type %s", propertyName, typeof(robloxValue)))
            end)

            if success then
                resultPayload.affected_count = resultPayload.affected_count + 1
            else
                local errorMsg = string.format("Failed on '%s': %s", childFullName, tostring(err))
                print("    - ERROR: " .. errorMsg)
                table.insert(resultPayload.errors, errorMsg)
            end
        end
    end

    print(string.format("Vibe Blocks MCP Plugin: Finished modifying children. Affected: %d, Errors: %d", resultPayload.affected_count, #resultPayload.errors))

    -- 3. Send Result
    if requestId then
        sendResultToServer(requestId, resultPayload)
    else
        print("Vibe Blocks MCP Plugin: Warning - No request_id found in modify_children data. Cannot report result back.")
    end
end
-- --- END: Modify Children Handler --- --

local function executeCommand(commandData)
	local action = commandData.action
	print("Vibe Blocks MCP Plugin: Executing action - " .. (action or "nil"))

	if action == "get_property_studio" then
		local objPath = commandData.object_path
		local propName = commandData.property_name

		if not objPath or not propName then
			print("Vibe Blocks MCP Plugin: Invalid get_property_studio command - missing object_path or property_name")
			return
		end

		local success, result = pcall(function()
			-- Attempt to find the object using the path
			-- NOTE: This simple FindFirstChild approach won't work for nested paths like game.Workspace.Part
			-- We need a helper to traverse the path.
			-- Let's add a simple path finder
			local target = findObjectFromPath(objPath)

			if target then
				local value = target[propName]
				print(string.format("Vibe Blocks MCP Plugin: Property [%s.%s] = %s", objPath, propName, tostring(value)))
			else
				print(string.format("Vibe Blocks MCP Plugin: Target object not found for path: %s", objPath))
			end
		end)

		if not success then
			print(string.format("Vibe Blocks MCP Plugin: Error executing get_property_studio [%s.%s]: %s", objPath, propName, tostring(result)))
		end

	elseif action == "print_message" then -- Add a simple test action
		local message = commandData.message or "No message provided."
		print("Vibe Blocks MCP Plugin: Message from server -> " .. message)

	elseif action == "set_environment" then
		handleSetEnvironment(commandData.data) -- Pass the 'data' part of the command

	elseif action == "create_instance" then
		handleCreateInstance(commandData.data) -- Pass the 'data' part

	elseif action == "delete_instance" then
		handleDeleteInstance(commandData.data)

	elseif action == "set_property" then
		handleSetProperty(commandData.data)

	elseif action == "move_instance" then
		handleMoveInstance(commandData.data)

	elseif action == "clone_instance" then
		handleCloneInstance(commandData.data)

	elseif action == "create_script" then
		handleCreateScript(commandData.data)

	elseif action == "spawn_npc" then
		handleSpawnNpc(commandData.data)

	elseif action == "scale_model" then
		handleScaleModel(commandData.data)

	elseif action == "play_animation" then
		handlePlayAnimation(commandData.data)

	elseif action == "send_chat" then
		handleSendChat(commandData.data)

	elseif action == "teleport_player" then
		handleTeleportPlayer(commandData.data)

	elseif action == "set_player_position" then
		handleSetPlayerPosition(commandData.data)

	elseif action == "list_children" then
		handleListChildren(commandData.data)

	elseif action == "get_property" then
		handleGetProperty(commandData.data)

	elseif action == "find_instances" then
		handleFindInstances(commandData.data)

	elseif action == "edit_script" then
		handleEditScript(commandData.data)

	elseif action == "delete_script" then
		handleDeleteScript(commandData.data)

	elseif action == "set_primary_part" then
		handleSetPrimaryPart(commandData.data)

	elseif action == "execute_script_in_studio" then
		handleExecuteScriptInStudio(commandData.data)

	-- <<< ADD: New action routing >>>
	elseif action == "modify_children" then
		handleModifyChildren(commandData.data)

	else
		print("Vibe Blocks MCP Plugin: Unknown command action received: " .. tostring(action))
	end
end

local COMMAND_HANDLERS = {
	set_environment = handleSetEnvironment,
	create_instance = handleCreateInstance,
	delete_instance = handleDeleteInstance,
	set_property = handleSetProperty,
	get_property = handleGetProperty,
	list_children = handleListChildren,
	move_instance = handleMoveInstance,
	clone_instance = handleCloneInstance,
	create_script = handleCreateScript,
	spawn_npc = handleSpawnNpc,
	scale_model = handleScaleModel,
	play_animation = handlePlayAnimation,
	send_chat = handleSendChat,
	teleport_player = handleTeleportPlayer,
	set_player_position = handleSetPlayerPosition,
	find_instances = handleFindInstances,
	edit_script = handleEditScript,
	delete_script = handleDeleteScript,
	set_primary_part = handleSetPrimaryPart,
	execute_script_in_studio = handleExecuteScriptInStudio,
	modify_children = handleModifyChildren, -- <<< REGISTER: New handler >>>
}

local function pollServer()
	-- Check if running in Studio environment before proceeding
	if not RunService:IsStudio() then
		-- print("Vibe Blocks MCP Companion Plugin: Not in Studio environment. Polling disabled.") -- Reduce noise
		return
	end

	local currentTime = os.clock()
	if currentTime - lastPollTime < POLLING_INTERVAL then
		return -- Don't poll too frequently
	end
	lastPollTime = currentTime

	local success, responseBody = pcall(function()
		-- Attempt HTTP GET request
        -- IMPORTANT: This will fail in Play Solo client, handled by pcall
        return HttpService:GetAsync(SERVER_URL)
	end)

    if not success then
        -- Ignore specific HTTP errors expected when running in Play Solo client
        local errStr = tostring(responseBody) -- responseBody contains error object/string
        if string.find(errStr, "Http requests can only be executed by game server") then
            -- Silently ignore, this is expected in Play Solo client
            -- print("Vibe Blocks MCP Plugin: Http GetAsync skipped (Play Solo Client context).")
        else
            -- Log other unexpected errors
            print("Vibe Blocks MCP Plugin: Error polling server - " .. errStr)
        end
        return -- Stop processing if the GET failed for any reason
    end

	-- Process successful response
	local decodedSuccess, commandData = pcall(function()
		return HttpService:JSONDecode(responseBody)
	end)

	if not decodedSuccess then
		print("Vibe Blocks MCP Plugin: Error decoding JSON response from server - " .. tostring(commandData)) -- commandData is error msg
		return
	end

	-- Check if the decoded data is a table and not empty
	if type(commandData) == "table" and next(commandData) ~= nil then
			-- Use the structure expected from the Python server:
            -- {"action": "action_name", "data": { ... }, "request_id": "..."}
            local action = commandData.action
            local data = commandData.data
            local requestId = commandData.request_id -- Extract request_id

            print("Vibe Blocks MCP Plugin: Received command from server.")
            print("  - Action: " .. tostring(action))
            print("  - Request ID: " .. tostring(requestId)) -- Log the ID
            -- print("  - Data: " .. HttpService:JSONEncode(data)) -- Optional: Log data if needed, can be verbose

            if action and COMMAND_HANDLERS[action] then
                print("Vibe Blocks MCP Plugin: Executing action - " .. action)
                
                -- Prepare data for the handler, ensuring request_id is included
                local handlerData = data
                if type(handlerData) ~= "table" then
                     -- If original data wasn't a table, create one
                    handlerData = {} 
                end
                -- Add/overwrite request_id in the data passed to the handler
                handlerData.request_id = requestId
                
                -- Execute the handler
                local handlerSuccess, handlerError = pcall(COMMAND_HANDLERS[action], handlerData)
                
                if not handlerSuccess then
                    print("Vibe Blocks MCP Plugin: Error executing action '" .. action .. "': " .. tostring(handlerError))
                    -- If the handler failed, send an error result back if there's a request ID
                    if requestId then
                        sendResultToServer(requestId, { error = "Plugin error during action '" .. action .. "' execution: " .. tostring(handlerError) })
                    end
                else
                    -- Success! The handler itself (like list_children) is responsible for sending back results if needed.
                    print("Vibe Blocks MCP Plugin: Action '" .. action .. "' execution finished.")
                end
            else
                print("Vibe Blocks MCP Plugin: Warning - Unknown or missing action in command: " .. tostring(action))
                -- Send an error result back for unknown actions if there's a request ID
                if requestId then
                    sendResultToServer(requestId, { error = "Unknown action requested by server: " .. tostring(action) })
                end
            end
        else
            -- Empty response or non-table data, likely just no command queued
            -- print("Vibe Blocks MCP Plugin: No command received from server.") -- Reduce noise
        end

end

-- --- NEW: Log Handling Functions --- --

-- Function to send buffered logs to the Python server
local function sendLogsToServer()
	if isSendingLogs or #logsToSend == 0 then
		return -- Already sending or nothing to send
	end

	local currentTime = os.clock()
	-- Enforce send interval
	if currentTime - lastLogSendTime < SEND_INTERVAL then
		-- Optional: Could schedule a deferred send here instead of just dropping
		return
	end

	isSendingLogs = true
	lastLogSendTime = currentTime -- Update time *before* sending

	-- Take a batch (up to MAX_LOG_BATCH_SIZE)
	local batch = {}
	local count = math.min(#logsToSend, MAX_LOG_BATCH_SIZE)
	for i = 1, count do
		table.insert(batch, table.remove(logsToSend, 1)) -- Move from buffer to batch
	end

	-- Print only if actually sending (avoids client spam)
	if RunService:IsServer() then
		print("Vibe Blocks MCP Plugin: Sending", #batch, "logs to server...")
	end

	local success, response = pcall(function()
		local jsonData = HttpService:JSONEncode(batch)
		return HttpService:PostAsync(SERVER_LOG_ENDPOINT, jsonData, Enum.HttpContentType.ApplicationJson)
	end)

	if success then
		-- Log successful send only on server
		-- if RunService:IsServer() then print("Log send success.") end 
	else
		local errorString = tostring(response)
		-- Check if it's the expected client-side error
		if string.find(errorString, "Http requests can only be executed by game server") then
			-- This error is expected on the client during Play mode, do nothing or minimal log
			-- print("MCP Debug: Client log send blocked as expected.")
		else
			-- Log other unexpected errors
			warn("Vibe Blocks MCP Plugin: Failed to send logs to server:", errorString)
			-- Retry logic (keep this part)
			for i = #batch, 1, -1 do
				table.insert(logsToSend, 1, batch[i])
			end
		end
	end

	isSendingLogs = false

	-- If there are still logs left, immediately try sending another batch
	-- This handles cases where logs accumulate faster than the send interval allows clearing
	if #logsToSend > 0 then
		task.defer(sendLogsToServer)
	end
end

-- Function called by LogService event
local function onMessageOut(message, messageType)
	-- Avoid logging our own log sending messages
	if string.find(message, "Vibe Blocks MCP Plugin: Sending") then
		return
	end

	local logEntry = {
		message = message,
		log_type = tostring(messageType), -- Convert Enum::MessageType to string
		timestamp = os.clock() -- Use os.clock() for high-resolution timestamp
	}
	table.insert(logsToSend, logEntry)

	-- Trigger send mechanism (non-blocking)
	-- Use task.defer to ensure it runs after the current event processing
	-- The IsServer check is inside sendLogsToServer, so it's safe to defer always
	task.defer(sendLogsToServer)
end

-- --- END: Log Handling Functions --- --

-- Only run polling loop and connect log service in Studio
if RunService:IsStudio() then
	-- TODO: Add plugin button/UI later if needed
	RunService.Heartbeat:Connect(function() pollServer() end)
	print("Vibe Blocks MCP Companion Plugin: Started polling loop.")

	-- --- NEW: Connect to Log Service --- --
	LogService.MessageOut:Connect(onMessageOut)
	print("Vibe Blocks MCP Companion Plugin: Connected to LogService for log forwarding.")
	-- --- END: Connect to Log Service --- --
else
	print("Vibe Blocks MCP Companion Plugin: Not running polling loop or log forwarding (not in Studio).")
end

-- --- NEW: List Children Handler --- --
-- <<< Function definition moved above COMMAND_HANDLERS >>>
-- --- END: List Children Handler --- -- 