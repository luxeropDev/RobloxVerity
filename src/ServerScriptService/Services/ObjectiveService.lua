-- ObjectiveService: objectives, clues, radio repair, bridge repair and their replication.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Remotes = require(Shared.Remotes)

local Lib = ServerScriptService.Lib
local InventoryLogic = require(Lib.InventoryLogic)
local Signal = require(Lib.Signal)

local ObjectiveService = {}

ObjectiveService.Completed = Signal.new() -- (objectiveId)
ObjectiveService.ClueFoundSignal = Signal.new() -- (clueId, player?)

local OBJ = GameConfig.Objectives

local Services
local World

local objectives = {} -- ordered list
local byId = {}
local cluesFound = {} -- [clueId] = true
local clueById = {}
local cluePrompts = {} -- [clueId] = ProximityPrompt
local radioFixed = false
local bridgeStage = 0
local radioPrompt
local bridgePrompt
local refreshRadioVisuals -- defined below

local function define()
	table.clear(objectives)
	table.clear(byId)
	local list = {
		{ Id = "gather_wood", Title = "Gather wood", Goal = OBJ.GatherWoodGoal },
		{ Id = "feed_fire", Title = "Feed the campfire", Goal = OBJ.FeedFireGoal },
		{ Id = "fix_radio", Title = "Fix the old radio (" .. InventoryLogic.formatCost(OBJ.RadioCost) .. ")", Goal = 1 },
		{ Id = "find_clues", Title = "Find clues about SUNNY", Goal = OBJ.CluesGoal },
		{ Id = "repair_bridge", Title = "Repair the broken bridge", Goal = OBJ.BridgeStages, Locked = true },
		{ Id = "survive", Title = "Survive " .. GameConfig.Nights.VictoryNight .. " nights", Goal = GameConfig.Nights.VictoryNight },
	}
	for _, def in ipairs(list) do
		local o = { Id = def.Id, Title = def.Title, Goal = def.Goal, Progress = 0, Complete = false, Locked = def.Locked == true }
		table.insert(objectives, o)
		byId[o.Id] = o
	end
end

local function snapshot()
	local view = {}
	for _, o in ipairs(objectives) do
		table.insert(view, { Id = o.Id, Title = o.Title, Progress = o.Progress, Goal = o.Goal, Complete = o.Complete, Locked = o.Locked })
	end
	return view
end

function ObjectiveService.broadcast()
	Remotes.get("ObjectivesUpdated"):FireAllClients(snapshot())
end

function ObjectiveService.sendTo(player: Player)
	Remotes.get("ObjectivesUpdated"):FireClient(player, snapshot())
end

local function setProgress(id: string, value: number)
	local o = byId[id]
	if not o or o.Complete or o.Locked then
		return
	end
	o.Progress = math.clamp(value, 0, o.Goal)
	if o.Progress >= o.Goal then
		o.Complete = true
		Services.PlayerStateService.notifyAll("Objective complete: " .. o.Title .. "!", "success")
		ObjectiveService.Completed:Fire(id)
	end
	ObjectiveService.broadcast()
end

function ObjectiveService.progress(id: string, amount: number)
	local o = byId[id]
	if not o then
		return
	end
	setProgress(id, o.Progress + amount)
end

function ObjectiveService.set(id: string, value: number)
	setProgress(id, value)
end

function ObjectiveService.isComplete(id: string): boolean
	local o = byId[id]
	return o ~= nil and o.Complete
end

-- Re-applies the radio light/prompt for the current state (used after night events tint it).
function ObjectiveService.refreshRadio()
	refreshRadioVisuals()
end

function ObjectiveService.isRadioFixed(): boolean
	return radioFixed
end

function ObjectiveService.isBridgeRepaired(): boolean
	return bridgeStage >= OBJ.BridgeStages
end

function ObjectiveService.getBridgeStage(): number
	return bridgeStage
end

function ObjectiveService.getCluesFound(): (number, number)
	local n = 0
	for _ in pairs(cluesFound) do
		n += 1
	end
	return n, #GameConfig.Clues
end

-------------------------------------------------------------------------------
-- Clues
-------------------------------------------------------------------------------

local function refreshCluePrompt(clueId: string)
	local prompt = cluePrompts[clueId]
	if not prompt then
		return
	end
	local clue = clueById[clueId]
	local part = prompt.Parent
	local visible = not cluesFound[clueId]
	if clue.NightOnly and Services.PhaseService.getPhase() ~= "Night" then
		visible = false
	end
	prompt.Enabled = visible
	if part and part:IsA("BasePart") and clue.NightOnly then
		-- Night-only clue markers are invisible during the day.
		part.Transparency = 0
		if not visible then
			part.Transparency = 1
		end
	end
end

-- Awards a clue (from a clue spot or an event). Idempotent.
function ObjectiveService.awardClue(clueId: string, player: Player?): boolean
	local clue = clueById[clueId]
	if not clue or cluesFound[clueId] then
		return false
	end
	cluesFound[clueId] = true
	local finderName = "The team"
	if player then
		finderName = player.DisplayName
		Services.PlayerStateService.addStat(player, "CluesFound", 1)
		Services.PlayerStateService.awardGlow(player, GameConfig.Rewards.GlowPerClue)
	end
	Remotes.get("ClueFound"):FireAllClients(clue.Title, clue.Text, finderName)
	Services.PlayerStateService.playSound("Clue", nil, nil, nil)
	refreshCluePrompt(clueId)
	local found = ObjectiveService.getCluesFound()
	ObjectiveService.set("find_clues", found)
	ObjectiveService.ClueFoundSignal:Fire(clueId, player)
	return true
end

function ObjectiveService.isClueFound(clueId: string): boolean
	return cluesFound[clueId] == true
end

function ObjectiveService.revealClue(clueId: string)
	refreshCluePrompt(clueId)
end

local function onClueTriggered(player: Player, clueId: string, part: BasePart)
	local PS = Services.PlayerStateService
	if not PS.allowPrompt(player) or not PS.canAct(player) then
		return
	end
	if not PS.isWithin(player, part.Position, OBJ.PromptDistance + 5) then
		return
	end
	local clue = clueById[clueId]
	if clue.NightOnly and Services.PhaseService.getPhase() ~= "Night" then
		return
	end
	ObjectiveService.awardClue(clueId, player)
end

-------------------------------------------------------------------------------
-- Radio and bridge
-------------------------------------------------------------------------------

local function refreshBridgeVisuals()
	for i, plank in ipairs(World.BridgePlanks) do
		if i <= bridgeStage then
			plank.Transparency = 0
			plank.CanCollide = true
		else
			plank.Transparency = 0.85
			plank.CanCollide = false
		end
	end
	World.BridgeBarrier.CanCollide = bridgeStage < OBJ.BridgeStages
	if bridgePrompt then
		bridgePrompt.Enabled = radioFixed and bridgeStage < OBJ.BridgeStages
		bridgePrompt.ActionText = string.format("Repair (%d/%d)", bridgeStage, OBJ.BridgeStages)
		bridgePrompt.ObjectText = "Bridge: " .. InventoryLogic.formatCost(OBJ.BridgeStageCost)
	end
end

function refreshRadioVisuals()
	if radioFixed then
		World.RadioLight.Color = Color3.fromRGB(80, 255, 120)
	else
		World.RadioLight.Color = Color3.fromRGB(120, 30, 30)
	end
	if radioPrompt then
		radioPrompt.Enabled = not radioFixed
	end
end

local function onRadio(player: Player)
	local PS = Services.PlayerStateService
	if radioFixed or not PS.allowPrompt(player) or not PS.canAct(player) then
		return
	end
	if not PS.isWithin(player, World.Radio.Position, OBJ.PromptDistance + 5) then
		return
	end
	if not Services.CampService.spendStock(OBJ.RadioCost) then
		PS.notify(player, "The radio needs " .. InventoryLogic.formatCost(OBJ.RadioCost) .. " from the camp crate.", "warn")
		return
	end
	radioFixed = true
	refreshRadioVisuals()
	local o = byId.repair_bridge
	o.Locked = false
	ObjectiveService.set("fix_radio", 1)
	refreshBridgeVisuals()
	PS.notifyAll(player.DisplayName .. " fixed the radio! The bridge can now be repaired.", "success")
	ObjectiveService.awardClue("radio_log", player)
	Services.SunnyService.say("You fixed the radio? Who are you calling? It's not a ranger, is it? Haha. Ha.", 5)
end

local function onBridge(player: Player)
	local PS = Services.PlayerStateService
	if not radioFixed or bridgeStage >= OBJ.BridgeStages then
		return
	end
	if not PS.allowPrompt(player) or not PS.canAct(player) then
		return
	end
	if not PS.isWithin(player, World.BridgePosition, OBJ.PromptDistance + 8) then
		return
	end
	if Services.PhaseService.getPhase() == "Night" then
		PS.notify(player, "Too dark to fix the bridge. Wait for morning!", "warn")
		return
	end
	if not Services.CampService.spendStock(OBJ.BridgeStageCost) then
		PS.notify(player, "Each bridge section needs " .. InventoryLogic.formatCost(OBJ.BridgeStageCost) .. " from the camp crate.", "warn")
		return
	end
	bridgeStage += 1
	refreshBridgeVisuals()
	ObjectiveService.set("repair_bridge", bridgeStage)
	if bridgeStage >= OBJ.BridgeStages then
		PS.notifyAll("The bridge is fixed! Survive until the ranger arrives at dawn!", "success")
		Services.SunnyService.say("You fixed the bridge?! But... but the tour...", 4)
	else
		PS.notifyAll(string.format("%s repaired a bridge section (%d/%d).", player.DisplayName, bridgeStage, OBJ.BridgeStages), "success")
	end
end

-------------------------------------------------------------------------------

function ObjectiveService.onPhaseChanged(phase: string, night: number)
	for clueId in pairs(cluePrompts) do
		refreshCluePrompt(clueId)
	end
	if phase == "Dawn" then
		ObjectiveService.set("survive", night)
	end
end

function ObjectiveService.reset()
	define()
	table.clear(cluesFound)
	radioFixed = false
	bridgeStage = 0
	refreshRadioVisuals()
	refreshBridgeVisuals()
	for clueId in pairs(cluePrompts) do
		refreshCluePrompt(clueId)
	end
	ObjectiveService.broadcast()
end

function ObjectiveService.init(services, world)
	Services = services
	World = world
	for _, clue in ipairs(GameConfig.Clues) do
		clueById[clue.Id] = clue
	end
	define()
end

function ObjectiveService.start()
	local makePrompt = Services.PlayerStateService.makePrompt
	for _, clue in ipairs(GameConfig.Clues) do
		local part = clue.Spot and World.ClueSpots[clue.Spot]
		if part then
			local prompt = makePrompt(part, "Inspect", clue.Title, 0.6, OBJ.PromptDistance)
			prompt.Name = "CluePrompt"
			cluePrompts[clue.Id] = prompt
			prompt.Triggered:Connect(function(player)
				onClueTriggered(player, clue.Id, part)
			end)
		end
	end
	radioPrompt = makePrompt(World.Radio, "Fix Radio", "Old Radio", 1.2, OBJ.PromptDistance)
	radioPrompt.Triggered:Connect(onRadio)
	bridgePrompt = makePrompt(World.BridgeSign, "Repair", "Bridge", 1.5, OBJ.PromptDistance + 4)
	bridgePrompt.Triggered:Connect(onBridge)

	Services.PlayerStateService.PlayerJoined:Connect(function(player)
		ObjectiveService.sendTo(player)
	end)
	Services.PhaseService.PhaseChanged:Connect(ObjectiveService.onPhaseChanged)

	ObjectiveService.reset()
end

return ObjectiveService
