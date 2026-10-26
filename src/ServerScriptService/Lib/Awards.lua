-- Awards: assigns one funny recap title per player from round stats.

local Awards = {}

-- Ordered by priority. Each award goes to the player with the highest stat (> 0) who has no award yet.
Awards.Definitions = table.freeze({
	{ Stat = "Rescues", Title = "Cage Cracker" },
	{ Stat = "Gathered", Title = "Professional Log Hugger" },
	{ Stat = "FuelAdded", Title = "Fire Whisperer" },
	{ Stat = "CluesFound", Title = "Detective Marshmallow" },
	{ Stat = "TimesChased", Title = "Cardio Champion" },
	{ Stat = "Captures", Title = "SUNNY's Favorite" },
	{ Stat = "Snacks", Title = "Head Chef" },
	{ Stat = "Deposited", Title = "Team Pack Mule" },
})

Awards.Default = "Happy Camper"

-- rows: { {key=any, stats={...}} } -> { [key] = title }
function Awards.assign(rows)
	local result = {}
	for _, def in ipairs(Awards.Definitions) do
		local bestKey, bestValue = nil, 0
		for _, row in ipairs(rows) do
			local value = row.stats[def.Stat] or 0
			if result[row.key] == nil and value > bestValue then
				bestKey, bestValue = row.key, value
			end
		end
		if bestKey ~= nil then
			result[bestKey] = def.Title
		end
	end
	for _, row in ipairs(rows) do
		if result[row.key] == nil then
			result[row.key] = Awards.Default
		end
	end
	return result
end

function Awards.titleForGlow(glow: number, titles): string
	local title = titles[1].Title
	for _, entry in ipairs(titles) do
		if glow >= entry.Glow then
			title = entry.Title
		end
	end
	return title
end

return Awards
