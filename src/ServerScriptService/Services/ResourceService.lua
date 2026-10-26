-- ResourceService: server-authoritative gathering from resource nodes, depletion, respawn and shifting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

local Lib = ServerScriptService.Lib
local RateLimiter = require(Lib.RateLimiter)

local ResourceService = {}

local GATHER = GameConfig.Gathering

local Services
local World

local nodes = {} -- [Model] = node record
local nodeList = {}
local gatherLimiter = RateLimiter.new(1, GATHER.Cooldown)

local function setNodeVisible(node, visible: boolean)
	for part, original in pairs(node.Parts) do
		if visible then
			part.Transparency = original.Transparency
			part.CanCollide = original.CanCollide
		else
			part.Transparency = math.max(original.Transparency, 0.85)
			part.CanCollide = false
		end
	end
	node.Prompt.Enabled = visible
end

local function deplete(node)
	node.Depleted = true
	node.RespawnAt = os.clock() + GameConfig.Resources[node.Type].RespawnTime
	setNodeVisible(node, false)
end

local function restore(node)
	node.Depleted = false
	node.Hits = node.MaxHits
	setNodeVisible(node, true)
end

function ResourceService.tryGather(player: Player, model: Model)
	local PS = Services.PlayerStateService
	local node = nodes[model]
	if not node then
		return
	end
	local phase = Services.PhaseService.getPhase()
	if phase == "Intermission" or phase == "Results" then
		return
	end
	if not PS.allowPrompt(player) or not gatherLimiter:allow(player) then
		return
	end
	if not PS.canAct(player) then
		return
	end
	local primary = model.PrimaryPart
	if not primary or not PS.isWithin(player, primary.Position, GATHER.MaxDistance) then
		return
	end
	-- Concurrency: everything below runs without yielding, so two players
	-- hitting the same node in the same frame are processed one after the other.
	if node.Depleted or node.Hits <= 0 then
		return
	end
	local res = GameConfig.Resources[node.Type]
	local capacity = PS.getCapacity(player)
	local inv = PS.getInventory(player)
	local total = 0
	for _, name in ipairs(GameConfig.ResourceOrder) do
		total += inv[name]
	end
	if total >= capacity then
		PS.notify(player, "Your backpack is full! Deposit at the camp crate.", "warn")
		return
	end
	node.Hits -= 1
	local added = PS.addResource(player, node.Type, res.Yield)
	PS.addStat(player, "Gathered", added)
	if node.Type == "Wood" then
		Services.ObjectiveService.progress("gather_wood", added)
	end
	if node.Hits <= 0 then
		deplete(node)
	end
	PS.notify(player, string.format("+%d %s", added, res.DisplayName), "gather")
	PS.playSound("Gather", primary.Position, nil, player)
	if phase == "Night" then
		Services.SunnyService.reportNoise(primary.Position, res.NightNoise)
	end
end

-- Moves up to `count` active nodes to spare positions. Returns how many moved.
function ResourceService.shiftNodes(count: number, rng: Random): number
	local spare = World.SpareNodePositions
	if #spare == 0 then
		return 0
	end
	local moved = 0
	local candidates = {}
	for _, node in ipairs(nodeList) do
		if not node.Depleted then
			table.insert(candidates, node)
		end
	end
	for _ = 1, math.min(count, #candidates) do
		local index = rng:NextInteger(1, #candidates)
		local node = table.remove(candidates, index)
		local target = spare[rng:NextInteger(1, #spare)]
		local current = node.Model:GetPivot()
		local offset = Vector3.new(target.X, 0, target.Z) - Vector3.new(current.Position.X, 0, current.Position.Z)
		node.Model:PivotTo(current + offset)
		moved += 1
	end
	return moved
end

function ResourceService.reset()
	for _, node in ipairs(nodeList) do
		node.Model:PivotTo(node.HomePivot)
		restore(node)
	end
	gatherLimiter:clear()
end

function ResourceService.getNodeCount(): number
	return #nodeList
end

local function respawnLoop()
	while true do
		task.wait(GATHER.RespawnCheckInterval)
		local now = os.clock()
		for _, node in ipairs(nodeList) do
			if node.Depleted and now >= node.RespawnAt and node.Model.Parent then
				restore(node)
			end
		end
	end
end

function ResourceService.init(services, world)
	Services = services
	World = world
end

function ResourceService.start()
	local makePrompt = Services.PlayerStateService.makePrompt
	for _, model in ipairs(World.ResourceNodes) do
		local kind = model:GetAttribute("ResourceType")
		local res = GameConfig.Resources[kind]
		if res and model.PrimaryPart then
			local parts = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					parts[d] = { Transparency = d.Transparency, CanCollide = d.CanCollide }
				end
			end
			local prompt = makePrompt(model.PrimaryPart, res.ActionText, res.NodeName, res.HoldDuration, GATHER.PromptDistance)
			prompt.Name = "GatherPrompt"
			local node = {
				Model = model,
				Type = kind,
				Hits = res.NodeHits,
				MaxHits = res.NodeHits,
				Depleted = false,
				RespawnAt = 0,
				Prompt = prompt,
				Parts = parts,
				HomePivot = model:GetPivot(),
			}
			nodes[model] = node
			table.insert(nodeList, node)
			prompt.Triggered:Connect(function(player)
				ResourceService.tryGather(player, model)
			end)
		end
	end
	Services.PlayerStateService.PlayerLeft:Connect(function(player)
		gatherLimiter:reset(player)
	end)
	task.spawn(respawnLoop)
end

return ResourceService
