-- StrangeRadio: the old radio crackles. Broken: funny static. Fixed: a real hint about SUNNY's location.

local BROKEN_LINES = {
	"*kssh* ...please return your library books... *kssh*",
	"*bzzt* ...you're listening to SUNNY FM. All smiles. All night... *bzzt*",
	"*kssh* ...the tour... is not... over... *kssh*",
	"*bzzt* ...today's forecast: dark, with a chance of hugs... *bzzt*",
}

return {
	Id = "StrangeRadio",
	run = function(ctx)
		local world = ctx.World
		local radioLight = world.RadioLight
		local originalColor = radioLight.Color
		ctx.Trove:Add(function()
			ctx.Services.ObjectiveService.refreshRadio()
		end)

		local text
		if ctx.Services.ObjectiveService.isRadioFixed() then
			text = "RANGER (static): ...SUNNY was last seen near " .. ctx.Services.SunnyService.nearestLandmarkName() .. ". Stay in the light!"
		else
			text = BROKEN_LINES[ctx.Rng:NextInteger(1, #BROKEN_LINES)]
		end
		ctx.notifyAll("RADIO: " .. text, "radio")
		ctx.playSound("RadioStatic", world.Radio.Position, 3)

		local on = false
		ctx.every(0.3, function()
			on = not on
			if on then
				radioLight.Color = Color3.fromRGB(255, 240, 120)
			else
				radioLight.Color = originalColor
			end
			return true
		end)
	end,
}
