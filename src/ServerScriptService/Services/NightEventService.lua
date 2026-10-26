-- NightEventService: schedules and runs modular night events. Every event gets its own Trove,
-- cleaned when the event's duration ends, when the night ends, or when the round resets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)

local Lib = ServerScriptService.Lib
local Trove = require(Lib.Trove)
local EventScheduler = require(Lib.EventScheduler)

local EventsFolder = script.Parent.NightEvents
local EVENT_MODULES = {
	require(EventsFolder.FalseLantern),
	require(EventsFolder.StrangeRadio),
	require(EventsFolder.ShiftingNodes),
	require(EventsFolder.SunnyAtEdge),
	require(EventsFolder.Silhouette),
	require(EventsFolder.StrangeCrate),
	require(EventsFolder.FootstepsCabin),
	require(EventsFolder.FakeSign),
}

local NightEventService = {}

local Services
local World

local events = {} -- [id] = module
local nightTrove = Trove.new()
local active = {} -- [Trove] = id
local runtimeFolder
local rng = Random.new()
local history = {} -- recent event ids for debugging/integration tests

local function log(...)
	if GameConfig.Debug.LogEvents then
		print("[Events]", ...)
	end
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-------------------------------------------------------------------------------
-- Context given to event modules
-------------------------------------------------------------------------------

local function makeContext(eventId: string, trove)
	local PS = Services.PlayerStateService
	local ctx = {
		Id = eventId,
		Services = Services,
		World = World,
		Rng = rng,
		Night = Services.PhaseService.getNight(),
		Definition = GameConfig.Events.Definitions[eventId],
		Trove = trove,
		Folder = runtimeFolder,
	}

	function ctx.notifyAll(text: string, kind: string?)
		PS.notifyAll(text, kind)
	end

	function ctx.say(text: string, duration: number?)
		Services.SunnyService.say(text, duration, true)
	end

	function ctx.playSound(key: string, position: Vector3?, repeatCount: number?)
		PS.playSound(key, position, repeatCount)
	end

	-- A point in the dark: outside the repel radius, on the camp side of the ravine, inside the map.
	function ctx.randomDarkPosition(minExtra: number, maxExtra: number): Vector3
		local center = World.CampCenter
		local radius = math.max(Services.CampService.getRepelRadius(), GameConfig.Camp.SafeRadiusMin)
		local limitZ = GameConfig.World.RavineZ + GameConfig.World.RavineWidth
		for _ = 1, 20 do
			local angle = rng:NextNumber() * math.pi * 2
			local dist = radius + minExtra + rng:NextNumber() * (maxExtra - minExtra)
			local p = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
			local half = GameConfig.World.MapHalfSize - 10
			if p.Z > limitZ and math.abs(p.X) < half and math.abs(p.Z) < half then
				return p
			end
		end
		return center + Vector3.new(radius + minExtra, 0, 0)
	end

	function ctx.nearestPlayer(position: Vector3): (Player?, number)
		local best, bestDist = nil, math.huge
		for _, player in ipairs(PS.getPlayers()) do
			local root = PS.getRoot(player)
			if root then
				local d = flatDistance(root.Position, position)
				if d < bestDist then
					best, bestDist = player, d
				end
			end
		end
		return best, bestDist
	end

	-- Runs fn every `interval` seconds until it returns false or the event is cleaned.
	function ctx.every(interval: number, fn)
		trove:Spawn(function()
			while true do
				task.wait(interval)
				local ok, result = pcall(fn)
				if not ok then
					warn("[Events] " .. eventId .. " loop error: " .. tostring(result))
					break
				end
				if result == false then
					break
				end
			end
		end)
	end

	function ctx.part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, opts)
		opts = opts or {}
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = opts.CanCollide == true
		p.CastShadow = false
		if opts.Shape then
			p.Shape = opts.Shape
		end
		if opts.Transparency then
			p.Transparency = opts.Transparency
		end
		p.Parent = opts.Parent or runtimeFolder
		trove:Add(p)
		return p
	end

	function ctx.prompt(parent: Instance, action: string, object: string, hold: number, distance: number): ProximityPrompt
		local prompt = PS.makePrompt(parent, action, object, hold, distance)
		trove:Add(prompt)
		return prompt
	end

	function ctx.label(part: BasePart, text: string, color: Color3?)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(200, 50)
		gui.StudsOffset = Vector3.new(0, 3, 0)
		gui.MaxDistance = 80
		gui.LightInfluence = 0
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundTransparency = 1
		l.TextScaled = true
		l.Font = Enum.Font.FredokaOne
		l.TextColor3 = color or Color3.fromRGB(255, 255, 255)
		l.TextStrokeTransparency = 0.3
		l.Text = text
		l.Parent = gui
		gui.Parent = part
		return l
	end

	-- Validates a player interaction with an event object.
	function ctx.canInteract(player: Player, position: Vector3, maxDistance: number): boolean
		return PS.allowPrompt(player) and PS.canAct(player) and PS.isWithin(player, position, maxDistance)
	end

	return ctx
end

-------------------------------------------------------------------------------
-- Running events
-------------------------------------------------------------------------------

function NightEventService.runEvent(eventId: string): boolean
	local module = events[eventId]
	if not module then
		warn("[Events] unknown event " .. tostring(eventId))
		return false
	end
	local def = GameConfig.Events.Definitions[eventId]
	local trove = Trove.new()
	active[trove] = eventId
	nightTrove:Add(trove)
	table.insert(history, eventId)
	if #history > 30 then
		table.remove(history, 1)
	end
	log("start", eventId)
	local ctx = makeContext(eventId, trove)
	local ok, err = pcall(module.run, ctx)
	if not ok then
		warn("[Events] " .. eventId .. " failed: " .. tostring(err))
		trove:Destroy()
		active[trove] = nil
		return false
	end
	local duration = (def and def.Duration) or 15
	task.delay(duration, function()
		if active[trove] then
			active[trove] = nil
			trove:Destroy()
			log("end", eventId)
		end
	end)
	return true
end

function NightEventService.stopAll()
	for trove in pairs(active) do
		active[trove] = nil
		trove:Destroy()
	end
	nightTrove:Clean()
end

function NightEventService.getActiveCount(): number
	local n = 0
	for _ in pairs(active) do
		n += 1
	end
	return n
end

function NightEventService.getHistory()
	return table.clone(history)
end

function NightEventService.getEventIds()
	local ids = {}
	for id in pairs(events) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function startNight(night: number, round: number)
	NightEventService.stopAll()
	local duration = Services.PhaseService.getTimings().Night
	local available = {}
	for id in pairs(events) do
		available[id] = true
	end
	local schedule = EventScheduler.build({
		night = night,
		duration = duration,
		count = Services.PhaseService.getEscalation().Events,
		definitions = GameConfig.Events.Definitions,
		rng = rng,
		eventsConfig = GameConfig.Events,
		available = available,
	})
	local names = {}
	for _, entry in ipairs(schedule) do
		table.insert(names, string.format("%s@%.0fs", entry.id, entry.at))
	end
	log("night", night, "schedule:", table.concat(names, ", "))
	local startedAt = os.clock()
	nightTrove:Spawn(function()
		for _, entry in ipairs(schedule) do
			local waitFor = startedAt + entry.at - os.clock()
			if waitFor > 0 then
				task.wait(waitFor)
			end
			local PhaseService = Services.PhaseService
			if PhaseService.getPhase() ~= "Night" or PhaseService.getRound() ~= round then
				return
			end
			NightEventService.runEvent(entry.id)
		end
	end)
end

function NightEventService.init(services, world)
	Services = services
	World = world
	for _, module in ipairs(EVENT_MODULES) do
		assert(type(module.Id) == "string" and type(module.run) == "function", "Night event modules need Id and run")
		assert(GameConfig.Events.Definitions[module.Id], "Night event missing config: " .. module.Id)
		events[module.Id] = module
	end
end

function NightEventService.start()
	runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = "NightEventObjects"
	runtimeFolder.Parent = workspace
	Services.PhaseService.PhaseChanged:Connect(function(phase, night, round)
		if phase == "Night" then
			startNight(night, round)
		else
			NightEventService.stopAll()
		end
	end)
end

return NightEventService
