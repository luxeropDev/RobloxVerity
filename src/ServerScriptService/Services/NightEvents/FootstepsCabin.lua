-- FootstepsCabin: footsteps sound near the cabin, then a note appears on the cabin table.

return {
	Id = "FootstepsCabin",
	run = function(ctx)
		local cabin = ctx.World.CabinCenter
		ctx.playSound("Footsteps", cabin, 6)
		ctx.notifyAll("Footsteps... coming from the cabin?", "mystery")
		ctx.every(6, function()
			local objectives = ctx.Services.ObjectiveService
			objectives.revealClue("cabin_note")
			if not objectives.isClueFound("cabin_note") then
				ctx.notifyAll("Something left a note on the cabin table.", "mystery")
			end
			return false
		end)
	end,
}
