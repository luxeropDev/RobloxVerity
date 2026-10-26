-- PlayerStateService: per-player state (inventory, capture, hiding, stats, cosmetics),
-- team Courage, joins/leaves/respawns, and notification helpers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)

local Lib = ServerScriptService.Lib
local InventoryLogic = require(Lib.InventoryLogic)
local RateLimiter = require(Lib.RateLimiter)
local Signal = require(Lib.Signal)
local Trove = require(Lib.Trove)
local Awards = require(Lib.Awards)

local PlayerStateService = {}

PlayerStateService.Captured = Signal.new() -- (player)
PlayerStateService.Released = Signal.new() -- (player, reason)
PlayerStateService.Hid = Signal.new() -- (player, spot)
PlayerStateService.CourageDepleted = Signal.new() -- ()
PlayerStateService.AllCaptured = Signal.new() -- ()
PlayerStateService.PlayerJoined = Signal.new() -- (player)
PlayerStateService.PlayerLeft = Signal.new() -- (player)

local Services
local World

local records = {} -- [Player] = record
local spotOccupant = {} -- [BasePart] = Player
local spotPrompts = {} -- [BasePart] = ProximityPrompt
local courage = 0
local courageMax = 0
local rescuePrompt
local unhideLimiter = RateLimiter.new(GameConfig.RateLimits.RequestUnhide.MaxCalls, GameConfig.RateLimits.RequestUnhide.Window)
local promptLimiter = RateLimiter.new(GameConfig.RateLimits.Prompt.MaxCalls, GameConfig.RateLimits.Prompt.Window)

local function newStats()
	return {
		Gathered = 0,
		Deposited = 0,
		FuelAdded = 0,
		Rescues = 0,
		Captures = 0,
		CluesFound = 0,
		TimesChased = 0,
		Snacks = 0,
	}
end

local function newRecord()
	return {
		Inventory = InventoryLogic.new(),
		Captured = false,
		CapturedAt = 0,
		ImmuneUntil = 0,
		Hidden = nil,
		HiddenAt = 0,
		SpookedUntil = 0,
		Glow = 0,
		Status = Types.PlayerStatus.Safe,
		Stats = newStats(),
		CharTrove = Trove.new(),
	}
end

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

function PlayerStateService.get(player: Player)
	return records[player]
end

function PlayerStateService.getPlayers(): { Player }
	local list = {}
	for player in pairs(records) do
		if player.Parent == Players then
			table.insert(list, player)
		end
	end
	return list
end

function PlayerStateService.getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function PlayerStateService.getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- True if the player can act (alive, not captured, not hidden).
function PlayerStateService.canAct(player: Player): boolean
	local rec = records[player]
	if not rec or rec.Captured or rec.Hidden then
		return false
	end
	return PlayerStateService.getRoot(player) ~= nil
end

-- Server-side distance validation for any interaction.
function PlayerStateService.isWithin(player: Player, position: Vector3, maxDistance: number): boolean
	local root = PlayerStateService.getRoot(player)
	if not root then
		return false
	end
	return (root.Position - position).Magnitude <= maxDistance
end

-- Prompt spam guard shared by all ProximityPrompt handlers.
function PlayerStateService.allowPrompt(player: Player): boolean
	return promptLimiter:allow(player)
end

function PlayerStateService.isTargetable(player: Player): boolean
	local rec = records[player]
	if not rec or rec.Captured or rec.Hidden then
		return false
	end
	if os.clock() < rec.ImmuneUntil then
		return false
	end
	return PlayerStateService.getRoot(player) ~= nil
end

function PlayerStateService.notify(player: Player, text: string, kind: string?)
	Remotes.get("Notify"):FireClient(player, text, kind or "info")
end

function PlayerStateService.notifyAll(text: string, kind: string?)
	Remotes.get("Notify"):FireAllClients(text, kind or "info")
end

function PlayerStateService.playSound(key: string, position: Vector3?, repeatCount: number?, player: Player?)
	if player then
		Remotes.get("PlaySound"):FireClient(player, key, position, repeatCount)
	else
		Remotes.get("PlaySound"):FireAllClients(key, position, repeatCount)
	end
end

-------------------------------------------------------------------------------
-- Attributes / sync
-------------------------------------------------------------------------------

local function updateTitleBillboard(player: Player, rec)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = head:FindFirstChild("CampTitle")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "CampTitle"
		gui.Size = UDim2.fromOffset(160, 24)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 60
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 230, 150)
		label.TextStrokeTransparency = 0.4
		label.Parent = gui
		gui.Parent = head
	end
	gui.Label.Text = Awards.titleForGlow(rec.Glow, GameConfig.Rewards.Titles)
end

function PlayerStateService.sync(player: Player)
	local rec = records[player]
	if not rec then
		return
	end
	for _, name in ipairs(GameConfig.ResourceOrder) do
		player:SetAttribute(name, rec.Inventory[name])
	end
	player:SetAttribute(Types.PlayerAttr.Capacity, PlayerStateService.getCapacity(player))
	player:SetAttribute(Types.PlayerAttr.Glow, rec.Glow)
	player:SetAttribute(Types.PlayerAttr.Title, Awards.titleForGlow(rec.Glow, GameConfig.Rewards.Titles))
	player:SetAttribute(Types.PlayerAttr.Hidden, rec.Hidden ~= nil)
	player:SetAttribute(Types.PlayerAttr.Captured, rec.Captured)
	player:SetAttribute(Types.PlayerAttr.Status, rec.Status)
end

local function syncCourage()
	local state = Remotes.getState()
	state:SetAttribute(Types.StateAttr.Courage, courage)
	state:SetAttribute(Types.StateAttr.CourageMax, courageMax)
end

-------------------------------------------------------------------------------
-- Inventory
-------------------------------------------------------------------------------

function PlayerStateService.getCapacity(player: Player): number
	local bonus = 0
	if Services and Services.CampService then
		bonus = Services.CampService.getCapacityBonus()
	end
	return GameConfig.Inventory.BaseCapacity + bonus
end

function PlayerStateService.getInventory(player: Player)
	local rec = records[player]
	return rec and rec.Inventory
end

function PlayerStateService.addResource(player: Player, resource: string, amount: number): number
	local rec = records[player]
	if not rec then
		return 0
	end
	local added = InventoryLogic.add(rec.Inventory, resource, amount, PlayerStateService.getCapacity(player))
	if added > 0 then
		player:SetAttribute(resource, rec.Inventory[resource])
	end
	return added
end

function PlayerStateService.removeResource(player: Player, resource: string, amount: number): number
	local rec = records[player]
	if not rec then
		return 0
	end
	local removed = InventoryLogic.remove(rec.Inventory, resource, amount)
	if removed > 0 then
		player:SetAttribute(resource, rec.Inventory[resource])
	end
	return removed
end

function PlayerStateService.addStat(player: Player, stat: string, amount: number?)
	local rec = records[player]
	if rec and rec.Stats[stat] ~= nil then
		rec.Stats[stat] += amount or 1
	end
end

-------------------------------------------------------------------------------
-- Courage
-------------------------------------------------------------------------------

function PlayerStateService.resetCourage()
	local count = math.max(1, #PlayerStateService.getPlayers())
	courageMax = math.min(GameConfig.Courage.Max, GameConfig.Courage.Base + GameConfig.Courage.PerExtraPlayer * (count - 1))
	courage = courageMax
	syncCourage()
end

function PlayerStateService.getCourage(): (number, number)
	return courage, courageMax
end

function PlayerStateService.changeCourage(delta: number)
	courage = math.clamp(courage + delta, 0, courageMax)
	syncCourage()
	if courage <= 0 then
		PlayerStateService.CourageDepleted:Fire()
	end
end

-------------------------------------------------------------------------------
-- Capture / rescue
-------------------------------------------------------------------------------

local function anyCaptured(): boolean
	for _, rec in pairs(records) do
		if rec.Captured then
			return true
		end
	end
	return false
end

local function refreshRescuePrompt()
	if rescuePrompt then
		rescuePrompt.Enabled = anyCaptured()
	end
end

local function teleportCharacter(player: Player, position: Vector3)
	local character = player.Character
	if character and character.PrimaryPart then
		character:PivotTo(CFrame.new(position))
	end
end

local function campSpawnPosition(): Vector3
	local spawn = World.SpawnLocation
	return spawn.Position + Vector3.new(math.random(-2, 2), 4, math.random(-2, 2))
end

function PlayerStateService.unhide(player: Player)
	local rec = records[player]
	if not rec or not rec.Hidden then
		return
	end
	local spot = rec.Hidden
	rec.Hidden = nil
	if spotOccupant[spot] == player then
		spotOccupant[spot] = nil
	end
	if spotPrompts[spot] then
		spotPrompts[spot].Enabled = true
	end
	local root = PlayerStateService.getRoot(player)
	if root then
		root.Anchored = false
		local away = (World.CampCenter - spot.Position) * Vector3.new(1, 0, 1)
		if away.Magnitude < 0.1 then
			away = Vector3.new(1, 0, 0)
		end
		local exitPos = spot.Position + away.Unit * GameConfig.Hiding.ExitOffset
		teleportCharacter(player, Vector3.new(exitPos.X, 3.5, exitPos.Z))
	end
	local humanoid = PlayerStateService.getHumanoid(player)
	if humanoid then
		humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
	end
	player:SetAttribute(Types.PlayerAttr.Hidden, false)
end

function PlayerStateService.capture(player: Player): boolean
	local rec = records[player]
	if not rec or rec.Captured then
		return false
	end
	if rec.Hidden then
		PlayerStateService.unhide(player)
	end
	rec.Captured = true
	rec.CapturedAt = os.clock()
	rec.Stats.Captures += 1
	-- Carried (not deposited) items are lost: SUNNY keeps them as "souvenirs".
	rec.Inventory = InventoryLogic.new()
	teleportCharacter(player, World.CageCenter + Vector3.new(0, 3, 0))
	PlayerStateService.sync(player)
	refreshRescuePrompt()
	PlayerStateService.notifyAll(player.DisplayName .. " was taken to the Giggle Cage! Rescue them at the shrine.", "danger")
	PlayerStateService.playSound("Capture", nil, nil, nil)
	PlayerStateService.Captured:Fire(player)
	PlayerStateService.changeCourage(-1)

	local allCaptured = true
	local any = false
	for _, other in ipairs(PlayerStateService.getPlayers()) do
		any = true
		local r = records[other]
		if r and not r.Captured then
			allCaptured = false
			break
		end
	end
	if any and allCaptured then
		PlayerStateService.AllCaptured:Fire()
	end
	return true
end

function PlayerStateService.release(player: Player, reason: string)
	local rec = records[player]
	if not rec or not rec.Captured then
		return
	end
	rec.Captured = false
	rec.ImmuneUntil = os.clock() + GameConfig.Capture.ReleaseImmunity
	teleportCharacter(player, campSpawnPosition())
	PlayerStateService.sync(player)
	refreshRescuePrompt()
	PlayerStateService.Released:Fire(player, reason)
end

function PlayerStateService.releaseAll(reason: string)
	for player, rec in pairs(records) do
		if rec.Captured then
			PlayerStateService.release(player, reason)
		end
	end
end

local function onRescue(player: Player)
	if not PlayerStateService.allowPrompt(player) then
		return
	end
	if not PlayerStateService.canAct(player) then
		return
	end
	if not PlayerStateService.isWithin(player, World.CageLock.Position, GameConfig.Capture.RescuePromptDistance + 4) then
		return
	end
	local freed = 0
	for other, rec in pairs(records) do
		if rec.Captured and other ~= player then
			PlayerStateService.release(other, "rescued")
			freed += 1
		end
	end
	if freed > 0 then
		PlayerStateService.addStat(player, "Rescues", freed)
		PlayerStateService.notifyAll(player.DisplayName .. " opened the Giggle Cage! Teamwork!", "success")
	end
end

-------------------------------------------------------------------------------
-- Hiding
-------------------------------------------------------------------------------

local function onHide(player: Player, spot: BasePart)
	if not PlayerStateService.allowPrompt(player) then
		return
	end
	local rec = records[player]
	if not rec or rec.Captured or rec.Hidden then
		return
	end
	if spotOccupant[spot] then
		PlayerStateService.notify(player, "Someone is already hiding here!", "warn")
		return
	end
	if not PlayerStateService.isWithin(player, spot.Position, GameConfig.Hiding.PromptDistance + 5) then
		return
	end
	local root = PlayerStateService.getRoot(player)
	if not root then
		return
	end
	-- All checks passed; mutate without yielding.
	rec.Hidden = spot
	rec.HiddenAt = os.clock()
	spotOccupant[spot] = player
	if spotPrompts[spot] then
		spotPrompts[spot].Enabled = false
	end
	teleportCharacter(player, Vector3.new(spot.Position.X, 3, spot.Position.Z))
	root.Anchored = true
	player:SetAttribute(Types.PlayerAttr.Hidden, true)
	PlayerStateService.notify(player, "You are hidden. Press Jump or tap LEAVE to come out.", "info")
	PlayerStateService.Hid:Fire(player, spot)
end

function PlayerStateService.spook(player: Player, duration: number)
	local rec = records[player]
	local humanoid = PlayerStateService.getHumanoid(player)
	if not rec or not humanoid or rec.Hidden then
		return
	end
	rec.SpookedUntil = os.clock() + duration
	humanoid.WalkSpeed = GameConfig.Player.SpookedWalkSpeed
end

-------------------------------------------------------------------------------
-- Rewards
-------------------------------------------------------------------------------

function PlayerStateService.awardGlow(player: Player, amount: number)
	local rec = records[player]
	if not rec or amount <= 0 then
		return
	end
	rec.Glow += amount
	PlayerStateService.sync(player)
	updateTitleBillboard(player, rec)
end

-------------------------------------------------------------------------------
-- Status loop
-------------------------------------------------------------------------------

local function computeStatus(player: Player, rec): string
	if rec.Captured then
		return Types.PlayerStatus.Captured
	end
	if rec.Hidden then
		return Types.PlayerStatus.Hidden
	end
	local sunny = Services.SunnyService
	if sunny and sunny.getTarget() == player then
		local s = sunny.getState()
		if s == "Chasing" then
			return Types.PlayerStatus.Chased
		elseif s == "Stalking" then
			return Types.PlayerStatus.Watched
		end
	end
	local root = PlayerStateService.getRoot(player)
	if root and Services.CampService.isInSafeZone(root.Position, 0) then
		return Types.PlayerStatus.Safe
	end
	return Types.PlayerStatus.Dark
end

local function tick()
	local now = os.clock()
	for player, rec in pairs(records) do
		if rec.Captured and now - rec.CapturedAt >= GameConfig.Capture.CageDuration then
			PlayerStateService.release(player, "timeout")
			PlayerStateService.notify(player, "SUNNY got bored and sent you back to camp.", "info")
		end
		if rec.Hidden then
			if now - rec.HiddenAt >= GameConfig.Hiding.MaxDuration then
				PlayerStateService.unhide(player)
				PlayerStateService.notify(player, "Your legs fell asleep. You had to come out!", "warn")
			elseif not rec.Hidden.Parent then
				PlayerStateService.unhide(player)
			end
		end
		if rec.SpookedUntil > 0 and now >= rec.SpookedUntil then
			rec.SpookedUntil = 0
			local humanoid = PlayerStateService.getHumanoid(player)
			if humanoid and not rec.Hidden then
				humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
			end
		end
		local status = computeStatus(player, rec)
		if status ~= rec.Status then
			rec.Status = status
			player:SetAttribute(Types.PlayerAttr.Status, status)
		end
	end
end

-------------------------------------------------------------------------------
-- Join / leave / respawn
-------------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local rec = records[player]
	if not rec then
		return
	end
	rec.CharTrove:Clean()
	-- Respawning clears hiding (the old character is gone).
	if rec.Hidden then
		local spot = rec.Hidden
		rec.Hidden = nil
		if spotOccupant[spot] == player then
			spotOccupant[spot] = nil
		end
		if spotPrompts[spot] then
			spotPrompts[spot].Enabled = true
		end
	end
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or records[player] ~= rec or player.Character ~= character then
		return
	end
	humanoid.WalkSpeed = GameConfig.Player.WalkSpeed
	rec.SpookedUntil = 0
	character:WaitForChild("HumanoidRootPart", 10)
	if records[player] ~= rec or player.Character ~= character then
		return
	end
	if rec.Captured then
		task.defer(teleportCharacter, player, World.CageCenter + Vector3.new(0, 3, 0))
	end
	updateTitleBillboard(player, rec)
	PlayerStateService.sync(player)
end

local function onPlayerAdded(player: Player)
	if records[player] then
		return
	end
	local rec = newRecord()
	records[player] = rec
	PlayerStateService.sync(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	PlayerStateService.PlayerJoined:Fire(player)
end

local function onPlayerRemoving(player: Player)
	local rec = records[player]
	if not rec then
		return
	end
	if rec.Hidden and spotOccupant[rec.Hidden] == player then
		spotOccupant[rec.Hidden] = nil
		if spotPrompts[rec.Hidden] then
			spotPrompts[rec.Hidden].Enabled = true
		end
	end
	rec.CharTrove:Destroy()
	records[player] = nil
	unhideLimiter:reset(player)
	promptLimiter:reset(player)
	refreshRescuePrompt()
	PlayerStateService.PlayerLeft:Fire(player)
end

-- Resets per-round state and respawns everyone at camp. Glow persists for the server session.
function PlayerStateService.resetRound()
	for player, rec in pairs(records) do
		if rec.Hidden then
			PlayerStateService.unhide(player)
		end
		rec.Inventory = InventoryLogic.new()
		rec.Captured = false
		rec.CapturedAt = 0
		rec.ImmuneUntil = 0
		rec.SpookedUntil = 0
		rec.Stats = newStats()
		rec.Status = Types.PlayerStatus.Safe
		PlayerStateService.sync(player)
		task.spawn(function()
			local ok, err = pcall(function()
				player:LoadCharacter()
			end)
			if not ok then
				warn("[PlayerState] LoadCharacter failed: " .. tostring(err))
			end
		end)
	end
	table.clear(spotOccupant)
	for _, prompt in pairs(spotPrompts) do
		prompt.Enabled = true
	end
	refreshRescuePrompt()
end

function PlayerStateService.getStats(player: Player)
	local rec = records[player]
	return rec and rec.Stats
end

-------------------------------------------------------------------------------

local function makePrompt(parent: Instance, action: string, object: string, hold: number, distance: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = hold
	prompt.MaxActivationDistance = distance
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end
PlayerStateService.makePrompt = makePrompt

function PlayerStateService.init(services, world)
	Services = services
	World = world
end

function PlayerStateService.start()
	-- Hiding spot prompts
	for _, spot in ipairs(World.HidingSpots) do
		local prompt = makePrompt(spot, "Hide", "Hiding Spot", 0.3, GameConfig.Hiding.PromptDistance)
		prompt.Name = "HidePrompt"
		spotPrompts[spot] = prompt
		prompt.Triggered:Connect(function(player)
			onHide(player, spot)
		end)
	end

	-- Rescue prompt
	rescuePrompt = makePrompt(World.CageLock, "Rescue", "Giggle Cage", 1.5, GameConfig.Capture.RescuePromptDistance)
	rescuePrompt.Name = "RescuePrompt"
	rescuePrompt.Enabled = false
	rescuePrompt.Triggered:Connect(onRescue)

	Remotes.get("RequestUnhide").OnServerEvent:Connect(function(player)
		if not unhideLimiter:allow(player) then
			return
		end
		PlayerStateService.unhide(player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	PlayerStateService.resetCourage()

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(tick)
			if not ok then
				warn("[PlayerState] tick error: " .. tostring(err))
			end
		end
	end)
end

return PlayerStateService
