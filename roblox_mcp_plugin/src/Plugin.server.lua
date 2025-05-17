--[[ Plugin Main Script ]]

-- Roblox Services
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local Plugin = script:FindFirstAncestorOfClass("Plugin")

-- Constants
local SERVER_URL = "http://localhost:8001/plugin_command"
local POLLING_INTERVAL = 2 -- Seconds
local SERVER_RESULT_ENDPOINT = "http://localhost:8001/plugin_report_result"
local SERVER_LOG_ENDPOINT = "http://localhost:8001/receive_studio_logs"
local SEND_INTERVAL = 1.5
local MAX_LOG_BATCH_SIZE = 50

-- State variables
local lastPollTime = 0
local isEnabled = false -- Track if plugin is enabled
local toolbarButton = nil -- Store reference to toolbar button
local isConnected = false -- Track connection state
local wasConnected = false -- Track previous connection state
local showDebugLogs = false -- Track if debug logs should be shown
local pluginGui = nil -- Store reference to DockWidget
local connectButton = nil -- Store reference to Connect button
local debugToggle = nil -- Store reference to Debug toggle
local statusLabel = nil -- Store reference to status label
local styles = nil -- Store reference to UI styles

-- Log buffer
local logsToSend = {}
local isSendingLogs = false
local lastLogSendTime = 0

-- Debug log function that respects the showDebugLogs flag
local function debugLog(message)
    if showDebugLogs then
        print(message)
    end
end

-- Helper function to create UI styles
local function createStyles()
    local styles = {}
    
    -- Button styles
    styles.buttonHeight = 30
    styles.buttonWidth = 120
    styles.buttonColor = Color3.fromRGB(53, 53, 53)
    styles.buttonBorderColor = Color3.fromRGB(80, 80, 80)
    styles.buttonTextColor = Color3.fromRGB(255, 255, 255)
    styles.buttonFontSize = Enum.FontSize.Size14
    
    -- Button states
    styles.connectedColor = Color3.fromRGB(46, 124, 46) -- 緑色
    styles.disconnectedColor = Color3.fromRGB(124, 46, 46) -- 赤色
    
    -- Toggle styles
    styles.togglePadding = 5
    styles.toggleHeight = 30
    
    -- Widget styles
    styles.widgetSize = Vector2.new(300, 200)
    styles.widgetTitle = "Vibe Blocks MCP"
    styles.backgroundColor = Color3.fromRGB(40, 40, 40)
    styles.textColor = Color3.fromRGB(240, 240, 240)
    
    -- General padding
    styles.padding = 10
    
    return styles
end

-- Create UI elements
local function createUI()
    styles = createStyles()
    
    -- Create DockWidgetPluginGuiInfo
    local widgetInfo = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Float,  -- Widget will be freely floating
        true,   -- Widget will be initially enabled
        false,  -- Override previous enabled state
        styles.widgetSize.X, styles.widgetSize.Y,  -- Size
        styles.widgetSize.X, styles.widgetSize.Y   -- Min Size
    )
    
    -- Create DockWidget
    pluginGui = Plugin:CreateDockWidgetPluginGui("VibeBlocksMCPWidget", widgetInfo)
    pluginGui.Title = styles.widgetTitle
    pluginGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    -- Create UI layout
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(1, 0, 1, 0)
    mainFrame.BackgroundColor3 = styles.backgroundColor
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = pluginGui
    
    -- Create padding for main frame
    local mainPadding = Instance.new("UIPadding")
    mainPadding.PaddingLeft = UDim.new(0, styles.padding)
    mainPadding.PaddingRight = UDim.new(0, styles.padding)
    mainPadding.PaddingTop = UDim.new(0, styles.padding)
    mainPadding.PaddingBottom = UDim.new(0, styles.padding)
    mainPadding.Parent = mainFrame
    
    -- Create layout for main frame
    local mainLayout = Instance.new("UIListLayout")
    mainLayout.Padding = UDim.new(0, styles.padding)
    mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
    mainLayout.Parent = mainFrame
    
    -- Title label
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0, 30)
    titleLabel.Text = "Vibe Blocks MCP Controller"
    titleLabel.TextColor3 = styles.textColor
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextSize = 18
    titleLabel.Font = Enum.Font.SourceSansBold
    titleLabel.LayoutOrder = 1
    titleLabel.Parent = mainFrame
    
    -- Status label
    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 20)
    statusLabel.Text = "Status: Disconnected"
    statusLabel.TextColor3 = styles.textColor
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextSize = 14
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.LayoutOrder = 2
    statusLabel.Parent = mainFrame
    
    -- Connection button
    connectButton = Instance.new("TextButton")
    connectButton.Size = UDim2.new(0, styles.buttonWidth, 0, styles.buttonHeight)
    connectButton.Position = UDim2.new(0, 0, 0, 0)
    connectButton.Text = "Connect"
    connectButton.TextColor3 = styles.buttonTextColor
    connectButton.BackgroundColor3 = styles.disconnectedColor
    connectButton.BorderColor3 = styles.buttonBorderColor
    connectButton.TextSize = 14
    connectButton.Font = Enum.Font.SourceSansBold
    connectButton.LayoutOrder = 3
    connectButton.Parent = mainFrame
    
    -- Debug toggle container
    local toggleContainer = Instance.new("Frame")
    toggleContainer.Size = UDim2.new(1, 0, 0, styles.toggleHeight)
    toggleContainer.BackgroundTransparency = 1
    toggleContainer.LayoutOrder = 4
    toggleContainer.Parent = mainFrame
    
    -- Debug toggle label
    local toggleLabel = Instance.new("TextLabel")
    toggleLabel.Size = UDim2.new(0.7, 0, 1, 0)
    toggleLabel.Position = UDim2.new(0, 0, 0, 0)
    toggleLabel.Text = "Show Debug Logs"
    toggleLabel.TextColor3 = styles.textColor
    toggleLabel.TextXAlignment = Enum.TextXAlignment.Left
    toggleLabel.BackgroundTransparency = 1
    toggleLabel.TextSize = 14
    toggleLabel.Font = Enum.Font.SourceSans
    toggleLabel.Parent = toggleContainer
    
    -- Debug toggle button
    debugToggle = Instance.new("TextButton")
    debugToggle.Size = UDim2.new(0, 50, 0, 20)
    debugToggle.Position = UDim2.new(0.8, 0, 0.5, -10)
    debugToggle.Text = ""
    debugToggle.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    debugToggle.BorderColor3 = styles.buttonBorderColor
    debugToggle.Parent = toggleContainer
    
    -- Debug toggle indicator
    local toggleIndicator = Instance.new("Frame")
    toggleIndicator.Size = UDim2.new(0, 16, 0, 16)
    toggleIndicator.Position = UDim2.new(0, 2, 0.5, -8)
    toggleIndicator.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
    toggleIndicator.BorderSizePixel = 0
    toggleIndicator.Name = "Indicator"
    toggleIndicator.Parent = debugToggle
    
    -- Server URL info
    local urlLabel = Instance.new("TextLabel")
    urlLabel.Size = UDim2.new(1, 0, 0, 20)
    urlLabel.Text = "Server: " .. SERVER_URL
    urlLabel.TextColor3 = styles.textColor
    urlLabel.BackgroundTransparency = 1
    urlLabel.TextSize = 12
    urlLabel.Font = Enum.Font.SourceSans
    urlLabel.LayoutOrder = 5
    urlLabel.Parent = mainFrame
    
    -- Update status function
    local function updateStatus()
        if not connectButton or not statusLabel then return end
        
        if isConnected then
            statusLabel.Text = "Status: Connected"
            statusLabel.TextColor3 = Color3.fromRGB(85, 255, 85) -- Green
            connectButton.Text = "Disconnect"
            connectButton.BackgroundColor3 = styles.connectedColor
        else
            statusLabel.Text = "Status: Disconnected"
            statusLabel.TextColor3 = Color3.fromRGB(255, 85, 85) -- Red
            connectButton.Text = "Connect"
            connectButton.BackgroundColor3 = styles.disconnectedColor
        end
    end
    
    -- Update debug toggle function
    local function updateDebugToggle()
        if showDebugLogs then
            toggleIndicator.Position = UDim2.new(0, 32, 0.5, -8)
            debugToggle.BackgroundColor3 = Color3.fromRGB(46, 124, 46) -- Green
        else
            toggleIndicator.Position = UDim2.new(0, 2, 0.5, -8)
            debugToggle.BackgroundColor3 = Color3.fromRGB(80, 80, 80) -- Gray
        end
    end
    
    -- Connect toggle debug logs button
    debugToggle.MouseButton1Click:Connect(function()
        showDebugLogs = not showDebugLogs
        updateDebugToggle()
        
        -- Log change in state
        if showDebugLogs then
            print("Vibe Blocks MCP Plugin: Debug logs enabled")
        else
            print("Vibe Blocks MCP Plugin: Debug logs disabled")
        end
    end)
    
    -- Connect button
    connectButton.MouseButton1Click:Connect(function()
        print("Vibe Blocks MCP Plugin: Connectボタンがクリックされました")
        
        isEnabled = not isEnabled
        
        if isEnabled then
            -- サーバー接続処理を直接実装
            print("Vibe Blocks MCP Plugin: 有効化")
            print("Vibe Blocks MCP Plugin: サーバー接続テスト開始...")
            
            -- サーバー接続テスト
            local success, response = pcall(function()
                return HttpService:GetAsync(SERVER_URL)
            end)
            
            local previousState = isConnected
            isConnected = success
            
            -- 接続状態の表示
            if isConnected ~= previousState then
                if isConnected then
                    print("Vibe Blocks MCP Plugin: サーバーに接続しました")
                else
                    print("Vibe Blocks MCP Plugin: サーバー接続失敗 - " .. tostring(response))
                end
            end
        else
            isConnected = false
            print("Vibe Blocks MCP Plugin: 無効化")
        end
        
        -- UI状態を更新
        if isConnected then
            statusLabel.Text = "Status: Connected"
            statusLabel.TextColor3 = Color3.fromRGB(85, 255, 85) -- Green
            connectButton.Text = "Disconnect"
            connectButton.BackgroundColor3 = styles.connectedColor
        else
            statusLabel.Text = "Status: Disconnected"
            statusLabel.TextColor3 = Color3.fromRGB(255, 85, 85) -- Red
            connectButton.Text = "Connect"
            connectButton.BackgroundColor3 = styles.disconnectedColor
        end
    end)
    
    -- Set initial states
    updateStatus()
    updateDebugToggle()
    
    return pluginGui
end

-- 変数定義
local lastPollTime = 0
local isEnabled = false -- Track if plugin is enabled
local toolbarButton = nil -- Store reference to toolbar button
local isConnected = false -- Track connection state
local wasConnected = false -- Track previous connection state

-- 接続状態変化のログ関数は各場所で直接実装

-- 接続状態をテストする関数
local function testConnection()
    print("Vibe Blocks MCP Plugin: testConnection関数が呼び出されました")
    
    if not connectButton then 
        print("Vibe Blocks MCP Plugin: エラー - connectButtonが初期化されていません")
        return 
    end
    
    debugLog("Vibe Blocks MCP Plugin: DEBUG - 接続テスト実行開始")
    
    local success, response = pcall(function()
        return HttpService:GetAsync(SERVER_URL)
    end)
    
    local previousState = isConnected
    isConnected = success
    
    -- 詳細デバッグ
    if success then
        debugLog("Vibe Blocks MCP Plugin: DEBUG - サーバー応答: " .. 
            (response == "" and "空" or 
            string.sub(response, 1, 100) .. (string.len(response) > 100 and "..." or "")))
            
        -- レスポンスがJSONかどうか確認
        local jsonSuccess, jsonData = pcall(function()
            return HttpService:JSONDecode(response)
        end)
        
        if jsonSuccess then
            if type(jsonData) == "table" then
                if next(jsonData) == nil then
                    debugLog("Vibe Blocks MCP Plugin: DEBUG - サーバーから空のオブジェクト/配列を受信")
                else
                    debugLog("Vibe Blocks MCP Plugin: DEBUG - サーバーからJSONオブジェクトを受信")
                end
            end
        else
            debugLog("Vibe Blocks MCP Plugin: DEBUG - サーバーからの応答はJSON形式ではありません")
        end
    else
        debugLog("Vibe Blocks MCP Plugin: DEBUG - 接続テスト失敗: " .. tostring(response))
    end
    
    -- 接続状態が変わった時だけメッセージを表示
    if isConnected ~= previousState then
        if isConnected then
            print("Vibe Blocks MCP Plugin: Successfully connected to server")
        else
            print("Vibe Blocks MCP Plugin: Failed to connect to server - " .. tostring(response))
        end
    end
    
    -- UIの更新
    if _G.updateMCPPluginStatus then
        _G.updateMCPPluginStatus()
    end
end

-- Create toolbar button
local function createToolbarButton()
    local toolbar = Plugin:CreateToolbar("Vibe Blocks MCP")
    local button = toolbar:CreateButton(
        "VibeBlocksMCP", -- Button ID
        "VibeBlocksMCP", -- Text
        "rbxassetid://87405097442038" -- Icon
    )
    
    -- Set initial state
    button:SetActive(false)
    
    -- HTTPサービスの状態確認
    local httpEnabled = false
    local httpStatusMsg = "不明"
    
    local success, status = pcall(function()
        return HttpService.HttpEnabled
    end)
    
    if success then
        httpEnabled = status
        httpStatusMsg = httpEnabled and "有効" or "無効"
    else
        httpStatusMsg = "エラー: " .. tostring(status)
    end
    
    print("Vibe Blocks MCP Plugin: 診断情報")
    print("  - プラグインID: " .. Plugin.Name)
    print("  - HttpService状態: " .. httpStatusMsg)
    print("  - 実行環境: " .. (RunService:IsStudio() and "Roblox Studio" or "その他"))
    print("  - サーバーURL: " .. SERVER_URL)
    print("  - 結果送信URL: " .. SERVER_RESULT_ENDPOINT)
    
    -- Connect click event
    button.Click:Connect(function()
        -- ウィンドウを表示または非表示
        if not pluginGui then
            -- まだUI作成されていない場合、作成
            pluginGui = createUI()
        else
            -- すでに作成されている場合は表示/非表示を切り替え
            pluginGui.Enabled = not pluginGui.Enabled
        end
        
        -- ウィンドウの表示状態に合わせてボタンの状態を設定
        button:SetActive(pluginGui.Enabled)
        
        -- ウィンドウを表示したことをログに出力
        if pluginGui.Enabled then
            print("Vibe Blocks MCP Plugin: ウィンドウを表示")
        else
            print("Vibe Blocks MCP Plugin: ウィンドウを非表示")
        end
    end)
    
    return button
end

-- Initialize toolbar button
toolbarButton = createToolbarButton()


-- --- Helper: Send Result Back to Server --- --
local function sendResultToServer(requestId, resultData)
	-- 詳細なデバッグ出力
	print("Vibe Blocks MCP Plugin: DEBUG - 結果送信開始 requestId=" .. tostring(requestId))
	
	if not requestId then
		print("Vibe Blocks MCP Plugin: エラー - リクエストIDなしで結果を送信できません")
		return
	end
	
	local payload = {
		request_id = requestId,
		result = resultData or {} -- resultDataがnilの場合は空のテーブルを使用
	}
	
	-- JSONエンコード処理
	local success, encodedPayload = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	
	if not success then
		print("Vibe Blocks MCP Plugin: エラー - JSONエンコード失敗: " .. tostring(encodedPayload))
		return
	end
	
	print("Vibe Blocks MCP Plugin: DEBUG - POST送信準備完了: エンドポイント=" .. SERVER_RESULT_ENDPOINT .. " データ長=" .. string.len(encodedPayload))
	
	-- HTTPリクエスト送信
	local postSuccess, postResult = pcall(function()
		print("Vibe Blocks MCP Plugin: DEBUG - HTTPリクエスト実行前")
		local result = HttpService:PostAsync(
			SERVER_RESULT_ENDPOINT,
			encodedPayload,
			Enum.HttpContentType.ApplicationJson,
			false
		)
		print("Vibe Blocks MCP Plugin: DEBUG - HTTPリクエスト実行後: 結果長=" .. (result and string.len(result) or 0))
		return result
	end)
	
	if postSuccess then
		print("Vibe Blocks MCP Plugin: 結果送信成功 - " .. tostring(requestId))
	else
		print("Vibe Blocks MCP Plugin: エラー - 結果送信失敗: " .. tostring(postResult))
		-- HTTP権限エラーの詳細検出
		local errorMessage = tostring(postResult)
		if string.find(errorMessage, "not allowed") or 
		   string.find(errorMessage, "permission") or
		   string.find(errorMessage, "HttpService") or
		   string.find(errorMessage, "must be enabled") then
			print("Vibe Blocks MCP Plugin: ===== HTTP権限エラー =====")
			print("Vibe Blocks MCP Plugin: プラグイン設定でHTTP権限確認が必要です。")
			print("Vibe Blocks MCP Plugin: 1. Roblox Studioメニューから [ファイル]->[スタジオ設定] を開く")
			print("Vibe Blocks MCP Plugin: 2. [セキュリティ]タブの[APIサービス]セクションで")
			print("Vibe Blocks MCP Plugin: 3. 'プラグインのHTTPリクエストを許可する'をオンにしてください")
		end
	end
end
-- --- End Helper: Send Result --- --

-- --- Helper: Get Full Path for an Instance --- --
local function getFullPath(instance)
	if instance then
		return instance:GetFullName()
	else
		return "nil"
	end
end
-- --- End Helper: Get Full Path --- --

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
	if not commandData then
		print("Vibe Blocks MCP Plugin: エラー - 無効なコマンドデータ (nil)")
		return
	end
	
	local action = commandData.action
	
	if not action then
		print("Vibe Blocks MCP Plugin: エラー - コマンドにactionがありません")
		print("Vibe Blocks MCP Plugin: DEBUG - 受信データ: " .. HttpService:JSONEncode(commandData))
		return
	end
	
	print("Vibe Blocks MCP Plugin: コマンド実行開始 - " .. action)
	print("Vibe Blocks MCP Plugin: リクエストID - " .. (commandData.request_id or "なし"))

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
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleSetEnvironment(data) -- Pass the 'data' part of the command

	elseif action == "create_instance" then
		local className = commandData.data.class_name
		local parentName = commandData.data.parent_name
		local properties = commandData.data.properties
		local requestId = commandData.request_id
		
		if not className or not parentName then
			print("Vibe Blocks MCP Plugin: エラー - create_instanceに必須パラメータがありません")
			print("  class_name: " .. tostring(className))
			print("  parent_name: " .. tostring(parentName))
			-- エラー結果を送信
			if requestId then
				sendResultToServer(requestId, {success = false, error = "Missing required parameters"})
			end
			return
		end
		
		-- 詳細デバッグ
		print("Vibe Blocks MCP Plugin: DEBUG - create_instance実行")
		print("  class_name: " .. className)
		print("  parent_name: " .. parentName) 
		print("  request_id: " .. tostring(requestId))
		if properties then
			print("  properties: " .. HttpService:JSONEncode(properties))
		end
		
		local success, result = pcall(function()
			local parent = findObjectFromPath(parentName)
			
			if not parent then
				print("Vibe Blocks MCP Plugin: エラー - 親オブジェクト検索失敗: " .. parentName)
				return {success = false, error = "Parent object not found: " .. parentName}
			end
			
			print("Vibe Blocks MCP Plugin: DEBUG - 親オブジェクト検出: " .. parent:GetFullName())
			local newInstance = Instance.new(className)
			
			-- Apply properties if available
			if properties then
				print("Vibe Blocks MCP Plugin: DEBUG - プロパティ設定開始")
				
				-- 最初にShapeとBrickColorを設定（これらは変換が必要）
				if properties.Shape then
					print("  設定: Shape = " .. tostring(properties.Shape))
					if properties.Shape == "Block" then
						newInstance.Shape = Enum.PartType.Block
						print("  適用: Shape = Enum.PartType.Block")
					elseif properties.Shape == "Ball" then
						newInstance.Shape = Enum.PartType.Ball
						print("  適用: Shape = Enum.PartType.Ball")
					elseif properties.Shape == "Cylinder" then
						newInstance.Shape = Enum.PartType.Cylinder
						print("  適用: Shape = Enum.PartType.Cylinder")
					else
						pcall(function() newInstance.Shape = properties.Shape end)
					end
				end
				
				if properties.BrickColor then
					print("  設定: BrickColor = " .. tostring(properties.BrickColor))
					pcall(function() 
						newInstance.BrickColor = BrickColor.new(properties.BrickColor)
						print("  適用: BrickColor = " .. newInstance.BrickColor.Name)
					end)
				end
				
				-- 他のすべてのプロパティを設定
				for propName, propValue in pairs(properties) do
					if propName ~= "Shape" and propName ~= "BrickColor" then
						print("  設定: " .. propName .. " = " .. tostring(propValue))
						
						-- Vector3の特別処理
						if propName == "Position" or propName == "Size" then
							if type(propValue) == "table" and #propValue == 3 then
								-- 配列形式 [x,y,z]
								pcall(function()
									newInstance[propName] = Vector3.new(propValue[1], propValue[2], propValue[3])
									print("  適用: " .. propName .. " = Vector3(" .. 
									      tostring(propValue[1]) .. ", " .. 
									      tostring(propValue[2]) .. ", " .. 
									      tostring(propValue[3]) .. ")")
								end)
							else
								-- 通常の代入を試行
								pcall(function() newInstance[propName] = propValue end)
							end
						else
							-- その他のプロパティは通常代入
							pcall(function() newInstance[propName] = propValue end)
						end
					end
				end
			end
			
			newInstance.Parent = parent
			local path = getFullPath(newInstance)
			print("Vibe Blocks MCP Plugin: DEBUG - インスタンス作成完了: " .. path)
			return {success = true, path = path}
		end)
		
		-- 実行結果をすぐに送信
		if success then
			print("Vibe Blocks MCP Plugin: 成功 - インスタンス作成: " .. className)
			-- 成功結果の送信
			if requestId then
				print("Vibe Blocks MCP Plugin: DEBUG - 結果送信実行 (成功)")
				sendResultToServer(requestId, result)
			else
				print("Vibe Blocks MCP Plugin: 警告 - リクエストIDなし、結果送信スキップ")
			end
		else
			print("Vibe Blocks MCP Plugin: エラー - インスタンス作成失敗: " .. tostring(result))
			-- エラー結果の送信
			if requestId then
				print("Vibe Blocks MCP Plugin: DEBUG - 結果送信実行 (エラー)")
				sendResultToServer(requestId, {success = false, error = tostring(result)})
			else
				print("Vibe Blocks MCP Plugin: 警告 - リクエストIDなし、結果送信スキップ")
			end
		end

	elseif action == "delete_instance" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleDeleteInstance(data)

	elseif action == "set_property" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleSetProperty(data)

	elseif action == "move_instance" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleMoveInstance(data)

	elseif action == "clone_instance" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleCloneInstance(data)

	elseif action == "create_script" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleCreateScript(data)

	elseif action == "spawn_npc" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleSpawnNpc(data)

	elseif action == "scale_model" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleScaleModel(data)

	elseif action == "play_animation" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handlePlayAnimation(data)

	elseif action == "send_chat" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleSendChat(data)

	elseif action == "teleport_player" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleTeleportPlayer(data)

	elseif action == "set_player_position" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleSetPlayerPosition(data)

	elseif action == "list_children" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleListChildren(data)

	elseif action == "get_property" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleGetProperty(data)

	elseif action == "find_instances" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleFindInstances(data)

	elseif action == "edit_script" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleEditScript(data)

	elseif action == "delete_script" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleDeleteScript(data)

	elseif action == "set_primary_part" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleSetPrimaryPart(data)

	elseif action == "execute_script_in_studio" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleExecuteScriptInStudio(data)

	-- <<< ADD: New action routing >>>
	elseif action == "modify_children" then
		-- request_idをdata内に移動
		local data = commandData.data or {}
		data.request_id = commandData.request_id
		handleModifyChildren(data)

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
    if not isEnabled then
        return
    end
    
    local currentTime = tick()
    if currentTime - lastPollTime < POLLING_INTERVAL then
        return
    end
    
    lastPollTime = currentTime
    
    local success, response = pcall(function()
        return HttpService:GetAsync(SERVER_URL)
    end)
    
    wasConnected = isConnected
    isConnected = success
    
    -- 接続状態が変化した時のみログを表示し、UIを更新
    if isConnected ~= wasConnected then
        if isConnected then
            print("Vibe Blocks MCP Plugin: Connected to server")
        else
            print("Vibe Blocks MCP Plugin: Lost connection to server - " .. tostring(response))
        end
        
        -- UIの更新
        updateStatus()
    end
    
    -- レスポンスがある場合は処理を実行
    if success and response and response ~= "" then
        -- レスポンスの内容確認
        if response == "{}" or response == "[]" then
            -- 空のオブジェクトや配列は無視
            debugLog("Vibe Blocks MCP Plugin: DEBUG - 空のレスポンス受信、処理スキップ")
            return
        end
        
        debugLog("Vibe Blocks MCP Plugin: DEBUG - コマンド受信: " .. string.sub(response, 1, 100) .. (string.len(response) > 100 and "..." or ""))
        
        local decodeSuccess, decodedCommand = pcall(function()
            return HttpService:JSONDecode(response)
        end)
        
        if not decodeSuccess then
            debugLog("Vibe Blocks MCP Plugin: エラー - JSONデコード失敗: " .. tostring(decodedCommand))
            return
        end
        
        -- 配列の場合は最初の要素を使用（サーバーが配列として送ってくる場合）
        if decodedCommand and type(decodedCommand) == "table" then
            if #decodedCommand > 0 then
                -- 配列として送られてきた場合、最初の要素を使用
                debugLog("Vibe Blocks MCP Plugin: DEBUG - 配列形式のレスポンス検出、最初の要素を使用")
                decodedCommand = decodedCommand[1]
            elseif next(decodedCommand) == nil then
                -- 空のテーブル/オブジェクトの場合
                debugLog("Vibe Blocks MCP Plugin: DEBUG - 空のオブジェクト受信、処理スキップ")
                return
            end
        end
        
        if decodedCommand and decodedCommand.action then
            debugLog("Vibe Blocks MCP Plugin: DEBUG - コマンドタイプ: " .. decodedCommand.action)
            if decodedCommand.request_id then
                debugLog("Vibe Blocks MCP Plugin: DEBUG - リクエストID: " .. decodedCommand.request_id)
            end
            
            -- コマンド実行
            executeCommand(decodedCommand)
        else
            debugLog("Vibe Blocks MCP Plugin: エラー - コマンドにactionがありません")
            debugLog("Vibe Blocks MCP Plugin: DEBUG - 受信データ: " .. response)
        end
    end
end

local function sendLogsToServer()
    -- プラグインが無効化されている場合は何もしない
    if not isEnabled then
        return
    end

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
    lastLogSendTime = currentTime

    -- If there are still logs left, immediately try sending another batch
    -- This handles cases where logs accumulate faster than the send interval allows clearing
    if #logsToSend > 0 then
        task.defer(sendLogsToServer)
    end
end

-- Function called by LogService event
local function onMessageOut(message, messageType)
    -- プラグインが無効化されている場合はログをバッファに追加しない
    if not isEnabled then
        return
    end

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
    -- Connect to Log Service
    LogService.MessageOut:Connect(onMessageOut)
    -- Start polling loop
    RunService.Heartbeat:Connect(pollServer)
else
    -- Not in Studio, nothing to do
end

-- --- NEW: List Children Handler --- --
-- <<< Function definition moved above COMMAND_HANDLERS >>>
-- --- END: List Children Handler --- 