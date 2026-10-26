-- ConfigValidator: sanity checks for GameConfig. Returns a list of problems (empty = valid).

local ConfigValidator = {}

local function positive(problems, path, value)
	if type(value) ~= "number" or value <= 0 then
		table.insert(problems, path .. " must be a positive number")
	end
end

function ConfigValidator.validate(cfg)
	local problems = {}

	for _, mode in ipairs({ "Normal", "Test" }) do
		local phases = cfg.Phases[mode]
		if type(phases) ~= "table" then
			table.insert(problems, "Phases." .. mode .. " missing")
		else
			for _, phase in ipairs({ "Intermission", "Day", "Sunset", "Night", "Dawn", "Results" }) do
				positive(problems, "Phases." .. mode .. "." .. phase, phases[phase])
			end
		end
	end

	if #cfg.Escalation < 1 then
		table.insert(problems, "Escalation needs at least one night")
	end
	for index, entry in ipairs(cfg.Escalation) do
		positive(problems, "Escalation[" .. index .. "].SunnySpeed", entry.SunnySpeed)
		if entry.SunnySpeed >= cfg.Player.WalkSpeed then
			table.insert(problems, "Escalation[" .. index .. "].SunnySpeed must stay below Player.WalkSpeed (fairness)")
		end
		positive(problems, "Escalation[" .. index .. "].DetectRadius", entry.DetectRadius)
	end

	if cfg.Nights.VictoryNight > cfg.Nights.MaxNights then
		table.insert(problems, "Nights.VictoryNight must be <= Nights.MaxNights")
	end

	for _, name in ipairs(cfg.ResourceOrder) do
		local res = cfg.Resources[name]
		if not res then
			table.insert(problems, "Resources." .. name .. " missing")
		else
			positive(problems, "Resources." .. name .. ".NodeHits", res.NodeHits)
			positive(problems, "Resources." .. name .. ".RespawnTime", res.RespawnTime)
		end
	end

	for _, id in ipairs(cfg.UpgradeOrder) do
		local up = cfg.Upgrades[id]
		if not up then
			table.insert(problems, "Upgrades." .. id .. " missing")
		elseif #up.Costs < 1 then
			table.insert(problems, "Upgrades." .. id .. ".Costs empty")
		end
	end
	if #cfg.Upgrades.FireRing.Costs + 1 > #cfg.Camp.FireLevels then
		table.insert(problems, "Camp.FireLevels needs an entry for every FireRing level")
	end

	if cfg.Objectives.CluesGoal > #cfg.Clues then
		table.insert(problems, "Objectives.CluesGoal exceeds number of clues")
	end
	local seen = {}
	for _, clue in ipairs(cfg.Clues) do
		if seen[clue.Id] then
			table.insert(problems, "Duplicate clue id " .. clue.Id)
		end
		seen[clue.Id] = true
	end

	if cfg.Events.FirstNightGuaranteed and not cfg.Events.Definitions[cfg.Events.FirstNightGuaranteed] then
		table.insert(problems, "Events.FirstNightGuaranteed is not a defined event")
	end

	for remote, limit in pairs(cfg.RateLimits) do
		if limit.MaxCalls < 1 or limit.Window <= 0 then
			table.insert(problems, "RateLimits." .. remote .. " invalid")
		end
	end

	return problems
end

return ConfigValidator
