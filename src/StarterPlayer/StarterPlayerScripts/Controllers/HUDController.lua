-- HUDController: builds and updates the whole HUD from replicated attributes and remotes.
-- Phase/timer, campfire, courage, inventory, status, objectives, toasts, SUNNY subtitles,
-- clue cards, upgrade panel, results screen and danger vignette.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("Types"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HUDController = {}

local player = Players.LocalPlayer
local controllers
local state -- GameState folder
local gui
local ui = {}
local stock = {}
local levels = {}
local toasts = {}
local MAX_TOASTS = 4

local FONT = Enum.Font.FredokaOne
local FONT_BODY = Enum.Font.GothamMedium
local C = {
	Panel = Color3.fromRGB(20, 26, 34),
	Text = Color3.fromRGB(245, 240, 230),
	Muted = Color3.fromRGB(170, 175, 185),
	Warm = Color3.fromRGB(255, 190, 100),
	Sunny = Color3.fromRGB(255, 214, 64),
	Danger = Color3.fromRGB(255, 110, 170),
	Good = Color3.fromRGB(120, 230, 140),
	Night = Color3.fromRGB(120, 220, 210),
	Button = Color3.fromRGB(255, 170, 60),
}

local TOAST_COLORS = {
	info = C.Text,
	gather = C.Good,
	success = C.Good,
	warn = C.Warm,
	danger = C.Danger,
	mystery = C.Night,
	radio = Color3.fromRGB(190, 255, 160),
}

-------------------------------------------------------------------------------
-- UI helpers
-------------------------------------------------------------------------------

local function make(className: string, props)
	local inst = Instance.new(className)
	local parent = props.Parent
	props.Parent = nil
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function corner(parent: Instance, radius: number?)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 10), Parent = parent })
end

local function padding(parent: Instance, px: number)
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		Parent = parent,
	})
end

local function panel(props)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Panel
	props.BackgroundTransparency = props.BackgroundTransparency or 0.25
	props.BorderSizePixel = 0
	local frame = make("Frame", props)
	corner(frame, 12)
	return frame
end

local function text(props)
	props.BackgroundTransparency = 1
	props.Font = props.Font or FONT_BODY
	props.TextColor3 = props.TextColor3 or C.Text
	props.TextSize = props.TextSize or 16
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextWrapped = true
	return make("TextLabel", props)
end

local function button(props)
	props.BackgroundColor3 = props.BackgroundColor3 or C.Button
	props.Font = FONT
	props.TextColor3 = props.TextColor3 or Color3.fromRGB(40, 25, 10)
	props.TextSize = props.TextSize or 20
	props.AutoButtonColor = true
	props.BorderSizePixel = 0
	local b = make("TextButton", props)
	corner(b, 10)
	return b
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function formatCost(cost): string
	local parts = {}
	for _, name in ipairs(GameConfig.ResourceOrder) do
		local amount = cost[name]
		if amount and amount > 0 then
			table.insert(parts, string.format("%d %s", amount, GameConfig.Resources[name].DisplayName))
		end
	end
	if #parts == 0 then
		return "Free"
	end
	return table.concat(parts, ", ")
end

-------------------------------------------------------------------------------
-- Build
-------------------------------------------------------------------------------

local function buildTopBar()
	local top = panel({ Name = "TopBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(300, 74), Parent = gui })
	ui.Phase = text({ Name = "Phase", Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 4), Font = FONT, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, Text = "WAITING", Parent = top })
	ui.Timer = text({ Name = "Timer", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 38), Font = FONT, TextSize = 22, TextColor3 = C.Warm, TextXAlignment = Enum.TextXAlignment.Center, Text = "0:00", Parent = top })
	ui.TestBadge = text({ Name = "TestBadge", Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, 2), TextSize = 12, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, Text = "", Parent = top })
end

local function buildLeftPanel()
	local left = panel({ Name = "Camp", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(220, 228), Parent = gui })
	padding(left, 10)
	text({ Size = UDim2.new(1, 0, 0, 20), Font = FONT, TextSize = 18, TextColor3 = C.Warm, Text = "CAMPFIRE", Parent = left })
	local barBack = make("Frame", { Name = "FuelBack", Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = Color3.fromRGB(60, 40, 30), BorderSizePixel = 0, Parent = left })
	corner(barBack, 7)
	ui.FuelFill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = C.Warm, BorderSizePixel = 0, Parent = barBack })
	corner(ui.FuelFill, 7)
	ui.FireInfo = text({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = C.Muted, Text = "", Parent = left })
	ui.Courage = text({ Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 22), Font = FONT, TextSize = 18, TextColor3 = C.Sunny, Text = "Courage", Parent = left })
	text({ Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 18), Font = FONT, TextSize = 16, TextColor3 = C.Warm, Text = "BACKPACK", Parent = left })
	ui.Inventory = {}
	for i, name in ipairs(GameConfig.ResourceOrder) do
		ui.Inventory[name] = text({ Position = UDim2.fromOffset(0, 88 + i * 20), Size = UDim2.new(1, 0, 0, 20), TextSize = 16, Text = name, Parent = left })
	end
	ui.Capacity = text({ Position = UDim2.fromOffset(0, 192), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = C.Muted, Text = "", Parent = left })
	ui.Glow = text({ Position = UDim2.fromOffset(0, 208), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = C.Night, Text = "", Parent = left })
end

local function buildObjectives()
	local right = panel({ Name = "Objectives", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(250, 60), AutomaticSize = Enum.AutomaticSize.Y, Parent = gui })
	padding(right, 10)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = right })
	text({ Name = "Header", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 20), Font = FONT, TextSize = 18, TextColor3 = C.Warm, Text = "OBJECTIVES", Parent = right })
	ui.ObjectivesFrame = right
end

local function buildStatus()
	ui.Status = text({ Name = "Status", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -112), Size = UDim2.fromOffset(520, 30), Font = FONT, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, Text = "", Parent = gui })
	local sub = panel({ Name = "SunnySubtitle", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -150), Size = UDim2.fromOffset(560, 54), Visible = false, Parent = gui })
	padding(sub, 8)
	text({ Size = UDim2.new(0, 70, 1, 0), Font = FONT, TextSize = 18, TextColor3 = C.Sunny, Text = "SUNNY:", Parent = sub })
	ui.SubtitleText = text({ Position = UDim2.fromOffset(74, 0), Size = UDim2.new(1, -74, 1, 0), TextSize = 16, Text = "", Parent = sub })
	ui.Subtitle = sub
	ui.SubtitleToken = 0
end

local function buildToasts()
	local holder = make("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(460, 160), BackgroundTransparency = 1, Parent = gui })
	make("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
	ui.Toasts = holder
	ui.ToastOrder = 0
end

local function buildButtons()
	ui.CampButton = button({ Name = "CampButton", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -170), Size = UDim2.fromOffset(120, 48), Text = "CAMP (C)", Parent = gui })
	ui.LeaveButton = button({ Name = "LeaveButton", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -200), Size = UDim2.fromOffset(200, 56), BackgroundColor3 = C.Night, Text = "LEAVE HIDING", Visible = false, Parent = gui })
	ui.CampButton.Activated:Connect(function()
		HUDController.toggleUpgradePanel()
	end)
	ui.LeaveButton.Activated:Connect(function()
		controllers.Interaction.requestUnhide()
	end)
end

local function buildUpgradePanel()
	local p = panel({ Name = "UpgradePanel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 476), BackgroundTransparency = 0.08, Visible = false, Parent = gui })
	padding(p, 14)
	text({ Size = UDim2.new(1, -50, 0, 30), Font = FONT, TextSize = 26, TextColor3 = C.Warm, Text = "CAMP UPGRADES", Parent = p })
	local close = button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(40, 36), Text = "X", Parent = p })
	close.Activated:Connect(function()
		HUDController.setUpgradePanelVisible(false)
	end)
	ui.StockText = text({ Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 36), TextSize = 15, TextColor3 = C.Muted, Text = "", Parent = p })
	ui.UpgradeRows = {}
	for i, id in ipairs(GameConfig.UpgradeOrder) do
		local def = GameConfig.Upgrades[id]
		local row = panel({ Position = UDim2.fromOffset(0, 76 + (i - 1) * 80), Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = Color3.fromRGB(40, 48, 60), BackgroundTransparency = 0.1, Parent = p })
		padding(row, 8)
		local title = text({ Size = UDim2.new(1, -110, 0, 22), Font = FONT, TextSize = 18, Text = def.DisplayName, Parent = row })
		local desc = text({ Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -110, 0, 18), TextSize = 13, TextColor3 = C.Muted, Text = def.Description, Parent = row })
		local cost = text({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, -110, 0, 18), TextSize = 13, TextColor3 = C.Warm, Text = "", Parent = row })
		local build = button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(100, 46), Text = "BUILD", Parent = row })
		build.Activated:Connect(function()
			controllers.Interaction.requestUpgrade(id)
		end)
		ui.UpgradeRows[id] = { Title = title, Desc = desc, Cost = cost, Build = build }
	end
	ui.UpgradeHint = text({ Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Center, Text = "Build near the campfire, outside of night. Costs come from the camp crate.", Parent = p })
	ui.UpgradePanel = p
end

local function buildClueCard()
	local card = panel({ Name = "ClueCard", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(420, 170), BackgroundColor3 = Color3.fromRGB(245, 235, 205), BackgroundTransparency = 0, Visible = false, Parent = gui })
	padding(card, 14)
	ui.ClueTitle = text({ Size = UDim2.new(1, 0, 0, 28), Font = FONT, TextSize = 24, TextColor3 = Color3.fromRGB(90, 50, 20), Text = "", Parent = card })
	ui.ClueText = text({ Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 90), TextSize = 17, TextColor3 = Color3.fromRGB(50, 40, 30), Text = "", Parent = card })
	ui.ClueFinder = text({ Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = Color3.fromRGB(120, 90, 60), Text = "", Parent = card })
	local closeBtn = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = card })
	closeBtn.Activated:Connect(function()
		card.Visible = false
	end)
	ui.ClueCard = card
	ui.ClueToken = 0
end

local function buildResults()
	local dim = make("Frame", { Name = "Results", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(5, 8, 12), BackgroundTransparency = 0.25, BorderSizePixel = 0, Visible = false, ZIndex = 20, Parent = gui })
	local p = panel({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 460), BackgroundTransparency = 0.05, ZIndex = 21, Parent = dim })
	padding(p, 16)
	ui.EndTitle = text({ Size = UDim2.new(1, 0, 0, 40), Font = FONT, TextSize = 36, TextXAlignment = Enum.TextXAlignment.Center, Text = "", ZIndex = 22, Parent = p })
	ui.EndText = text({ Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 56), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Muted, Text = "", ZIndex = 22, Parent = p })
	ui.EndStats = text({ Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 22), Font = FONT, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Warm, Text = "", ZIndex = 22, Parent = p })
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 132), Size = UDim2.new(1, 0, 1, -200), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ZIndex = 22, Parent = p })
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	ui.EndRows = list
	ui.RestartButton = button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(260, 54), Text = "PLAY AGAIN", ZIndex = 22, Parent = p })
	ui.RestartButton.Activated:Connect(function()
		controllers.Interaction.requestRestart()
	end)
	ui.Results = dim
end

local function buildVignette()
	local v = make("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 0, Parent = gui })
	ui.VignetteEdges = {}
	local edges = {
		{ Size = UDim2.new(1, 0, 0.18, 0), Position = UDim2.fromScale(0, 0), Rotation = 90 },
		{ Size = UDim2.new(1, 0, 0.18, 0), Position = UDim2.fromScale(0, 0.82), Rotation = -90 },
		{ Size = UDim2.new(0.12, 0, 1, 0), Position = UDim2.fromScale(0, 0), Rotation = 0 },
		{ Size = UDim2.new(0.12, 0, 1, 0), Position = UDim2.fromScale(0.88, 0), Rotation = 180 },
	}
	for _, e in ipairs(edges) do
		local f = make("Frame", { Size = e.Size, Position = e.Position, BackgroundColor3 = C.Danger, BorderSizePixel = 0, BackgroundTransparency = 0, ZIndex = 0, Parent = v })
		make("UIGradient", {
			Rotation = e.Rotation,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
			Parent = f,
		})
		table.insert(ui.VignetteEdges, f)
	end
	ui.Vignette = v
end

local function buildIntro()
	local card = text({ Name = "Intro", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(700, 90), Font = FONT, TextSize = 48, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Sunny, TextStrokeTransparency = 0.2, TextTransparency = 1, TextStrokeColor3 = Color3.fromRGB(60, 30, 10), Text = GameConfig.GameTitle .. "\n" .. GameConfig.GameSubtitle, Parent = gui })
	ui.Intro = card
end

-------------------------------------------------------------------------------
-- Updates
-------------------------------------------------------------------------------

local function phaseTitle(): string
	local phase = state:GetAttribute(Types.StateAttr.Phase) or "Intermission"
	local night = state:GetAttribute(Types.StateAttr.Night) or 0
	if phase == "Day" then
		return "DAY " .. (night + 1)
	elseif phase == "Sunset" then
		return "SUNSET"
	elseif phase == "Night" then
		return "NIGHT " .. night
	elseif phase == "Dawn" then
		return "DAWN"
	elseif phase == "Results" then
		return "RESULTS"
	end
	return "GET READY"
end

local function updatePhase()
	local phase = state:GetAttribute(Types.StateAttr.Phase) or "Intermission"
	ui.Phase.Text = phaseTitle()
	local color = C.Text
	if phase == "Night" then
		color = C.Night
	elseif phase == "Sunset" or phase == "Dawn" then
		color = C.Warm
	end
	ui.Phase.TextColor3 = color
	ui.TestBadge.Text = ""
	if state:GetAttribute(Types.StateAttr.TestMode) then
		ui.TestBadge.Text = "SOLO TEST MODE (short timers)"
	end
	if phase == "Night" and ui.UpgradePanel.Visible then
		HUDController.setUpgradePanelVisible(false)
	end
	HUDController.updateStatus()
end

local function updateTimer()
	local endsAt = state:GetAttribute(Types.StateAttr.PhaseEndsAt) or 0
	ui.Timer.Text = formatTime(endsAt - workspace:GetServerTimeNow())
end

local function updateCamp()
	local fuel = state:GetAttribute(Types.StateAttr.Fuel) or 0
	local maxFuel = state:GetAttribute(Types.StateAttr.FuelMax) or 100
	local radius = state:GetAttribute(Types.StateAttr.SafeRadius) or 0
	local level = state:GetAttribute(Types.StateAttr.FireLevel) or 1
	local frac = math.clamp(fuel / math.max(1, maxFuel), 0, 1)
	TweenService:Create(ui.FuelFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(frac, 1) }):Play()
	local color = C.Warm
	if frac < 0.25 then
		color = C.Danger
	end
	ui.FuelFill.BackgroundColor3 = color
	local barricade = state:GetAttribute(Types.StateAttr.BarricadeHP) or 0
	local extra = ""
	if barricade > 0 then
		extra = "  Fence " .. barricade
	end
	ui.FireInfo.Text = string.format("Fuel %d/%d  Lv%d  Light %dm%s", fuel, maxFuel, level, math.floor(radius), extra)
	local courage = state:GetAttribute(Types.StateAttr.Courage) or 0
	local courageMax = state:GetAttribute(Types.StateAttr.CourageMax) or 0
	ui.Courage.Text = string.format("Team Courage %d/%d", courage, courageMax)
	if courage <= 1 and courageMax > 0 then
		ui.Courage.TextColor3 = C.Danger
	else
		ui.Courage.TextColor3 = C.Sunny
	end
end

local function updateInventory()
	local total = 0
	for _, name in ipairs(GameConfig.ResourceOrder) do
		local amount = player:GetAttribute(name) or 0
		total += amount
		ui.Inventory[name].Text = string.format("%s: %d", GameConfig.Resources[name].DisplayName, amount)
	end
	local capacity = player:GetAttribute(Types.PlayerAttr.Capacity) or GameConfig.Inventory.BaseCapacity
	ui.Capacity.Text = string.format("Carrying %d/%d  (deposit at the crate)", total, capacity)
	if total >= capacity then
		ui.Capacity.TextColor3 = C.Danger
	else
		ui.Capacity.TextColor3 = C.Muted
	end
	local glow = player:GetAttribute(Types.PlayerAttr.Glow) or 0
	local title = player:GetAttribute(Types.PlayerAttr.Title) or ""
	ui.Glow.Text = string.format("Glow %d  -  %s", glow, title)
end

local STATUS_TEXT = {
	Safe = { "Safe in the firelight", C.Warm },
	Dark = { "In the dark. Stay alert.", C.Night },
	Hidden = { "Hidden. SUNNY can't get you here.", C.Good },
	Watched = { "SUNNY IS WATCHING YOU", C.Sunny },
	Chased = { "RUN TO THE LIGHT OR HIDE!", C.Danger },
	Captured = { "In the Giggle Cage. Wait for a rescue!", C.Danger },
}

function HUDController.updateStatus()
	local status = player:GetAttribute(Types.PlayerAttr.Status) or "Safe"
	local phase = state:GetAttribute(Types.StateAttr.Phase) or "Intermission"
	local entry = STATUS_TEXT[status] or STATUS_TEXT.Safe
	local message, color = entry[1], entry[2]
	if phase ~= "Night" and (status == "Dark" or status == "Safe") then
		message, color = "", C.Text
		if phase == "Sunset" then
			message, color = "Sunset! Get back to the fire.", C.Warm
		end
	end
	ui.Status.Text = message
	ui.Status.TextColor3 = color
	ui.LeaveButton.Visible = player:GetAttribute(Types.PlayerAttr.Hidden) == true
end

local function updateObjectives(list)
	for _, child in ipairs(ui.ObjectivesFrame:GetChildren()) do
		if child:IsA("TextLabel") and child.Name == "Objective" then
			child:Destroy()
		end
	end
	if type(list) ~= "table" then
		return
	end
	for i, o in ipairs(list) do
		local line
		local color = C.Text
		if o.Complete then
			line = "[x] " .. o.Title
			color = C.Good
		elseif o.Locked then
			line = "[ ] " .. o.Title .. " (locked)"
			color = C.Muted
		else
			line = string.format("[ ] %s  %d/%d", o.Title, o.Progress, o.Goal)
		end
		text({ Name = "Objective", LayoutOrder = i, Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 14, TextColor3 = color, Text = line, Parent = ui.ObjectivesFrame })
	end
end

local function updateUpgradePanel()
	local parts = {}
	for _, name in ipairs(GameConfig.ResourceOrder) do
		table.insert(parts, string.format("%s %d", GameConfig.Resources[name].DisplayName, stock[name] or 0))
	end
	ui.StockText.Text = "Camp crate: " .. table.concat(parts, "   ")
	for _, id in ipairs(GameConfig.UpgradeOrder) do
		local def = GameConfig.Upgrades[id]
		local row = ui.UpgradeRows[id]
		local level = levels[id] or 0
		local nextCost = def.Costs[level + 1]
		row.Title.Text = string.format("%s  (Lv %d/%d)", def.DisplayName, level, #def.Costs)
		if nextCost then
			row.Cost.Text = "Cost: " .. formatCost(nextCost)
			row.Build.Text = "BUILD"
			row.Build.AutoButtonColor = true
			row.Build.BackgroundColor3 = C.Button
		else
			row.Cost.Text = "Maxed out!"
			row.Build.Text = "DONE"
			row.Build.AutoButtonColor = false
			row.Build.BackgroundColor3 = C.Muted
		end
	end
end

function HUDController.setUpgradePanelVisible(visible: boolean)
	ui.UpgradePanel.Visible = visible
	if visible then
		updateUpgradePanel()
	end
end

function HUDController.toggleUpgradePanel()
	HUDController.setUpgradePanelVisible(not ui.UpgradePanel.Visible)
end

function HUDController.toast(message: string, kind: string?)
	ui.ToastOrder += 1
	local label = text({
		Name = "Toast",
		LayoutOrder = ui.ToastOrder,
		Size = UDim2.new(1, 0, 0, 26),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.35,
		Font = FONT,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = TOAST_COLORS[kind or "info"] or C.Text,
		Text = message,
		Parent = ui.Toasts,
	})
	label.BackgroundColor3 = C.Panel
	label.BackgroundTransparency = 0.35
	corner(label, 8)
	table.insert(toasts, label)
	while #toasts > MAX_TOASTS do
		local old = table.remove(toasts, 1)
		old:Destroy()
	end
	task.delay(4.5, function()
		if label.Parent then
			local tween = TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			local index = table.find(toasts, label)
			if index then
				table.remove(toasts, index)
			end
			label:Destroy()
		end
	end)
end

local function showSubtitle(message: string, duration: number)
	ui.SubtitleToken += 1
	local token = ui.SubtitleToken
	ui.SubtitleText.Text = message
	ui.Subtitle.Visible = true
	task.delay(math.max(1.5, duration or 3.5), function()
		if ui.SubtitleToken == token then
			ui.Subtitle.Visible = false
		end
	end)
end

local function showClue(title: string, body: string, finder: string)
	ui.ClueToken += 1
	local token = ui.ClueToken
	ui.ClueTitle.Text = "CLUE: " .. tostring(title)
	ui.ClueText.Text = tostring(body)
	ui.ClueFinder.Text = "Found by " .. tostring(finder) .. "  (tap to close)"
	ui.ClueCard.Visible = true
	task.delay(8, function()
		if ui.ClueToken == token then
			ui.ClueCard.Visible = false
		end
	end)
end

local function updateVotes()
	local votes = state:GetAttribute(Types.StateAttr.RestartVotes) or 0
	local needed = state:GetAttribute(Types.StateAttr.RestartNeeded) or 1
	ui.RestartButton.Text = string.format("PLAY AGAIN (%d/%d)", votes, needed)
end

local function showRecap(recap)
	if recap == nil then
		ui.Results.Visible = false
		return
	end
	if type(recap) ~= "table" then
		return
	end
	HUDController.setUpgradePanelVisible(false)
	ui.EndTitle.Text = tostring(recap.EndingTitle)
	if recap.Victory then
		ui.EndTitle.TextColor3 = C.Good
	else
		ui.EndTitle.TextColor3 = C.Danger
	end
	ui.EndText.Text = tostring(recap.EndingText)
	ui.EndStats.Text = string.format("Nights survived: %d   Clues: %d/%d   Bridge: %d/%d   Time: %.1f min", recap.NightsSurvived or 0, recap.CluesFound or 0, recap.CluesTotal or 0, recap.BridgeStages or 0, GameConfig.Objectives.BridgeStages, recap.Minutes or 0)
	for _, child in ipairs(ui.EndRows:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, row in ipairs(recap.Rows or {}) do
		text({
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 40),
			TextSize = 15,
			ZIndex = 23,
			Text = string.format("%s  -  \"%s\"\nGathered %d | Fuel %d | Rescues %d | Caught %d | Clues %d | Glow %d", row.Name, row.Award, row.Gathered, row.FuelAdded, row.Rescues, row.Captures, row.CluesFound, row.Glow),
			Parent = ui.EndRows,
		})
	end
	updateVotes()
	ui.Results.Visible = true
end

local function setAlert(level: string)
	if level == "Clear" then
		ui.Vignette.Visible = false
		return
	end
	local color = C.Sunny
	if level == "Chased" then
		color = C.Danger
	end
	for _, edge in ipairs(ui.VignetteEdges) do
		edge.BackgroundColor3 = color
	end
	ui.Vignette.Visible = true
end

local function playIntro()
	ui.Intro.TextTransparency = 1
	ui.Intro.TextStrokeTransparency = 1
	TweenService:Create(ui.Intro, TweenInfo.new(1), { TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()
	task.delay(4, function()
		TweenService:Create(ui.Intro, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

local function applyScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local scale = math.clamp(math.min(size.X / 1100, size.Y / 640), 0.55, 1.15)
	ui.Scale.Scale = scale
end

-------------------------------------------------------------------------------

function HUDController.init(all)
	controllers = all
	state = Remotes.getState()
	gui = make("ScreenGui", {
		Name = "SurviveHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	ui.Scale = make("UIScale", { Parent = gui })
	buildVignette()
	buildTopBar()
	buildLeftPanel()
	buildObjectives()
	buildStatus()
	buildToasts()
	buildButtons()
	buildUpgradePanel()
	buildClueCard()
	buildResults()
	buildIntro()
end

function HUDController.start()
	applyScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end

	local lastPhase = nil
	state:GetAttributeChangedSignal(Types.StateAttr.Phase):Connect(function()
		local phase = state:GetAttribute(Types.StateAttr.Phase)
		updatePhase()
		if phase == "Day" and (state:GetAttribute(Types.StateAttr.Night) or 0) == 0 and lastPhase ~= "Day" then
			playIntro()
		end
		lastPhase = phase
	end)
	state:GetAttributeChangedSignal(Types.StateAttr.Night):Connect(updatePhase)
	state:GetAttributeChangedSignal(Types.StateAttr.TestMode):Connect(updatePhase)
	for _, attr in ipairs({ Types.StateAttr.Fuel, Types.StateAttr.FuelMax, Types.StateAttr.SafeRadius, Types.StateAttr.FireLevel, Types.StateAttr.Courage, Types.StateAttr.CourageMax, Types.StateAttr.BarricadeHP }) do
		state:GetAttributeChangedSignal(attr):Connect(updateCamp)
	end
	state:GetAttributeChangedSignal(Types.StateAttr.RestartVotes):Connect(updateVotes)
	state:GetAttributeChangedSignal(Types.StateAttr.RestartNeeded):Connect(updateVotes)

	for _, name in ipairs(GameConfig.ResourceOrder) do
		player:GetAttributeChangedSignal(name):Connect(updateInventory)
	end
	for _, attr in ipairs({ Types.PlayerAttr.Capacity, Types.PlayerAttr.Glow, Types.PlayerAttr.Title }) do
		player:GetAttributeChangedSignal(attr):Connect(updateInventory)
	end
	player:GetAttributeChangedSignal(Types.PlayerAttr.Status):Connect(HUDController.updateStatus)
	player:GetAttributeChangedSignal(Types.PlayerAttr.Hidden):Connect(HUDController.updateStatus)

	Remotes.get("Notify").OnClientEvent:Connect(function(message, kind)
		if type(message) == "string" then
			HUDController.toast(message, kind)
		end
	end)
	Remotes.get("SunnySpeech").OnClientEvent:Connect(function(message, duration)
		if type(message) == "string" then
			showSubtitle(message, duration)
		end
	end)
	Remotes.get("ObjectivesUpdated").OnClientEvent:Connect(updateObjectives)
	Remotes.get("Recap").OnClientEvent:Connect(showRecap)
	Remotes.get("ClueFound").OnClientEvent:Connect(showClue)
	Remotes.get("SunnyAlert").OnClientEvent:Connect(setAlert)
	Remotes.get("StockpileUpdated").OnClientEvent:Connect(function(newStock, newLevels)
		if type(newStock) == "table" then
			stock = newStock
		end
		if type(newLevels) == "table" then
			levels = newLevels
		end
		if ui.UpgradePanel.Visible then
			updateUpgradePanel()
		end
	end)

	updatePhase()
	updateCamp()
	updateInventory()
	updateVotes()

	-- Timer and vignette pulse, throttled.
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if ui.Vignette.Visible then
			local pulse = 0.5 + 0.5 * math.sin(os.clock() * 5)
			for _, edge in ipairs(ui.VignetteEdges) do
				edge.BackgroundTransparency = 0.2 + pulse * 0.4
			end
		end
		if accum >= 0.2 then
			accum = 0
			updateTimer()
		end
	end)
end

return HUDController
