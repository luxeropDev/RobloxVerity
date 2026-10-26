-- SunnyModel: builds SUNNY, an original floating forest-guide robot, from primitive parts.
-- Silhouette: round yellow body, ring of 8 petals, antenna with a blinking tip, tall oval eyes, crescent smile.
-- Movement is physics-driven (AlignPosition/AlignOrientation) so it replicates smoothly to clients.

local SunnyModel = {}

local YELLOW = Color3.fromRGB(255, 214, 64)
local PETAL_DAY = Color3.fromRGB(255, 150, 40)
local PETAL_NIGHT = Color3.fromRGB(150, 80, 40)
local FACE_DAY = Color3.fromRGB(30, 25, 20)
local FACE_NIGHT = Color3.fromRGB(110, 255, 230)
local FACE_CHASE = Color3.fromRGB(255, 120, 200)

local BODY_RADIUS = 2.5

local function weldedPart(m: Model, root: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = m
	return p
end

local function ellipsoid(p: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

function SunnyModel.build(parent: Instance, position: Vector3)
	local m = Instance.new("Model")
	m.Name = "SUNNY"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(2, 2, 2)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.new(position)
	root.Parent = m
	m.PrimaryPart = root

	local body = weldedPart(m, root, "Body", Vector3.new(BODY_RADIUS * 2, BODY_RADIUS * 2, BODY_RADIUS * 2), CFrame.new(), YELLOW, Enum.Material.SmoothPlastic, Enum.PartType.Ball)

	-- Petal ring in the face plane (model faces -Z).
	local petals = {}
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2
		local offset = CFrame.new(math.cos(a) * 3.3, math.sin(a) * 3.3, 0.4) * CFrame.Angles(0, 0, a - math.pi / 2)
		local petal = weldedPart(m, root, "Petal" .. i, Vector3.new(1.3, 1.9, 0.5), offset, PETAL_DAY, Enum.Material.SmoothPlastic)
		table.insert(petals, petal)
	end

	-- Eyes: tall ovals on the front surface.
	local eyes = {}
	for _, x in ipairs({ -0.85, 0.85 }) do
		local eye = weldedPart(m, root, "Eye", Vector3.new(0.6, 1.15, 0.4), CFrame.new(x, 0.55, -BODY_RADIUS + 0.12), FACE_DAY, Enum.Material.SmoothPlastic)
		ellipsoid(eye)
		table.insert(eyes, eye)
	end

	-- Crescent smile: small segments along an arc that follows the sphere surface.
	local smile = {}
	local segments = 9
	for i = 0, segments - 1 do
		local t = math.rad(200 + (140 / (segments - 1)) * i)
		local x = math.cos(t) * 1.45
		local y = -0.25 + math.sin(t) * 0.95
		local zSq = BODY_RADIUS * BODY_RADIUS - x * x - y * y
		local z = -math.sqrt(math.max(0.05, zSq)) + 0.08
		local seg = weldedPart(m, root, "Smile" .. i, Vector3.new(0.42, 0.26, 0.2), CFrame.new(x, y, z) * CFrame.Angles(0, 0, t + math.pi / 2), FACE_DAY, Enum.Material.SmoothPlastic)
		table.insert(smile, seg)
	end

	-- Antenna with blinking tip.
	weldedPart(m, root, "Antenna", Vector3.new(0.18, 1.8, 0.18), CFrame.new(0, BODY_RADIUS + 0.8, 0), Color3.fromRGB(90, 90, 100), Enum.Material.Metal)
	local tip = weldedPart(m, root, "AntennaTip", Vector3.new(0.55, 0.55, 0.55), CFrame.new(0, BODY_RADIUS + 1.8, 0), Color3.fromRGB(255, 80, 80), Enum.Material.Neon, Enum.PartType.Ball)

	-- Name plate under the body.
	local plate = weldedPart(m, root, "NamePlate", Vector3.new(2.6, 0.6, 0.15), CFrame.new(0, -BODY_RADIUS - 0.2, -1.2) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(240, 240, 240), Enum.Material.Metal)
	local plateGui = Instance.new("SurfaceGui")
	plateGui.Face = Enum.NormalId.Front
	plateGui.CanvasSize = Vector2.new(260, 60)
	local plateLabel = Instance.new("TextLabel")
	plateLabel.Size = UDim2.fromScale(1, 1)
	plateLabel.BackgroundTransparency = 1
	plateLabel.TextScaled = true
	plateLabel.Font = Enum.Font.GothamBold
	plateLabel.TextColor3 = Color3.fromRGB(40, 40, 60)
	plateLabel.Text = "SUN-E v2.3 FOREST GUIDE"
	plateLabel.Parent = plateGui
	plateGui.Parent = plate

	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Range = 14
	light.Brightness = 1.2
	light.Color = Color3.fromRGB(255, 220, 140)
	light.Shadows = false
	light.Parent = body

	-- Speech bubble
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Speech"
	billboard.Size = UDim2.fromOffset(260, 80)
	billboard.StudsOffset = Vector3.new(0, 5.5, 0)
	billboard.MaxDistance = 110
	billboard.LightInfluence = 0
	billboard.Enabled = false
	local bubble = Instance.new("TextLabel")
	bubble.Name = "Text"
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.BackgroundColor3 = Color3.fromRGB(255, 250, 225)
	bubble.BackgroundTransparency = 0.1
	bubble.TextColor3 = Color3.fromRGB(60, 40, 20)
	bubble.Font = Enum.Font.FredokaOne
	bubble.TextScaled = true
	bubble.TextWrapped = true
	bubble.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bubble
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = bubble
	bubble.Parent = billboard
	billboard.Parent = body

	-- Physics movers
	local attachment = Instance.new("Attachment")
	attachment.Name = "MoverAttachment"
	attachment.Parent = root
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxForce = 1e6
	align.MaxVelocity = 12
	align.Responsiveness = 30
	align.Position = position
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = attachment
	orient.MaxTorque = 1e6
	orient.Responsiveness = 18
	orient.CFrame = CFrame.new()
	orient.Parent = root

	m.Parent = parent
	pcall(function()
		root:SetNetworkOwner(nil) -- server owns SUNNY's physics
	end)

	return {
		Model = m,
		Root = root,
		Body = body,
		Eyes = eyes,
		Smile = smile,
		Petals = petals,
		Tip = tip,
		Light = light,
		Billboard = billboard,
		SpeechLabel = bubble,
		Align = align,
		Orient = orient,
	}
end

-- mood: "Day" | "Night" | "Chase" | "Off"
function SunnyModel.setMood(h, mood: string)
	local face, faceMat, petalColor, lightColor, lightRange = FACE_DAY, Enum.Material.SmoothPlastic, PETAL_DAY, Color3.fromRGB(255, 220, 140), 14
	if mood == "Night" then
		face, faceMat, petalColor, lightColor, lightRange = FACE_NIGHT, Enum.Material.Neon, PETAL_NIGHT, Color3.fromRGB(110, 255, 230), 16
	elseif mood == "Chase" then
		face, faceMat, petalColor, lightColor, lightRange = FACE_CHASE, Enum.Material.Neon, PETAL_NIGHT, Color3.fromRGB(255, 140, 210), 20
	elseif mood == "Off" then
		face, faceMat, petalColor, lightColor, lightRange = Color3.fromRGB(80, 80, 80), Enum.Material.SmoothPlastic, Color3.fromRGB(120, 110, 90), Color3.fromRGB(0, 0, 0), 0
	end
	for _, eye in ipairs(h.Eyes) do
		eye.Color = face
		eye.Material = faceMat
	end
	for _, seg in ipairs(h.Smile) do
		seg.Color = face
		seg.Material = faceMat
	end
	for _, petal in ipairs(h.Petals) do
		petal.Color = petalColor
	end
	h.Light.Color = lightColor
	h.Light.Range = lightRange
	h.Light.Enabled = lightRange > 0
end

function SunnyModel.setSpeech(h, text: string?)
	if text and text ~= "" then
		h.SpeechLabel.Text = text
		h.Billboard.Enabled = true
	else
		h.Billboard.Enabled = false
		h.SpeechLabel.Text = ""
	end
end

-- Teleports SUNNY and resets the movers so it does not fly back.
function SunnyModel.teleport(h, position: Vector3)
	h.Model:PivotTo(CFrame.new(position))
	h.Align.Position = position
	h.Root.AssemblyLinearVelocity = Vector3.zero
end

return SunnyModel
