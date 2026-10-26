-- TestRunner: tiny test harness for Studio.
-- Command bar (while a Play/Run session is active, server side):
--   require(game.ServerStorage.Tests.TestRunner).run()              -- unit + integration
--   require(game.ServerStorage.Tests.TestRunner).run({ unitOnly = true })
-- Integration specs change live game state. Run them only in a local Studio session.

local TestRunner = {}

local function deepEqual(a, b): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function expect(actual)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
		end
	end
	function e.toEqual(expected)
		if not deepEqual(actual, expected) then
			error("tables differ", 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error("expected truthy, got " .. tostring(actual), 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error("expected falsy, got " .. tostring(actual), 2)
		end
	end
	function e.toBeNear(expected, epsilon)
		if math.abs(actual - expected) > (epsilon or 1e-6) then
			error(string.format("expected ~%s, got %s", tostring(expected), tostring(actual)), 2)
		end
	end
	function e.toBeGreaterThan(expected)
		if not (actual > expected) then
			error(string.format("expected > %s, got %s", tostring(expected), tostring(actual)), 2)
		end
	end
	function e.toBeAtMost(expected)
		if not (actual <= expected) then
			error(string.format("expected <= %s, got %s", tostring(expected), tostring(actual)), 2)
		end
	end
	return e
end

local function runFolder(folder: Instance, results)
	for _, module in ipairs(folder:GetChildren()) do
		if module:IsA("ModuleScript") then
			local tests = {}
			local t = {
				expect = expect,
				test = function(name: string, fn)
					table.insert(tests, { name = name, fn = fn })
				end,
			}
			local okLoad, spec = pcall(require, module)
			if not okLoad or type(spec) ~= "function" then
				table.insert(results.failures, module.Name .. ": failed to load: " .. tostring(spec))
				results.failed += 1
			else
				local okDefine, defineErr = pcall(spec, t)
				if not okDefine then
					table.insert(results.failures, module.Name .. ": define error: " .. tostring(defineErr))
					results.failed += 1
				end
				for _, test in ipairs(tests) do
					local ok, err = pcall(test.fn)
					if ok then
						results.passed += 1
					else
						results.failed += 1
						table.insert(results.failures, module.Name .. " > " .. test.name .. ": " .. tostring(err))
					end
				end
			end
		end
	end
end

function TestRunner.run(options)
	options = options or {}
	local results = { passed = 0, failed = 0, failures = {} }
	runFolder(script.Parent.Unit, results)
	if not options.unitOnly then
		runFolder(script.Parent.Integration, results)
	end
	print(string.format("[Tests] %d passed, %d failed", results.passed, results.failed))
	for _, failure in ipairs(results.failures) do
		warn("[Tests] FAIL " .. failure)
	end
	return results
end

return TestRunner
