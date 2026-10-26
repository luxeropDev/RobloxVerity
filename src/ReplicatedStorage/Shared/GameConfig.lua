-- GameConfig: every gameplay tunable lives here.
-- Shared by server and client. Clients only read display values; the server is authoritative.

local GameConfig = {}

GameConfig.Version = "0.1.0"
GameConfig.GameTitle = "SURVIVE THE NIGHT"
GameConfig.GameSubtitle = "The Smiling Stranger"

-- nil = random seed per server. Set a number for a deterministic map while testing.
GameConfig.Seed = nil

-- "Auto": short timings in Studio when exactly one player is present. "On": always short. "Off": never.
GameConfig.SoloTestMode = "Auto"

GameConfig.Debug = {
	LogPhases = true,
	LogSunnyStates = false,
	LogEvents = true,
}

-- Phase durations in seconds.
GameConfig.Phases = {
	Normal = { Intermission = 12, Day = 150, Sunset = 20, Night = 120, Dawn = 12, Results = 25 },
	Test = { Intermission = 4, Day = 45, Sunset = 8, Night = 60, Dawn = 6, Results = 15 },
	MinPlayersToStart = 1,
	FinalDawnBonus = 6, -- extra dawn seconds before the ending plays
}

GameConfig.Nights = {
	VictoryNight = 3, -- surviving to this dawn with the bridge repaired wins
	MaxNights = 5, -- dawn of this night without the bridge = "Forever Campers"
}

-- Escalation per night. The last entry is reused for later nights.
GameConfig.Escalation = {
	{ SunnySpeed = 12, DetectRadius = 50, SuspicionRate = 0.7, Events = 2, FuelDecayMult = 1.0 },
	{ SunnySpeed = 13.5, DetectRadius = 60, SuspicionRate = 0.9, Events = 3, FuelDecayMult = 1.2 },
	{ SunnySpeed = 14.5, DetectRadius = 70, SuspicionRate = 1.1, Events = 3, FuelDecayMult = 1.4 },
	{ SunnySpeed = 15, DetectRadius = 75, SuspicionRate = 1.25, Events = 4, FuelDecayMult = 1.6 },
	{ SunnySpeed = 15.5, DetectRadius = 80, SuspicionRate = 1.4, Events = 4, FuelDecayMult = 1.8 },
}

GameConfig.Player = {
	WalkSpeed = 16,
	SpookedWalkSpeed = 10,
	SpookedDuration = 5,
}

GameConfig.Inventory = {
	BaseCapacity = 10,
}

GameConfig.ResourceOrder = { "Wood", "Stone", "Food", "Token" }

GameConfig.Resources = {
	Wood = { DisplayName = "Wood", NodeName = "Tree", ActionText = "Chop", NodeHits = 4, Yield = 1, RespawnTime = 60, HoldDuration = 0.5, NightNoise = 1.0 },
	Stone = { DisplayName = "Stone", NodeName = "Rock", ActionText = "Mine", NodeHits = 3, Yield = 1, RespawnTime = 75, HoldDuration = 0.7, NightNoise = 1.3 },
	Food = { DisplayName = "Berries", NodeName = "Berry Bush", ActionText = "Pick", NodeHits = 2, Yield = 1, RespawnTime = 45, HoldDuration = 0.4, NightNoise = 0.5 },
	Token = { DisplayName = "Tokens", NodeName = "Strange Sparkle", ActionText = "Grab", NodeHits = 1, Yield = 1, RespawnTime = 120, HoldDuration = 0.3, NightNoise = 0.3 },
}

GameConfig.Gathering = {
	MaxDistance = 12, -- server-side distance check (prompt distance + leeway)
	PromptDistance = 9,
	Cooldown = 0.45, -- seconds between gathers per player
	RespawnCheckInterval = 1,
	ShiftCountBase = 3,
}

GameConfig.Camp = {
	InteractRadius = 45, -- must be this close to the fire to build upgrades
	PromptDistance = 10,
	FuelStart = 70,
	FuelPerWood = 10,
	FuelDecayDay = 0.15, -- per second
	FuelDecayNight = 0.55, -- per second, multiplied by escalation
	SafeRadiusBase = 26, -- full radius at >= FullRadiusFuelFraction
	SafeRadiusMin = 9, -- radius when fuel is just above 0
	FullRadiusFuelFraction = 0.5,
	LightRangeMin = 12,
	LightRangeMax = 40,
	BarricadeRadius = 32,
	BarricadeHP = 6,
	BarricadeHitCooldown = 3,
	TickInterval = 0.5,
	FireLevels = {
		{ MaxFuel = 100, RadiusBonus = 0, DecayMult = 1.0 },
		{ MaxFuel = 130, RadiusBonus = 6, DecayMult = 0.9 },
		{ MaxFuel = 160, RadiusBonus = 12, DecayMult = 0.8 },
	},
}

-- Upgrade costs are paid from the shared stockpile. Index = level being bought.
GameConfig.Upgrades = {
	FireRing = {
		DisplayName = "Stronger Fire",
		Description = "Bigger light, more fuel, slower burn.",
		Costs = { { Wood = 8, Stone = 4 }, { Wood = 12, Stone = 8, Token = 1 } },
	},
	Storage = {
		DisplayName = "Bigger Backpacks",
		Description = "+5 carry capacity for everyone.",
		CapacityPerLevel = 5,
		Costs = { { Wood = 6, Food = 2 }, { Wood = 10, Food = 4, Token = 1 } },
	},
	Lanterns = {
		DisplayName = "Lantern Ring",
		Description = "Lanterns push the safe light further out.",
		RadiusPerLevel = 5,
		LanternCount = 6,
		Costs = { { Wood = 6, Stone = 2, Token = 1 }, { Wood = 8, Stone = 4, Token = 2 } },
	},
	Barricade = {
		DisplayName = "Spiky-ish Fence",
		Description = "Holds SUNNY back for a while, even if the fire fails.",
		SegmentCount = 12,
		Costs = { { Wood = 14, Stone = 6 } },
	},
}
GameConfig.UpgradeOrder = { "FireRing", "Storage", "Lanterns", "Barricade" }

GameConfig.Courage = {
	Base = 3,
	PerExtraPlayer = 1,
	Max = 8,
	SnackCost = { Food = 3 },
	SnackRestore = 1,
}

GameConfig.Capture = {
	Distance = 4.5,
	CageDuration = 25, -- auto release to camp after this many seconds
	ReleaseImmunity = 6,
	RescuePromptDistance = 8,
}

GameConfig.Hiding = {
	MaxDuration = 25,
	PromptDistance = 7,
	ExitOffset = 4,
	SpottedGrace = 1.5, -- hiding within this time after being seen during a chase makes SUNNY search the spot
}

GameConfig.Sunny = {
	TickInterval = 0.1,
	HoverHeight = 4.5,
	BobAmplitude = 0.6,
	BobSpeed = 2,
	DaySpeed = 10,
	RetreatSpeed = 18,
	InvestigateSpeedMult = 0.75,
	StalkSpeedMult = 0.8,
	StalkDistance = 20,
	SuspicionThreshold = 1,
	SuspicionDecay = 0.5, -- per second when not visible
	MovingSuspicionMult = 1.3,
	ObserveDuration = 8,
	StalkDuration = 3.5,
	ChaseMaxDuration = 12,
	LoseSightTime = 3,
	SearchDuration = 8,
	RetreatDuration = 6,
	InvestigateMaxTime = 12,
	PostCaptureCooldown = 10,
	LightEdgeBuffer = 3,
	EyeHeight = 1.2,
	DayHintInterval = 28,
	DayFollowDistance = 14,
	SpeechMinGap = 2.5,
	NoiseMemory = 10, -- seconds a noise stays interesting
	ArriveDistance = 4,
	Path = {
		AgentRadius = 3,
		AgentHeight = 6,
		WaypointSpacing = 6,
		RecomputeInterval = 0.8,
		RecomputeDistance = 8,
		Timeout = 1.5,
		StuckTime = 2.5,
		StuckProgress = 1.5,
		DriftHeight = 18, -- fallback: float over obstacles
		DriftDuration = 2.5,
	},
}

GameConfig.Events = {
	MinGap = 12,
	StartFraction = 0.12,
	EndFraction = 0.85,
	FirstNightGuaranteed = "SunnyAtEdge",
	FirstNightGuaranteedFraction = 0.2,
	Definitions = {
		FalseLantern = { Weight = 3, MinNight = 1, Duration = 30 },
		StrangeRadio = { Weight = 3, MinNight = 1, Duration = 12 },
		ShiftingNodes = { Weight = 2, MinNight = 2, Duration = 4 },
		SunnyAtEdge = { Weight = 2, MinNight = 1, Duration = 8 },
		Silhouette = { Weight = 2, MinNight = 1, Duration = 20 },
		StrangeCrate = { Weight = 3, MinNight = 1, Duration = 35 },
		FootstepsCabin = { Weight = 2, MinNight = 2, Duration = 12 },
		FakeSign = { Weight = 2, MinNight = 1, Duration = 40 },
	},
}

GameConfig.Objectives = {
	GatherWoodGoal = 8,
	FeedFireGoal = 3,
	CluesGoal = 4,
	RadioCost = { Stone = 4, Token = 1 },
	BridgeStages = 3,
	BridgeStageCost = { Wood = 8, Stone = 3 },
	PromptDistance = 10,
}

GameConfig.Clues = {
	{ Id = "shrine_carving", Spot = "Shrine", NightOnly = false, Title = "Shrine Carving", Text = "A carving of a smiling sun. Underneath: 'SUN-E: Smiling Unit for Nature Experiences.'" },
	{ Id = "bus_sign", Spot = "TourBus", NightOnly = false, Title = "Tour Bus Sign", Text = "'SUNNY TOURS: Nobody leaves without a smile!' Someone scratched out the word 'leaves'." },
	{ Id = "cabin_note", Spot = "Cabin", NightOnly = true, Title = "Ranger's Note", Text = "Ranger log: 'The guide bot will not power down. It keeps saying the tour is not over.'" },
	{ Id = "mushroom_ring", Spot = "MushroomRing", NightOnly = true, Title = "Tiny Writing", Text = "Tiny letters inside the mushroom ring: 'If it smiles too wide, stay in the light.'" },
	{ Id = "radio_log", Spot = nil, NightOnly = false, Title = "Radio Recording", Text = "'Ranger here. Fix the bridge and I can drive in at sunrise. Keep that fire going!'" },
	{ Id = "crate_receipt", Spot = nil, NightOnly = false, Title = "Strange Receipt", Text = "A receipt: '1x Smile Upgrade (Extra Wide). Paid by: SUNNY.'" },
}

GameConfig.Rewards = {
	GlowPerNightSurvived = 10,
	GlowPerClue = 3,
	GlowVictory = 20,
	Titles = {
		{ Glow = 0, Title = "Camp Newbie" },
		{ Glow = 15, Title = "Marshmallow Scout" },
		{ Glow = 35, Title = "Firefly Friend" },
		{ Glow = 60, Title = "Night Owl" },
		{ Glow = 90, Title = "Sun Chaser" },
	},
}

GameConfig.World = {
	MapHalfSize = 300,
	CampCenter = Vector3.new(0, 0, 0),
	TreeCount = 110,
	TreeMinRadius = 40,
	WoodNodes = 24,
	RockNodes = 14,
	BerryNodes = 12,
	TokenNodes = 6,
	SpareNodePositions = 30,
	HidingSpots = 8,
	PatrolPoints = 14,
	RavineZ = -200,
	RavineWidth = 26,
	MaxParts = 900,
}

GameConfig.Lighting = {
	Day = { ClockTime = 13, Brightness = 2.2, Ambient = Color3.fromRGB(120, 120, 110), OutdoorAmbient = Color3.fromRGB(150, 150, 140), FogEnd = 900, FogColor = Color3.fromRGB(190, 220, 255), Saturation = 0.15, Tint = Color3.fromRGB(255, 255, 255) },
	Sunset = { ClockTime = 17.8, Brightness = 1.4, Ambient = Color3.fromRGB(120, 80, 70), OutdoorAmbient = Color3.fromRGB(140, 90, 80), FogEnd = 500, FogColor = Color3.fromRGB(255, 150, 110), Saturation = 0.2, Tint = Color3.fromRGB(255, 225, 200) },
	Night = { ClockTime = 0.5, Brightness = 0.6, Ambient = Color3.fromRGB(25, 45, 55), OutdoorAmbient = Color3.fromRGB(35, 60, 70), FogEnd = 170, FogColor = Color3.fromRGB(20, 45, 50), Saturation = -0.1, Tint = Color3.fromRGB(190, 230, 225) },
	Dawn = { ClockTime = 6.4, Brightness = 1.5, Ambient = Color3.fromRGB(110, 100, 120), OutdoorAmbient = Color3.fromRGB(150, 130, 150), FogEnd = 450, FogColor = Color3.fromRGB(255, 200, 180), Saturation = 0.05, Tint = Color3.fromRGB(255, 235, 230) },
	TweenTime = 4,
}

-- Sound ids. Empty string = silent placeholder. See assets/ASSET_MANIFEST.md before adding ids.
GameConfig.Audio = {
	MasterVolume = 0.6,
	Sounds = {
		Gather = { Id = "rbxasset://sounds/clickfast.wav", Volume = 0.5 },
		Deposit = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5 },
		Upgrade = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7 },
		Fuel = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.4 },
		Giggle = { Id = "", Volume = 0.8 },
		Alert = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9 },
		Capture = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.9 },
		Footsteps = { Id = "rbxasset://sounds/action_footsteps_plastic.mp3", Volume = 0.8 },
		RadioStatic = { Id = "", Volume = 0.6 },
		Clue = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6 },
		DayAmbience = { Id = "", Volume = 0.3 },
		NightAmbience = { Id = "", Volume = 0.3 },
	},
}

-- Client->server rate limits: MaxCalls per Window seconds, per player.
GameConfig.RateLimits = {
	RequestUpgrade = { MaxCalls = 4, Window = 2 },
	RequestRestart = { MaxCalls = 3, Window = 5 },
	RequestUnhide = { MaxCalls = 4, Window = 2 },
	Prompt = { MaxCalls = 12, Window = 2 },
}

-- SUNNY's original dialogue.
GameConfig.Dialogue = {
	Greeting = {
		"Hi hi! I'm SUNNY, your forest guide! Grab some wood before it gets dark. Dark is... not my favorite!",
	},
	DayHints = {
		"Tip! The fire keeps you safe. The bigger the fire, the bigger the safe circle!",
		"Deposit your stuff in the camp crate so your friends can build things. Sharing is caring!",
		"That old radio by the ranger post looks broken. Stone and a token might fix it!",
		"Berries make snacks. Snacks make courage. Courage makes... more snacks? Science!",
		"The bridge is broken. Nobody can leave. Isn't that great? I mean, isn't that LATE. It's getting late.",
		"If something chases you, run to the light or hide in a bush. Just a random tip. No reason.",
		"I love visitors. I love them so much I never let them— I mean, I never let them get bored!",
	},
	Sunset = {
		"Ooh, sunset! My favorite part of the tour is coming up!",
		"The sun is going down. Stay close to the fire, campers. Or don't. I'm not your mom.",
	},
	NightStart = {
		"Tour part two: Night Mode! Please keep your arms and legs inside the light.",
		"Is everyone still here? Good. Good good good.",
	},
	Stalk = {
		"I see you~",
		"Peekaboo!",
		"You're doing great! Keep walking. Further. Further!",
		"Don't mind me. Just floating. Normally.",
	},
	Chase = {
		"Tag! You're it! Forever!",
		"Wait for me! The tour isn't over!",
		"Hug time!",
	},
	LightEdge = {
		"Ow. Too bright. Turn that off, please?",
		"That fire is very rude.",
		"I'll just wait here. I'm very patient.",
	},
	Capture = {
		"Gotcha! Welcome to the Giggle Cage!",
		"Another happy visitor!",
	},
	Search = {
		"Where did you go~?",
		"Hide and seek? I LOVE hide and seek.",
	},
	Retreat = {
		"Fine. FINE. I'll be back.",
		"Brb!",
	},
	Dawn = {
		"Good morning! You survived! For now. :)",
		"Rise and shine, campers! Did you miss me?",
	},
	Victory = {
		"You're leaving? But... the tour... Okay. Please leave a five-star review!",
	},
	SecretVictory = {
		"Oh. You found out what I am. The tour is over. Thank you for visiting. Powering down... goodnight, campers.",
	},
	Defeat = {
		"Everyone's in the Giggle Cage! Best. Tour. Ever.",
	},
	Forever = {
		"Another night? Yay! Forever camp! Forever friends!",
	},
}

table.freeze(GameConfig)

return GameConfig
