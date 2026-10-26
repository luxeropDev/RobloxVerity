-- WorldBootstrap: builds the whole map procedurally from primitive parts.
-- Deterministic for a given seed. Returns a `world` table of references used by services.
-- Geometry only: services attach prompts and behavior.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local WorldBootstrap = {}

local WORLD_CFG = GameConfig.World
local GROUND_Y = 0

local COLORS = {
	Grass = Color3.fromRGB(96, 168, 82),
	GrassFar = Color3.fromRGB(80, 140, 72),
	Dirt = Color3.fromRGB(150, 112, 74),
	Trunk = Color3.fromRGB(105, 72, 48),
	Stone = Color3.fromRGB(128, 128, 136),
	Wood = Color3.fromRGB(160, 116, 70),
	DarkWood = Color3.fromRGB(96, 66, 44),
	Ribbon = Color3.fromRGB(255, 140, 40),
	Berry = Color3.fromRGB(210, 40, 70),
	Bush = Color3.fromRGB(46, 110, 52),
	Token = Color3.fromRGB(120, 255, 230),
	SunnyYellow = Color3.fromRGB(255, 214, 64),
	Fire = Color3.fromRGB(255, 150, 60),
	Water = Color3.fromRGB(40, 90, 120),
	Glass = Color3.fromRGB(255, 200, 240),
}

local CANOPY_COLORS = {
	Color3.fromRGB(58, 140, 70),
	Color3.fromRGB(70, 156, 64),
	Color3.fromRGB(44, 122, 78),
	Color3.fromRGB(86, 150, 58),
	Color3.fromRGB(52, 132, 96),
}

local partCount = 0

local function newPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, opts)
	opts = opts or {}
	local p = Instance.new(opts.ClassName or "Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.Shape and p:IsA("Part") then
		p.Shape = opts.Shape
	end
	if opts.CanCollide ~= nil then
		p.CanCollide = opts.CanCollide
	end
	if opts.CanQuery ~= nil then
		p.CanQuery = opts.CanQuery
	end
	if opts.CanTouch ~= nil then
		p.CanTouch = opts.CanTouch
	end
	if opts.Transparency then
		p.Transparency = opts.Transparency
	end
	p.CastShadow = opts.CastShadow == true
	p.Parent = parent
	partCount += 1
	return p
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function addSign(p: BasePart, text: string, face: Enum.NormalId, textColor: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = Vector2.new(400, 200)
	gui.LightInfluence = 0.3
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = textColor or Color3.fromRGB(40, 30, 20)
	label.Text = text
	label.Parent = gui
	gui.Parent = p
	return label
end

-- Simple keep-out zones for placement.
local Zones = {}
Zones.__index = Zones

function Zones.new()
	return setmetatable({ circles = {} }, Zones)
end

function Zones:add(x: number, z: number, r: number)
	table.insert(self.circles, { x = x, z = z, r = r })
end

function Zones:addSegment(ax: number, az: number, bx: number, bz: number, r: number)
	local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local steps = math.max(1, math.floor(length / 8))
	for i = 0, steps do
		local t = i / steps
		self:add(ax + (bx - ax) * t, az + (bz - az) * t, r)
	end
end

function Zones:isFree(x: number, z: number, r: number): boolean
	for _, c in ipairs(self.circles) do
		local dx, dz = x - c.x, z - c.z
		local min = r + c.r
		if dx * dx + dz * dz < min * min then
			return false
		end
	end
	return true
end

local function inPlayableArea(x: number, z: number, margin: number): boolean
	local half = WORLD_CFG.MapHalfSize - margin
	if math.abs(x) > half or math.abs(z) > half then
		return false
	end
	-- Keep everything out of the ravine band.
	if math.abs(z - WORLD_CFG.RavineZ) < WORLD_CFG.RavineWidth / 2 + margin + 4 then
		return false
	end
	return true
end

-- Finds a free spot in a ring around the camp. Returns nil after maxAttempts.
local function findSpot(rng: Random, zones, minR: number, maxR: number, radius: number, campSideOnly: boolean?)
	for _ = 1, 60 do
		local angle = rng:NextNumber() * math.pi * 2
		local dist = minR + rng:NextNumber() * (maxR - minR)
		local x = math.cos(angle) * dist
		local z = math.sin(angle) * dist
		local okSide = (not campSideOnly) or z > WORLD_CFG.RavineZ + WORLD_CFG.RavineWidth
		if okSide and inPlayableArea(x, z, radius) and zones:isFree(x, z, radius) then
			zones:add(x, z, radius)
			return Vector3.new(x, GROUND_Y, z)
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- Builders
-------------------------------------------------------------------------------

local function buildGround(root: Instance)
	local f = folder(root, "Ground")
	local half = WORLD_CFG.MapHalfSize
	local ravineNear = WORLD_CFG.RavineZ + WORLD_CFG.RavineWidth / 2
	local ravineFar = WORLD_CFG.RavineZ - WORLD_CFG.RavineWidth / 2

	local nearDepth = half - ravineNear
	newPart(f, "GroundMain", Vector3.new(half * 2, 4, nearDepth), at(0, GROUND_Y - 2, ravineNear + nearDepth / 2), COLORS.Grass, Enum.Material.Grass)
	local farDepth = ravineFar + half
	newPart(f, "GroundFar", Vector3.new(half * 2, 4, farDepth), at(0, GROUND_Y - 2, -half + farDepth / 2), COLORS.GrassFar, Enum.Material.Grass)
	newPart(f, "RavineFloor", Vector3.new(half * 2, 4, WORLD_CFG.RavineWidth), at(0, GROUND_Y - 40, WORLD_CFG.RavineZ), COLORS.Water, Enum.Material.Slate)

	-- Invisible map borders.
	local wallH = 60
	local walls = {
		{ Vector3.new(4, wallH, half * 2), at(half + 2, wallH / 2, 0) },
		{ Vector3.new(4, wallH, half * 2), at(-half - 2, wallH / 2, 0) },
		{ Vector3.new(half * 2, wallH, 4), at(0, wallH / 2, half + 2) },
		{ Vector3.new(half * 2, wallH, 4), at(0, wallH / 2, -half - 2) },
	}
	for i, w in ipairs(walls) do
		newPart(f, "Border" .. i, w[1], w[2], COLORS.Grass, Enum.Material.SmoothPlastic, { Transparency = 1, CanQuery = false })
	end

	-- Ravine guard rails (invisible) on the camp side, with a gap at the bridge that has its own barrier.
	local railZ = ravineNear - 1
	local gapHalf = 6
	local sideLen = half - gapHalf
	newPart(f, "RavineGuardWest", Vector3.new(sideLen, 14, 2), at(-gapHalf - sideLen / 2, 7, railZ), COLORS.Grass, nil, { Transparency = 1, CanQuery = false })
	newPart(f, "RavineGuardEast", Vector3.new(sideLen, 14, 2), at(gapHalf + sideLen / 2, 7, railZ), COLORS.Grass, nil, { Transparency = 1, CanQuery = false })
	local farRailZ = ravineFar + 1
	newPart(f, "RavineGuardFarWest", Vector3.new(sideLen, 14, 2), at(-gapHalf - sideLen / 2, 7, farRailZ), COLORS.Grass, nil, { Transparency = 1, CanQuery = false })
	newPart(f, "RavineGuardFarEast", Vector3.new(sideLen, 14, 2), at(gapHalf + sideLen / 2, 7, farRailZ), COLORS.Grass, nil, { Transparency = 1, CanQuery = false })
end

local function buildPath(parent: Instance, name: string, a: Vector3, b: Vector3)
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt(Vector3.new(mid.X, GROUND_Y + 0.05, mid.Z), Vector3.new(b.X, GROUND_Y + 0.05, b.Z))
	newPart(parent, name, Vector3.new(6, 0.1, length), cf, COLORS.Dirt, Enum.Material.Ground, { CanCollide = false, CanQuery = false })
end

local function buildCamp(root: Instance, world)
	local camp = folder(root, "Camp")
	local c = WORLD_CFG.CampCenter

	-- Clearing patch
	newPart(camp, "Clearing", Vector3.new(0.1, 56, 56), CFrame.new(c.X, GROUND_Y + 0.04, c.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(130, 170, 90), Enum.Material.Grass, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false })

	-- Campfire
	local fire = model(camp, "Campfire")
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		newPart(fire, "Stone" .. i, Vector3.new(1.4, 1, 1.4), at(c.X + math.cos(a) * 3, GROUND_Y + 0.5, c.Z + math.sin(a) * 3) * CFrame.Angles(0, a, 0), COLORS.Stone, Enum.Material.Slate)
	end
	newPart(fire, "LogA", Vector3.new(4.5, 0.9, 0.9), at(c.X, GROUND_Y + 0.6, c.Z) * CFrame.Angles(0, math.rad(35), 0), COLORS.DarkWood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	newPart(fire, "LogB", Vector3.new(4.5, 0.9, 0.9), at(c.X, GROUND_Y + 0.9, c.Z) * CFrame.Angles(0, math.rad(-55), 0), COLORS.DarkWood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	local firePart = newPart(fire, "FireCore", Vector3.new(2, 2, 2), at(c.X, GROUND_Y + 1.5, c.Z), COLORS.Fire, Enum.Material.Neon, { CanCollide = false, Transparency = 0.4, CanQuery = false })
	local fx = Instance.new("Fire")
	fx.Name = "Flames"
	fx.Size = 8
	fx.Heat = 12
	fx.Color = Color3.fromRGB(255, 140, 40)
	fx.SecondaryColor = Color3.fromRGB(255, 220, 90)
	fx.Parent = firePart
	local light = Instance.new("PointLight")
	light.Name = "FireLight"
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Range = GameConfig.Camp.LightRangeMax
	light.Brightness = 2.5
	light.Shadows = false
	light.Parent = firePart
	fire.PrimaryPart = firePart
	world.Campfire = fire
	world.FirePart = firePart

	-- Safe-radius ring (vertical cylinder, resized by CampService)
	local ring = newPart(camp, "SafeRing", Vector3.new(0.3, 52, 52), CFrame.new(c.X, GROUND_Y + 0.12, c.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 190, 110), Enum.Material.ForceField, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 0.2 })
	world.SafeRing = ring

	-- Log benches
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.rad(45)
		local pos = Vector3.new(c.X + math.cos(a) * 8, GROUND_Y + 0.7, c.Z + math.sin(a) * 8)
		newPart(camp, "Bench" .. i, Vector3.new(5, 1.4, 1.4), CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z)), COLORS.Wood, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	end

	-- Spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CampSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = at(c.X, GROUND_Y + 0.2, c.Z + 15)
	spawn.Color = Color3.fromRGB(240, 200, 120)
	spawn.Material = Enum.Material.WoodPlanks
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = camp
	partCount += 1
	world.SpawnLocation = spawn

	-- Supply crate (deposit)
	local crate = newPart(camp, "SupplyCrate", Vector3.new(4, 3, 4), at(c.X - 11, GROUND_Y + 1.5, c.Z + 4), COLORS.Wood, Enum.Material.WoodPlanks)
	addSign(crate, "CAMP CRATE", Enum.NormalId.Front)
	addSign(crate, "CAMP CRATE", Enum.NormalId.Back)
	world.SupplyCrate = crate

	-- Cooking pot (snacks)
	newPart(camp, "PotStand", Vector3.new(3, 0.6, 3), at(c.X - 7, GROUND_Y + 0.3, c.Z - 9), COLORS.Stone, Enum.Material.Slate)
	local pot = newPart(camp, "CookingPot", Vector3.new(2, 2.4, 2.4), at(c.X - 7, GROUND_Y + 1.6, c.Z - 9) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 60, 66), Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	world.CookingPot = pot

	-- Upgrade bench (client opens the upgrade panel from its prompt)
	local bench = newPart(camp, "UpgradeBench", Vector3.new(5, 2.6, 2.4), at(c.X + 10, GROUND_Y + 1.3, c.Z + 6), COLORS.DarkWood, Enum.Material.WoodPlanks)
	addSign(bench, "CAMP UPGRADES", Enum.NormalId.Front, Color3.fromRGB(255, 240, 200))
	addSign(bench, "CAMP UPGRADES", Enum.NormalId.Back, Color3.fromRGB(255, 240, 200))
	world.UpgradeBench = bench

	world.CampCenter = Vector3.new(c.X, GROUND_Y, c.Z)
	world.BuiltFolder = folder(camp, "Built")
end

local function buildCabin(root: Instance, world, zones)
	local cabin = model(root, "Cabin")
	local cx, cz = 30, -16
	local w, d, h = 16, 12, 9
	newPart(cabin, "Floor", Vector3.new(w, 0.6, d), at(cx, GROUND_Y + 0.3, cz), COLORS.Wood, Enum.Material.WoodPlanks)
	newPart(cabin, "WallBack", Vector3.new(1, h, d), at(cx + w / 2, GROUND_Y + h / 2, cz), COLORS.DarkWood, Enum.Material.WoodPlanks)
	newPart(cabin, "WallNorth", Vector3.new(w, h, 1), at(cx, GROUND_Y + h / 2, cz + d / 2), COLORS.DarkWood, Enum.Material.WoodPlanks)
	newPart(cabin, "WallSouth", Vector3.new(w, h, 1), at(cx, GROUND_Y + h / 2, cz - d / 2), COLORS.DarkWood, Enum.Material.WoodPlanks)
	-- Front wall (facing camp, -X) with a door gap.
	local side = (d - 5) / 2
	newPart(cabin, "WallFrontA", Vector3.new(1, h, side), at(cx - w / 2, GROUND_Y + h / 2, cz + 2.5 + side / 2), COLORS.DarkWood, Enum.Material.WoodPlanks)
	newPart(cabin, "WallFrontB", Vector3.new(1, h, side), at(cx - w / 2, GROUND_Y + h / 2, cz - 2.5 - side / 2), COLORS.DarkWood, Enum.Material.WoodPlanks)
	newPart(cabin, "WallFrontTop", Vector3.new(1, 2, 5), at(cx - w / 2, GROUND_Y + h - 1, cz), COLORS.DarkWood, Enum.Material.WoodPlanks)
	newPart(cabin, "Roof", Vector3.new(w + 2, 1, d + 2), at(cx, GROUND_Y + h + 0.5, cz), Color3.fromRGB(150, 60, 50), Enum.Material.Slate)
	newPart(cabin, "Table", Vector3.new(3, 2.5, 2), at(cx + 4, GROUND_Y + 1.25, cz + 3), COLORS.Wood, Enum.Material.Wood)
	local closet = newPart(cabin, "Closet", Vector3.new(3, 6, 3), at(cx + 5.5, GROUND_Y + 3, cz - 3.5), COLORS.DarkWood, Enum.Material.WoodPlanks, { CanCollide = false })
	world.CabinHidingSpot = closet
	local note = newPart(cabin, "CabinNote", Vector3.new(1.2, 0.1, 1.6), at(cx + 4, GROUND_Y + 2.55, cz + 3), Color3.fromRGB(245, 235, 200), Enum.Material.SmoothPlastic, { CanCollide = false })
	world.ClueSpots.Cabin = note
	world.CabinCenter = Vector3.new(cx, GROUND_Y, cz)
	zones:add(cx, cz, 14)
end

local function buildRadioPost(root: Instance, world, zones)
	local post = model(root, "RangerPost")
	local x, z = -95, 70
	newPart(post, "Table", Vector3.new(5, 2.6, 3), at(x, GROUND_Y + 1.3, z), COLORS.Wood, Enum.Material.WoodPlanks)
	local radio = newPart(post, "Radio", Vector3.new(2.4, 1.6, 1.4), at(x, GROUND_Y + 3.4, z), Color3.fromRGB(70, 90, 70), Enum.Material.Metal)
	newPart(post, "Antenna", Vector3.new(0.2, 4, 0.2), at(x + 0.9, GROUND_Y + 6, z), Color3.fromRGB(200, 200, 200), Enum.Material.Metal)
	local radioLight = newPart(post, "RadioLight", Vector3.new(0.4, 0.4, 0.4), at(x - 0.8, GROUND_Y + 3.9, z - 0.71), Color3.fromRGB(120, 30, 30), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
	local sign = newPart(post, "PostSign", Vector3.new(6, 2, 0.4), at(x, GROUND_Y + 5, z + 3), COLORS.Wood, Enum.Material.Wood)
	addSign(sign, "RANGER POST", Enum.NormalId.Front)
	world.Radio = radio
	world.RadioLight = radioLight
	world.RadioPosition = radio.Position
	zones:add(x, z, 16)
	table.insert(world.Landmarks, { Name = "the Ranger Post", Position = Vector3.new(x, 0, z) })
end

local function buildBridge(root: Instance, world, zones)
	local bridge = model(root, "Bridge")
	local near = WORLD_CFG.RavineZ + WORLD_CFG.RavineWidth / 2
	local far = WORLD_CFG.RavineZ - WORLD_CFG.RavineWidth / 2
	local stub = 4
	newPart(bridge, "StubNear", Vector3.new(10, 1, stub), at(0, GROUND_Y - 0.5, near - stub / 2), COLORS.Wood, Enum.Material.WoodPlanks)
	newPart(bridge, "StubFar", Vector3.new(10, 1, stub), at(0, GROUND_Y - 0.5, far + stub / 2), COLORS.Wood, Enum.Material.WoodPlanks)
	local gapStart = near - stub
	local gapEnd = far + stub
	local gap = gapStart - gapEnd
	local stages = GameConfig.Objectives.BridgeStages
	local seg = gap / stages
	world.BridgePlanks = {}
	for i = 1, stages do
		local zc = gapStart - seg * (i - 0.5)
		local plank = newPart(bridge, "Stage" .. i, Vector3.new(10, 1, seg), at(0, GROUND_Y - 0.5, zc), COLORS.Wood, Enum.Material.WoodPlanks, { Transparency = 0.85, CanCollide = false })
		world.BridgePlanks[i] = plank
	end
	-- Dangling broken planks (decor)
	newPart(bridge, "BrokenPlank1", Vector3.new(3, 0.6, 6), at(-2, GROUND_Y - 4, gapStart - 3) * CFrame.Angles(math.rad(60), 0, math.rad(10)), COLORS.DarkWood, Enum.Material.Wood, { CanCollide = false })
	newPart(bridge, "BrokenPlank2", Vector3.new(3, 0.6, 5), at(2.5, GROUND_Y - 5, gapEnd + 3) * CFrame.Angles(math.rad(-55), 0, math.rad(-8)), COLORS.DarkWood, Enum.Material.Wood, { CanCollide = false })
	for _, sx in ipairs({ -5.5, 5.5 }) do
		newPart(bridge, "PostNear", Vector3.new(1, 5, 1), at(sx, GROUND_Y + 2, near - 0.5), COLORS.DarkWood, Enum.Material.Wood)
		newPart(bridge, "PostFar", Vector3.new(1, 5, 1), at(sx, GROUND_Y + 2, far + 0.5), COLORS.DarkWood, Enum.Material.Wood)
	end
	local barrier = newPart(bridge, "BridgeBarrier", Vector3.new(12, 14, 2), at(0, 7, near - 1), COLORS.Wood, nil, { Transparency = 1, CanQuery = false })
	local sign = newPart(bridge, "BridgeSign", Vector3.new(6, 2.5, 0.4), at(0, GROUND_Y + 4, near + 3), COLORS.Wood, Enum.Material.Wood)
	sign.CFrame = sign.CFrame * CFrame.Angles(0, math.rad(180), 0)
	addSign(sign, "BRIDGE OUT", Enum.NormalId.Front, Color3.fromRGB(150, 20, 20))
	world.BridgeBarrier = barrier
	world.BridgeSign = sign
	world.BridgePosition = Vector3.new(0, GROUND_Y, near + 3)

	-- Far side: ranger station (where the ending truck arrives)
	newPart(bridge, "RangerStation", Vector3.new(14, 8, 10), at(0, GROUND_Y + 4, far - 30), Color3.fromRGB(110, 140, 100), Enum.Material.WoodPlanks)
	zones:add(0, near + 6, 14)
	table.insert(world.Landmarks, { Name = "the Broken Bridge", Position = Vector3.new(0, 0, near) })
end

local function buildShrine(root: Instance, world, zones)
	local shrine = model(root, "Shrine")
	local x, z = 140, 115
	newPart(shrine, "Base", Vector3.new(12, 1, 8), at(x, GROUND_Y + 0.5, z), COLORS.Stone, Enum.Material.Cobblestone)
	newPart(shrine, "PillarL", Vector3.new(1.5, 9, 1.5), at(x - 4.5, GROUND_Y + 5.5, z), COLORS.Stone, Enum.Material.Cobblestone)
	newPart(shrine, "PillarR", Vector3.new(1.5, 9, 1.5), at(x + 4.5, GROUND_Y + 5.5, z), COLORS.Stone, Enum.Material.Cobblestone)
	newPart(shrine, "Arch", Vector3.new(11, 1.5, 2), at(x, GROUND_Y + 10.5, z), COLORS.Stone, Enum.Material.Cobblestone)
	local slab = newPart(shrine, "Carving", Vector3.new(5, 5, 0.8), at(x, GROUND_Y + 3.5, z), Color3.fromRGB(110, 110, 118), Enum.Material.Slate)
	addSign(slab, ":)", Enum.NormalId.Front, COLORS.SunnyYellow)
	newPart(shrine, "Orb", Vector3.new(1.6, 1.6, 1.6), at(x, GROUND_Y + 12.2, z), COLORS.SunnyYellow, Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
	world.ClueSpots.Shrine = slab
	world.ShrinePosition = Vector3.new(x, GROUND_Y, z)

	-- Giggle Cage
	local cage = model(root, "GiggleCage")
	local cx, cz = x + 12, z - 12
	local size = 8
	newPart(cage, "Floor", Vector3.new(size, 0.6, size), at(cx, GROUND_Y + 0.3, cz), Color3.fromRGB(230, 170, 220), Enum.Material.SmoothPlastic)
	newPart(cage, "Roof", Vector3.new(size, 0.6, size), at(cx, GROUND_Y + 9, cz), Color3.fromRGB(230, 170, 220), Enum.Material.SmoothPlastic)
	local wallOpts = { Transparency = 0.35 }
	newPart(cage, "WallN", Vector3.new(size, 9, 0.5), at(cx, GROUND_Y + 4.5, cz + size / 2), COLORS.Glass, Enum.Material.ForceField, wallOpts)
	newPart(cage, "WallS", Vector3.new(size, 9, 0.5), at(cx, GROUND_Y + 4.5, cz - size / 2), COLORS.Glass, Enum.Material.ForceField, wallOpts)
	newPart(cage, "WallE", Vector3.new(0.5, 9, size), at(cx + size / 2, GROUND_Y + 4.5, cz), COLORS.Glass, Enum.Material.ForceField, wallOpts)
	newPart(cage, "WallW", Vector3.new(0.5, 9, size), at(cx - size / 2, GROUND_Y + 4.5, cz), COLORS.Glass, Enum.Material.ForceField, wallOpts)
	local lock = newPart(cage, "CageLock", Vector3.new(1.6, 1.6, 0.6), at(cx - size / 2 - 0.6, GROUND_Y + 3, cz), COLORS.SunnyYellow, Enum.Material.Neon)
	local sign = newPart(cage, "CageSign", Vector3.new(6, 1.6, 0.3), at(cx, GROUND_Y + 10.4, cz - size / 2), Color3.fromRGB(255, 230, 250), Enum.Material.SmoothPlastic)
	addSign(sign, "GIGGLE CAGE", Enum.NormalId.Front, Color3.fromRGB(200, 60, 160))
	world.CageLock = lock
	world.CageCenter = Vector3.new(cx, GROUND_Y + 1, cz)
	zones:add(x, z, 18)
	zones:add(cx, cz, 10)
	table.insert(world.Landmarks, { Name = "the Strange Shrine", Position = Vector3.new(x, 0, z) })
end

local function buildTourBus(root: Instance, world, zones)
	local bus = model(root, "TourBus")
	local x, z = 195, -70
	local cf = at(x, GROUND_Y, z) * CFrame.Angles(0, math.rad(25), math.rad(4))
	newPart(bus, "Body", Vector3.new(22, 8, 8), cf * CFrame.new(0, 5, 0), Color3.fromRGB(220, 190, 90), Enum.Material.Metal)
	newPart(bus, "Windows", Vector3.new(18, 2.5, 8.2), cf * CFrame.new(-1, 6.5, 0), Color3.fromRGB(40, 50, 60), Enum.Material.Glass)
	for i, offset in ipairs({ Vector3.new(-7, 1.4, 4), Vector3.new(7, 1.4, 4), Vector3.new(-7, 1.4, -4), Vector3.new(7, 1.4, -4) }) do
		newPart(bus, "Wheel" .. i, Vector3.new(1.2, 3, 3), cf * CFrame.new(offset) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(30, 30, 30), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	end
	local sign = newPart(bus, "BusSign", Vector3.new(10, 2, 0.3), cf * CFrame.new(0, 7.5, 4.2), Color3.fromRGB(255, 240, 210), Enum.Material.SmoothPlastic, { CanCollide = false })
	addSign(sign, "SUNNY TOURS", Enum.NormalId.Back, Color3.fromRGB(230, 120, 20))
	world.ClueSpots.TourBus = sign
	zones:add(x, z, 18)
	table.insert(world.Landmarks, { Name = "the Old Tour Bus", Position = Vector3.new(x, 0, z) })
end

local function buildLandmarks(root: Instance, world, zones)
	local lm = folder(root, "Landmarks")

	-- Mushroom ring (secret)
	local mx, mz = -190, 170
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local px, pz = mx + math.cos(a) * 5, mz + math.sin(a) * 5
		newPart(lm, "MushroomStem", Vector3.new(0.6, 1.6, 0.6), at(px, GROUND_Y + 0.8, pz), Color3.fromRGB(240, 230, 210), Enum.Material.SmoothPlastic, { CanCollide = false })
		newPart(lm, "MushroomCap", Vector3.new(1.8, 1.8, 1.8), at(px, GROUND_Y + 1.8, pz), Color3.fromRGB(200, 60, 200), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
	local ringClue = newPart(lm, "MushroomClue", Vector3.new(1.5, 0.2, 1.5), at(mx, GROUND_Y + 0.15, mz), Color3.fromRGB(255, 255, 220), Enum.Material.Neon, { CanCollide = false })
	world.ClueSpots.MushroomRing = ringClue
	zones:add(mx, mz, 12)
	table.insert(world.Landmarks, { Name = "the Mushroom Ring", Position = Vector3.new(mx, 0, mz) })

	-- Big rock
	newPart(lm, "BigRock", Vector3.new(16, 16, 16), at(-150, GROUND_Y + 5, -60), COLORS.Stone, Enum.Material.Slate, { Shape = Enum.PartType.Ball })
	zones:add(-150, -60, 12)
	table.insert(world.Landmarks, { Name = "the Big Rock", Position = Vector3.new(-150, 0, -60) })

	-- Fallen giant log
	newPart(lm, "GiantLog", Vector3.new(36, 5, 5), at(60, GROUND_Y + 2.5, 160) * CFrame.Angles(0, math.rad(30), 0), COLORS.Trunk, Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
	zones:add(60, 160, 20)
	table.insert(world.Landmarks, { Name = "the Fallen Log", Position = Vector3.new(60, 0, 160) })

	-- Signpost on the bridge path
	newPart(lm, "SignPole", Vector3.new(0.6, 7, 0.6), at(5, GROUND_Y + 3.5, -110), COLORS.DarkWood, Enum.Material.Wood)
	local board = newPart(lm, "SignBoard", Vector3.new(5, 1.6, 0.3), at(5, GROUND_Y + 6, -110), COLORS.Wood, Enum.Material.Wood)
	addSign(board, "BRIDGE ->", Enum.NormalId.Front)
	addSign(board, "<- BRIDGE", Enum.NormalId.Back)
	zones:add(5, -110, 4)
	table.insert(world.Landmarks, { Name = "the Old Signpost", Position = Vector3.new(5, 0, -110) })
	table.insert(world.Landmarks, { Name = "the Camp", Position = WORLD_CFG.CampCenter })
end

local function buildTree(parent: Instance, rng: Random, pos: Vector3, tag: string?)
	local height = 9 + rng:NextNumber() * 7
	local canopy = 8 + rng:NextNumber() * 5
	local m = model(parent, "Tree")
	local trunk = newPart(m, "Trunk", Vector3.new(2, height, 2), at(pos.X, GROUND_Y + height / 2, pos.Z), COLORS.Trunk, Enum.Material.Wood)
	newPart(m, "Canopy", Vector3.new(canopy, canopy, canopy), at(pos.X, GROUND_Y + height + canopy * 0.25, pos.Z), CANOPY_COLORS[rng:NextInteger(1, #CANOPY_COLORS)], Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
	m.PrimaryPart = trunk
	if tag then
		CollectionService:AddTag(m, tag)
	end
	return m
end

local function buildResourceNode(parent: Instance, rng: Random, kind: string, pos: Vector3)
	local m = model(parent, kind .. "Node")
	local primary
	if kind == "Wood" then
		local height = 8 + rng:NextNumber() * 3
		primary = newPart(m, "Trunk", Vector3.new(2.6, height, 2.6), at(pos.X, GROUND_Y + height / 2, pos.Z), COLORS.Trunk, Enum.Material.Wood)
		newPart(m, "Ribbon", Vector3.new(2.8, 0.6, 2.8), at(pos.X, GROUND_Y + 3.2, pos.Z), COLORS.Ribbon, Enum.Material.Neon, { CanCollide = false })
		newPart(m, "Canopy", Vector3.new(9, 9, 9), at(pos.X, GROUND_Y + height + 2, pos.Z), Color3.fromRGB(110, 180, 70), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
	elseif kind == "Stone" then
		local s = 3.5 + rng:NextNumber() * 2
		primary = newPart(m, "Rock", Vector3.new(s * 1.3, s, s), at(pos.X, GROUND_Y + s / 2 - 0.3, pos.Z) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), COLORS.Stone, Enum.Material.Slate)
	elseif kind == "Food" then
		primary = newPart(m, "Bush", Vector3.new(4, 4, 4), at(pos.X, GROUND_Y + 1.6, pos.Z), COLORS.Bush, Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
		for i = 1, 3 do
			local a = (i / 3) * math.pi * 2
			newPart(m, "Berry" .. i, Vector3.new(0.8, 0.8, 0.8), at(pos.X + math.cos(a) * 1.7, GROUND_Y + 2.2, pos.Z + math.sin(a) * 1.7), COLORS.Berry, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	else -- Token
		primary = newPart(m, "Sparkle", Vector3.new(1.4, 1.4, 1.4), at(pos.X, GROUND_Y + 2, pos.Z), COLORS.Token, Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		local light = Instance.new("PointLight")
		light.Color = COLORS.Token
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = primary
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = COLORS.Token
		sparkles.Parent = primary
	end
	m.PrimaryPart = primary
	m:SetAttribute("ResourceType", kind)
	CollectionService:AddTag(m, "ResourceNode")
	return m
end

local function buildHidingSpot(parent: Instance, pos: Vector3, index: number)
	local bush = newPart(parent, "HidingBush" .. index, Vector3.new(6, 6, 6), at(pos.X, GROUND_Y + 2.2, pos.Z), Color3.fromRGB(34, 90, 44), Enum.Material.Grass, { Shape = Enum.PartType.Ball, CanCollide = false })
	CollectionService:AddTag(bush, "HidingSpot")
	return bush
end

-------------------------------------------------------------------------------

function WorldBootstrap.build(seed: number)
	partCount = 0
	local existing = workspace:FindFirstChild("World")
	if existing then
		existing:Destroy()
	end

	local rng = Random.new(seed)
	local root = Instance.new("Folder")
	root.Name = "World"

	local world = {
		Root = root,
		Seed = seed,
		ClueSpots = {},
		Landmarks = {},
		ResourceNodes = {},
		HidingSpots = {},
		SpareNodePositions = {},
		PatrolPoints = {},
	}

	local zones = Zones.new()
	zones:add(0, 0, 22) -- camp core stays clear

	buildGround(root)
	buildCamp(root, world)
	buildCabin(root, world, zones)
	buildRadioPost(root, world, zones)
	buildBridge(root, world, zones)
	buildShrine(root, world, zones)
	buildTourBus(root, world, zones)
	buildLandmarks(root, world, zones)

	local paths = folder(root, "Paths")
	local campEdge = Vector3.new(0, 0, 0)
	local pathTargets = {
		{ "PathRadio", world.RadioPosition },
		{ "PathShrine", world.ShrinePosition },
		{ "PathBridge", world.BridgePosition },
		{ "PathBus", Vector3.new(195, 0, -70) },
	}
	for _, entry in ipairs(pathTargets) do
		buildPath(paths, entry[1], campEdge, entry[2])
		zones:addSegment(campEdge.X, campEdge.Z, entry[2].X, entry[2].Z, 5)
	end

	-- Resource nodes. The first wood nodes are close to spawn for a quick start.
	local nodes = folder(root, "ResourceNodes")
	local function placeNodes(kind: string, count: number, minR: number, maxR: number, nearFirst: number)
		for i = 1, count do
			local lo, hi = minR, maxR
			if i <= nearFirst then
				lo, hi = 16, 32
			end
			local pos = findSpot(rng, zones, lo, hi, 4, true)
			if pos then
				table.insert(world.ResourceNodes, buildResourceNode(nodes, rng, kind, pos))
			end
		end
	end
	placeNodes("Wood", WORLD_CFG.WoodNodes, 24, 150, 3)
	placeNodes("Stone", WORLD_CFG.RockNodes, 30, 170, 1)
	placeNodes("Food", WORLD_CFG.BerryNodes, 26, 160, 1)
	placeNodes("Token", WORLD_CFG.TokenNodes, 80, 240, 0)

	-- Hiding spots (plus the cabin closet)
	local hiding = folder(root, "HidingSpots")
	for i = 1, WORLD_CFG.HidingSpots do
		local pos = findSpot(rng, zones, 45, 160, 5, true)
		if pos then
			table.insert(world.HidingSpots, buildHidingSpot(hiding, pos, i))
		end
	end
	CollectionService:AddTag(world.CabinHidingSpot, "HidingSpot")
	table.insert(world.HidingSpots, world.CabinHidingSpot)

	-- Decorative forest
	local forest = folder(root, "Forest")
	for _ = 1, WORLD_CFG.TreeCount do
		local pos = findSpot(rng, zones, WORLD_CFG.TreeMinRadius, WORLD_CFG.MapHalfSize * 1.3, 4, false)
		if pos then
			buildTree(forest, rng, pos, nil)
		end
	end

	-- Positions (no instances) for shifted nodes and SUNNY patrols.
	for _ = 1, WORLD_CFG.SpareNodePositions do
		local pos = findSpot(rng, zones, 40, 170, 3, true)
		if pos then
			table.insert(world.SpareNodePositions, pos)
		end
	end
	for _ = 1, WORLD_CFG.PatrolPoints do
		local pos = findSpot(rng, zones, 60, 220, 2, true)
		if pos then
			table.insert(world.PatrolPoints, pos)
		end
	end
	if #world.PatrolPoints == 0 then
		table.insert(world.PatrolPoints, world.ShrinePosition)
	end

	for _, part in pairs(world.ClueSpots) do
		CollectionService:AddTag(part, "ClueSpot")
	end

	root.Parent = workspace
	-- Template places (e.g. Baseplate) ship their own SpawnLocation; disable it so everyone spawns at camp.
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") and d ~= world.SpawnLocation then
			d.Enabled = false
			warn("[World] Disabled extra SpawnLocation " .. d:GetFullName())
		end
	end
	world.PartCount = partCount
	if partCount > WORLD_CFG.MaxParts then
		warn(string.format("[World] Part budget exceeded: %d > %d", partCount, WORLD_CFG.MaxParts))
	end
	return world
end

-- Horizontal distance helper used across services.
function WorldBootstrap.flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

return WorldBootstrap
