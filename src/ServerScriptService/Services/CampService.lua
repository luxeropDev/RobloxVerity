-- CampService: campfire fuel and light, safe radius, shared stockpile, deposits, snacks and upgrades.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.GameConfig)
local Types = require(Shared.Types)
local Remotes = require(Shared.Remotes)

local Lib = ServerScriptService.Lib
local InventoryLogic = require(Lib.InventoryLogic)
local RateLimiter = require(Lib.RateLimiter)
local Trove = require(Lib.Trove)

local CampService = {}

local CAMP = GameConfig.Camp

local Services
local World

local fuel = CAMP.FuelStart
local fireLevel = 1
local levels = {}
local stock = InventoryLogic.new()
local barricadeHp = 0
local lastBarricadeHit = 0
local lowFuelWarned = false
local fireOutWarned = false
local lanternTrove = Trove.new()
local barricadeTrove = Trove.new()
local upgradeLimiter = RateLimiter.new(GameConfig.RateLimits.RequestUpgrade.MaxCalls, GameConfig.RateLimits.RequestUpgrade.Window)

local function resetLevels()
	for _, id in ipairs(GameConfig.UpgradeOrder) do
		levels[id] = 0
	end
end
resetLevels()

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-------------------------------------------------------------------------------
-- Queries
-------------------------------------------------------------------------------

function CampService.getCenter(): Vector3
	return World.CampCenter
end

function CampService.getMaxFuel(): number
	return CAMP.FireLevels[fireLevel].MaxFuel
end

function CampService.getFuel(): number
	return fuel
end

function CampService.getSafeRadius(): number
	if fuel <= 0 then
		return 0
	end
	local maxFuel = CampService.getMaxFuel()
	local full = CAMP.SafeRadiusBase + CAMP.FireLevels[fireLevel].RadiusBonus + levels.Lanterns * GameConfig.Upgrades.Lanterns.RadiusPerLevel
	local frac = math.clamp(fuel / (maxFuel * CAMP.FullRadiusFuelFraction), 0, 1)
	return CAMP.SafeRadiusMin + (full - CAMP.SafeRadiusMin) * frac
end

function CampService.isBarricadeActive(): boolean
	return levels.Barricade > 0 and barricadeHp > 0
end

-- Radius SUNNY cannot enter.
function CampService.getRepelRadius(): number
	local r = CampService.getSafeRadius()
	if CampService.isBarricadeActive() then
		r = math.max(r, CAMP.BarricadeRadius)
	end
	return r
end

function CampService.isInSafeZone(position: Vector3, margin: number?): boolean
	return flatDistance(position, World.CampCenter) <= CampService.getRepelRadius() + (margin or 0)
end

function CampService.getCapacityBonus(): number
	return (levels.Storage or 0) * GameConfig.Upgrades.Storage.CapacityPerLevel
end

function CampService.getLevels()
	return table.clone(levels)
end

function CampService.getStock()
	return table.clone(stock)
end

-------------------------------------------------------------------------------
-- Replication
-------------------------------------------------------------------------------

function CampService.broadcastStock(player: Player?)
	local remote = Remotes.get("StockpileUpdated")
	if player then
		remote:FireClient(player, table.clone(stock), table.clone(levels))
	else
		remote:FireAllClients(table.clone(stock), table.clone(levels))
	end
end

local function syncState()
	local state = Remotes.getState()
	state:SetAttribute(Types.StateAttr.Fuel, math.floor(fuel + 0.5))
	state:SetAttribute(Types.StateAttr.FuelMax, CampService.getMaxFuel())
	state:SetAttribute(Types.StateAttr.SafeRadius, math.floor(CampService.getRepelRadius() * 10) / 10)
	state:SetAttribute(Types.StateAttr.FireLevel, fireLevel)
	state:SetAttribute(Types.StateAttr.BarricadeHP, barricadeHp)
end

local function updateVisuals()
	local maxFuel = CampService.getMaxFuel()
	local frac = math.clamp(fuel / maxFuel, 0, 1)
	local light = World.FirePart:FindFirstChild("FireLight")
	local flames = World.FirePart:FindFirstChild("Flames")
	if light then
		light.Range = CAMP.LightRangeMin + (CAMP.LightRangeMax - CAMP.LightRangeMin) * frac
		light.Enabled = fuel > 0
	end
	if flames then
		flames.Enabled = fuel > 0
		flames.Size = 3 + 9 * frac
	end
	World.FirePart.Transparency = 0.4
	if fuel <= 0 then
		World.FirePart.Transparency = 1
	end
	local radius = CampService.getRepelRadius()
	local ring = World.SafeRing
	if radius <= 0.5 then
		ring.Transparency = 1
	else
		ring.Transparency = 0.2
		local goal = { Size = Vector3.new(0.3, radius * 2, radius * 2) }
		TweenService:Create(ring, TweenInfo.new(CAMP.TickInterval, Enum.EasingStyle.Linear), goal):Play()
	end
end

-------------------------------------------------------------------------------
-- Upgrade visuals
-------------------------------------------------------------------------------

local function buildLanterns()
	lanternTrove:Clean()
	if levels.Lanterns <= 0 then
		return
	end
	local cfg = GameConfig.Upgrades.Lanterns
	local radius = CAMP.SafeRadiusBase + CAMP.FireLevels[fireLevel].RadiusBonus + (levels.Lanterns - 1) * cfg.RadiusPerLevel
	local center = World.CampCenter
	for i = 1, cfg.LanternCount do
		local a = (i / cfg.LanternCount) * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		local pole = Instance.new("Part")
		pole.Name = "LanternPole"
		pole.Anchored = true
		pole.Size = Vector3.new(0.5, 6, 0.5)
		pole.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
		pole.Color = Color3.fromRGB(90, 60, 40)
		pole.Material = Enum.Material.Wood
		pole.CastShadow = false
		pole.Parent = World.BuiltFolder
		lanternTrove:Add(pole)
		local lamp = Instance.new("Part")
		lamp.Name = "Lantern"
		lamp.Anchored = true
		lamp.CanCollide = false
		lamp.Size = Vector3.new(1.2, 1.4, 1.2)
		lamp.CFrame = CFrame.new(pos + Vector3.new(0, 6.6, 0))
		lamp.Color = Color3.fromRGB(255, 200, 120)
		lamp.Material = Enum.Material.Neon
		lamp.CastShadow = false
		local light = Instance.new("PointLight")
		light.Range = 16
		light.Brightness = 1.4
		light.Color = Color3.fromRGB(255, 190, 120)
		light.Parent = lamp
		lamp.Parent = World.BuiltFolder
		lanternTrove:Add(lamp)
	end
end

local function buildBarricade()
	barricadeTrove:Clean()
	if levels.Barricade <= 0 then
		return
	end
	local cfg = GameConfig.Upgrades.Barricade
	local center = World.CampCenter
	local radius = CAMP.BarricadeRadius
	for i = 1, cfg.SegmentCount do
		local a = (i / cfg.SegmentCount) * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * radius, 1.6, math.sin(a) * radius)
		local seg = Instance.new("Part")
		seg.Name = "Fence"
		seg.Anchored = true
		seg.Size = Vector3.new(9, 3.2, 0.8)
		seg.CFrame = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
		seg.Color = Color3.fromRGB(150, 105, 60)
		seg.Material = Enum.Material.WoodPlanks
		seg.CastShadow = false
		seg.Parent = World.BuiltFolder
		barricadeTrove:Add(seg)
	end
end

local function refreshBarricadeLook()
	local cfg = CAMP.BarricadeHP
	local health = math.clamp(barricadeHp / cfg, 0, 1)
	for _, child in ipairs(World.BuiltFolder:GetChildren()) do
		if child.Name == "Fence" then
			child.Transparency = 0.6 * (1 - health)
		end
	end
end

-- Called by SUNNY when it pushes against the barricade.
function CampService.hitBarricade(): boolean
	if not CampService.isBarricadeActive() then
		return false
	end
	local now = os.clock()
	if now - lastBarricadeHit < CAMP.BarricadeHitCooldown then
		return true
	end
	lastBarricadeHit = now
	barricadeHp -= 1
	refreshBarricadeLook()
	if barricadeHp <= 0 then
		barricadeTrove:Clean()
		levels.Barricade = 0 -- can be rebuilt next day
		CampService.broadcastStock()
		Services.PlayerStateService.notifyAll("SUNNY broke through the fence! Rebuild it tomorrow.", "danger")
	else
		Services.PlayerStateService.notifyAll(string.format("SUNNY is bonking the fence! (%d left)", barricadeHp), "warn")
	end
	syncState()
	return barricadeHp > 0
end

local function applyUpgrade(id: string)
	if id == "FireRing" then
		fireLevel = math.min(#CAMP.FireLevels, levels.FireRing + 1)
		buildLanterns() -- lantern ring follows the fire radius
	elseif id == "Storage" then
		for _, player in ipairs(Services.PlayerStateService.getPlayers()) do
			Services.PlayerStateService.sync(player)
		end
	elseif id == "Lanterns" then
		buildLanterns()
	elseif id == "Barricade" then
		barricadeHp = CAMP.BarricadeHP
		buildBarricade()
	end
end

-------------------------------------------------------------------------------
-- Player actions (all server-validated)
-------------------------------------------------------------------------------

local function nearCampObject(player: Player, part: BasePart): boolean
	return Services.PlayerStateService.isWithin(player, part.Position, CAMP.PromptDistance + 5)
end

function CampService.addFuel(player: Player)
	local PS = Services.PlayerStateService
	if not PS.allowPrompt(player) or not PS.canAct(player) or not nearCampObject(player, World.FirePart) then
		return
	end
	local maxFuel = CampService.getMaxFuel()
	if fuel >= maxFuel - 0.5 then
		PS.notify(player, "The fire is already roaring!", "info")
		return
	end
	local needed = math.ceil((maxFuel - fuel) / CAMP.FuelPerWood)
	local inv = PS.getInventory(player)
	local fromInventory = math.min(needed, inv.Wood)
	local used = 0
	if fromInventory > 0 then
		used = PS.removeResource(player, "Wood", fromInventory)
	else
		-- Nothing carried: use up to 3 wood from the shared stockpile.
		local fromStock = math.min(needed, 3, stock.Wood)
		if fromStock <= 0 then
			PS.notify(player, "You need wood! Chop trees with orange ribbons.", "warn")
			return
		end
		stock.Wood -= fromStock
		used = fromStock
		CampService.broadcastStock()
	end
	fuel = math.min(maxFuel, fuel + used * CAMP.FuelPerWood)
	PS.addStat(player, "FuelAdded", used)
	Services.ObjectiveService.progress("feed_fire", 1)
	if fuel > maxFuel * 0.25 then
		lowFuelWarned = false
	end
	fireOutWarned = false
	PS.notify(player, string.format("+%d fuel. The fire crackles happily.", used * CAMP.FuelPerWood), "success")
	PS.playSound("Fuel", World.FirePart.Position)
	syncState()
	updateVisuals()
end

function CampService.deposit(player: Player)
	local PS = Services.PlayerStateService
	if not PS.allowPrompt(player) or not PS.canAct(player) or not nearCampObject(player, World.SupplyCrate) then
		return
	end
	local inv = PS.getInventory(player)
	local moved, total = InventoryLogic.transferAll(inv, stock)
	if total <= 0 then
		PS.notify(player, "Your pockets are empty. Go gather something!", "info")
		return
	end
	PS.addStat(player, "Deposited", total)
	PS.sync(player)
	local parts = {}
	for _, name in ipairs(GameConfig.ResourceOrder) do
		if moved[name] then
			table.insert(parts, string.format("%d %s", moved[name], GameConfig.Resources[name].DisplayName))
		end
	end
	PS.notify(player, "Deposited " .. table.concat(parts, ", ") .. ".", "success")
	PS.playSound("Deposit", World.SupplyCrate.Position, nil, player)
	CampService.broadcastStock()
end

function CampService.cookSnack(player: Player)
	local PS = Services.PlayerStateService
	if not PS.allowPrompt(player) or not PS.canAct(player) or not nearCampObject(player, World.CookingPot) then
		return
	end
	local current, max = PS.getCourage()
	if current >= max then
		PS.notify(player, "Everyone is already brave. Save the berries!", "info")
		return
	end
	if not InventoryLogic.spend(stock, GameConfig.Courage.SnackCost) then
		PS.notify(player, "Need " .. InventoryLogic.formatCost(GameConfig.Courage.SnackCost) .. " in the camp crate.", "warn")
		return
	end
	PS.changeCourage(GameConfig.Courage.SnackRestore)
	PS.addStat(player, "Snacks", 1)
	PS.notifyAll(player.DisplayName .. " cooked berry snacks! Courage +" .. GameConfig.Courage.SnackRestore, "success")
	CampService.broadcastStock()
end

function CampService.requestUpgrade(player: Player, upgradeId)
	local PS = Services.PlayerStateService
	if not upgradeLimiter:allow(player) then
		return
	end
	if type(upgradeId) ~= "string" then
		return
	end
	local def = GameConfig.Upgrades[upgradeId]
	if not def then
		return
	end
	local phase = Services.PhaseService.getPhase()
	if phase == "Night" then
		PS.notify(player, "Too dark to build! Survive until morning.", "warn")
		return
	end
	if phase == "Intermission" or phase == "Results" then
		return
	end
	if not PS.canAct(player) then
		return
	end
	if not PS.isWithin(player, World.CampCenter, CAMP.InteractRadius) then
		PS.notify(player, "Get back to camp to build.", "warn")
		return
	end
	local level = levels[upgradeId]
	local cost = def.Costs[level + 1]
	if not cost then
		PS.notify(player, def.DisplayName .. " is already maxed out.", "info")
		return
	end
	if not InventoryLogic.spend(stock, cost) then
		PS.notify(player, "Need " .. InventoryLogic.formatCost(cost) .. " in the camp crate.", "warn")
		return
	end
	levels[upgradeId] = level + 1
	applyUpgrade(upgradeId)
	PS.notifyAll(string.format("%s built %s (level %d)!", player.DisplayName, def.DisplayName, levels[upgradeId]), "success")
	PS.playSound("Upgrade", World.CampCenter)
	CampService.broadcastStock()
	syncState()
	updateVisuals()
end

-- Used by objectives (radio, bridge). All-or-nothing.
function CampService.spendStock(cost): boolean
	if InventoryLogic.spend(stock, cost) then
		CampService.broadcastStock()
		return true
	end
	return false
end

-------------------------------------------------------------------------------
-- Tick
-------------------------------------------------------------------------------

local function tick(dt: number)
	local phase = Services.PhaseService.getPhase()
	local rate = 0
	if phase == "Night" then
		rate = CAMP.FuelDecayNight * Services.PhaseService.getEscalation().FuelDecayMult
	elseif phase == "Day" or phase == "Sunset" or phase == "Dawn" then
		rate = CAMP.FuelDecayDay
	end
	rate *= CAMP.FireLevels[fireLevel].DecayMult
	if rate > 0 and fuel > 0 then
		fuel = math.max(0, fuel - rate * dt)
		local maxFuel = CampService.getMaxFuel()
		if not lowFuelWarned and fuel <= maxFuel * 0.25 then
			lowFuelWarned = true
			Services.PlayerStateService.notifyAll("The campfire is getting low! Add wood!", "warn")
		end
		if fuel <= 0 and not fireOutWarned then
			fireOutWarned = true
			Services.PlayerStateService.notifyAll("The fire went out! The camp is not safe!", "danger")
		end
	end
	syncState()
	updateVisuals()
end

function CampService.reset()
	fuel = CAMP.FuelStart
	fireLevel = 1
	resetLevels()
	stock = InventoryLogic.new()
	barricadeHp = 0
	lowFuelWarned = false
	fireOutWarned = false
	lanternTrove:Clean()
	barricadeTrove:Clean()
	syncState()
	updateVisuals()
	CampService.broadcastStock()
end

function CampService.init(services, world)
	Services = services
	World = world
end

function CampService.start()
	local makePrompt = Services.PlayerStateService.makePrompt
	local firePrompt = makePrompt(World.FirePart, "Add Wood", "Campfire", 0.3, CAMP.PromptDistance)
	firePrompt.Triggered:Connect(CampService.addFuel)
	local cratePrompt = makePrompt(World.SupplyCrate, "Deposit All", "Camp Crate", 0.2, CAMP.PromptDistance)
	cratePrompt.Triggered:Connect(CampService.deposit)
	local potPrompt = makePrompt(World.CookingPot, "Cook Snack", "Cooking Pot", 0.8, CAMP.PromptDistance)
	potPrompt.Triggered:Connect(CampService.cookSnack)
	-- The bench prompt only opens the client's upgrade panel; the server validates the build request itself.
	local benchPrompt = makePrompt(World.UpgradeBench, "Open Upgrades", "Workbench", 0, CAMP.PromptDistance)
	benchPrompt.Name = "UpgradeBenchPrompt"

	Remotes.get("RequestUpgrade").OnServerEvent:Connect(CampService.requestUpgrade)

	Services.PlayerStateService.PlayerJoined:Connect(function(player)
		CampService.broadcastStock(player)
	end)
	Services.PlayerStateService.PlayerLeft:Connect(function(player)
		upgradeLimiter:reset(player)
	end)

	CampService.reset()

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(CAMP.TickInterval)
			local now = os.clock()
			local ok, err = pcall(tick, now - last)
			last = now
			if not ok then
				warn("[Camp] tick error: " .. tostring(err))
			end
		end
	end)
end

return CampService
