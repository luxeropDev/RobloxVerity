-- ShiftingNodes: some resource nodes relocate in the night. Nobody saw them move.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

return {
	Id = "ShiftingNodes",
	run = function(ctx)
		local count = GameConfig.Gathering.ShiftCountBase + ctx.Night
		local moved = ctx.Services.ResourceService.shiftNodes(count, ctx.Rng)
		if moved > 0 then
			ctx.notifyAll("Did that tree just... move? Some resources have shifted!", "mystery")
		end
	end,
}
