-- EventScheduler: pure function that plans which night events run and when.

local EventScheduler = {}

local function weightedPick(candidates, rng)
	local total = 0
	for _, c in ipairs(candidates) do
		total += c.weight
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for index, c in ipairs(candidates) do
		roll -= c.weight
		if roll <= 0 then
			return index
		end
	end
	return #candidates
end

--[[
params:
	night: number
	duration: number            -- night length in seconds
	count: number               -- events to schedule
	definitions: { [id]: {Weight, MinNight, Duration} }
	rng: Random
	eventsConfig: GameConfig.Events
	available: { [id]: true }?  -- ids that have an implementation (nil = all)
returns: array of { id = string, at = number } sorted by time.
]]
function EventScheduler.build(params)
	local cfg = params.eventsConfig
	local night = params.night
	local duration = params.duration
	local rng = params.rng

	local candidates = {}
	local ids = {}
	for id in pairs(params.definitions) do
		table.insert(ids, id)
	end
	table.sort(ids) -- deterministic order for a given seed
	for _, id in ipairs(ids) do
		local def = params.definitions[id]
		local implemented = params.available == nil or params.available[id] == true
		if implemented and night >= def.MinNight and def.Weight > 0 then
			table.insert(candidates, { id = id, weight = def.Weight })
		end
	end

	local chosen = {}
	if night == 1 and cfg.FirstNightGuaranteed then
		for index, c in ipairs(candidates) do
			if c.id == cfg.FirstNightGuaranteed then
				table.insert(chosen, { id = c.id, guaranteed = true })
				table.remove(candidates, index)
				break
			end
		end
	end

	while #chosen < params.count and #candidates > 0 do
		local index = weightedPick(candidates, rng)
		if not index then
			break
		end
		table.insert(chosen, { id = candidates[index].id })
		table.remove(candidates, index) -- no repeats within a night
	end

	-- Assign times: spread evenly across the active window with jitter, respecting MinGap.
	local startT = duration * cfg.StartFraction
	local endT = duration * cfg.EndFraction
	local window = math.max(1, endT - startT)
	local n = #chosen
	local schedule = {}
	local slot = window / math.max(1, n)
	local slotIndex = 0
	for _, entry in ipairs(chosen) do
		local at
		if entry.guaranteed then
			at = duration * cfg.FirstNightGuaranteedFraction
		else
			at = startT + slot * slotIndex + rng:NextNumber() * slot * 0.6
		end
		slotIndex += 1
		table.insert(schedule, { id = entry.id, at = at })
	end
	table.sort(schedule, function(a, b)
		return a.at < b.at
	end)
	for i = 2, #schedule do
		local minAt = schedule[i - 1].at + cfg.MinGap
		if schedule[i].at < minAt then
			schedule[i].at = minAt
		end
	end
	-- Drop anything pushed past the end of the night.
	local final = {}
	for _, entry in ipairs(schedule) do
		if entry.at <= duration - 2 then
			table.insert(final, entry)
		end
	end
	return final
end

return EventScheduler
