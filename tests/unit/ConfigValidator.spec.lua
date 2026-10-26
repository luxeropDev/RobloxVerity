local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ConfigValidator = require(ServerScriptService.Lib.ConfigValidator)

return function(t)
	t.test("shipped config is valid", function()
		local problems = ConfigValidator.validate(GameConfig)
		if #problems > 0 then
			error(table.concat(problems, "; "))
		end
	end)
end
