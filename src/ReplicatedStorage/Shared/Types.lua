-- Types: shared type definitions and string enums.
-- Enums are frozen tables so typos fail loudly (indexing a missing key returns nil and is caught by asserts).

export type Phase = "Intermission" | "Day" | "Sunset" | "Night" | "Dawn" | "Results"

export type SunnyState = "Dormant" | "Observing" | "Investigating" | "Stalking" | "Chasing" | "Searching" | "Retreating"

export type PlayerStatus = "Safe" | "Dark" | "Hidden" | "Watched" | "Chased" | "Captured"

export type Inventory = {
	Wood: number,
	Stone: number,
	Food: number,
	Token: number,
}

export type Cost = { [string]: number }

export type ObjectiveView = {
	Id: string,
	Title: string,
	Progress: number,
	Goal: number,
	Complete: boolean,
	Locked: boolean,
}

export type RecapRow = {
	Name: string,
	Gathered: number,
	FuelAdded: number,
	Rescues: number,
	Captures: number,
	CluesFound: number,
	Glow: number,
	Award: string,
}

export type Recap = {
	EndingId: string,
	EndingTitle: string,
	EndingText: string,
	Victory: boolean,
	NightsSurvived: number,
	CluesFound: number,
	CluesTotal: number,
	BridgeStages: number,
	Rows: { RecapRow },
}

local Types = {}

Types.Phase = table.freeze({
	Intermission = "Intermission",
	Day = "Day",
	Sunset = "Sunset",
	Night = "Night",
	Dawn = "Dawn",
	Results = "Results",
})

Types.SunnyState = table.freeze({
	Dormant = "Dormant",
	Observing = "Observing",
	Investigating = "Investigating",
	Stalking = "Stalking",
	Chasing = "Chasing",
	Searching = "Searching",
	Retreating = "Retreating",
})

Types.PlayerStatus = table.freeze({
	Safe = "Safe",
	Dark = "Dark",
	Hidden = "Hidden",
	Watched = "Watched",
	Chased = "Chased",
	Captured = "Captured",
})

Types.Ending = table.freeze({
	OverTheBridge = "OverTheBridge",
	SunnysGoodbye = "SunnysGoodbye",
	LightsOut = "LightsOut",
	ForeverCampers = "ForeverCampers",
})

Types.EndingInfo = table.freeze({
	OverTheBridge = { Title = "Over the Bridge", Victory = true, Text = "The ranger's truck rumbles across the repaired bridge at sunrise. Everyone piles in. SUNNY waves from the treeline." },
	SunnysGoodbye = { Title = "SUNNY's Goodbye", Victory = true, Text = "You uncovered SUNNY's story. The old tour robot finally ends the tour, waves, and powers down for a long, sunny nap." },
	LightsOut = { Title = "Lights Out", Victory = false, Text = "Everyone ended up in the Giggle Cage. SUNNY is thrilled. The tour continues..." },
	ForeverCampers = { Title = "Forever Campers", Victory = false, Text = "The bridge was never fixed. SUNNY has decided you live here now. Forever. With snacks." },
})

-- Attribute names used on the replicated GameState folder.
Types.StateAttr = table.freeze({
	Phase = "Phase",
	PhaseEndsAt = "PhaseEndsAt",
	PhaseDuration = "PhaseDuration",
	Night = "Night",
	Round = "Round",
	TestMode = "TestMode",
	Fuel = "Fuel",
	FuelMax = "FuelMax",
	SafeRadius = "SafeRadius",
	FireLevel = "FireLevel",
	Courage = "Courage",
	CourageMax = "CourageMax",
	SunnyState = "SunnyState",
	RestartVotes = "RestartVotes",
	RestartNeeded = "RestartNeeded",
	BarricadeHP = "BarricadeHP",
})

-- Attribute names used on each Player.
Types.PlayerAttr = table.freeze({
	Status = "Status",
	Capacity = "Capacity",
	Glow = "Glow",
	Title = "Title",
	Hidden = "Hidden",
	Captured = "Captured",
})

return table.freeze(Types)
