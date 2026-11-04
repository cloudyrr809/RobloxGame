--!strict
-- Строит модельку предмета: форма по виду, вид по редкости (цвет, блеск, частицы).
local Config = require(script.Parent.Config)

local ItemVisual = {}

local function newPart(className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function shapeParts(shape: string): { BasePart }
	local parts: { BasePart } = {}
	if shape == "Ball" then
		local p = newPart() :: Part
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * 1.7
		table.insert(parts, p)
	elseif shape == "Block" then
		local p = newPart()
		p.Size = Vector3.one * 1.4
		table.insert(parts, p)
	elseif shape == "Disc" then
		local p = newPart() :: Part
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.7, 1.9, 1.9)
		table.insert(parts, p)
	elseif shape == "Wedge" then
		local p = newPart("WedgePart")
		p.Size = Vector3.new(1.4, 1.5, 1.7)
		table.insert(parts, p)
	elseif shape == "Corner" then
		local p = newPart("CornerWedgePart")
		p.Size = Vector3.new(1.6, 1.6, 1.6)
		table.insert(parts, p)
	elseif shape == "Ring" then
		local n = 10
		for i = 1, n do
			local a = (i / n) * math.pi * 2
			local p = newPart()
			p.Size = Vector3.new(0.55, 0.55, 0.75)
			p.CFrame = CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -1)
			table.insert(parts, p)
		end
	elseif shape == "Prism" then
		local p = newPart()
		p.Size = Vector3.new(1.1, 1.1, 1.1)
		p.CFrame = CFrame.Angles(math.rad(45), 0, math.rad(45))
		local tall = newPart()
		tall.Size = Vector3.new(0.7, 2.3, 0.7)
		tall.CFrame = CFrame.Angles(0, math.rad(45), 0)
		table.insert(parts, p)
		table.insert(parts, tall)
	elseif shape == "Star" then
		for i = 0, 2 do
			local p = newPart()
			p.Size = Vector3.new(0.45, 2.3, 0.45)
			p.CFrame = CFrame.Angles(0, 0, math.rad(i * 60))
			table.insert(parts, p)
		end
		local core = newPart() :: Part
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.one * 0.9
		table.insert(parts, core)
	else
		local p = newPart()
		p.Size = Vector3.one
		table.insert(parts, p)
	end
	return parts
end

local function sparkles(parent: BasePart, color: Color3, rate: number, size: number)
	local att = Instance.new("Attachment")
	att.Parent = parent
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.5, 1)
	pe.Rate = rate
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = att
end

-- withEffects = false для витрины (ViewportFrame не рисует частицы и свет)
function ItemVisual.make(itemId: string, rarity: Config.Rarity, withEffects: boolean): Model
	local kind = Config.ItemById[itemId]
	local model = Instance.new("Model")
	model.Name = itemId
	local parts = shapeParts(kind.shape)
	local root = newPart()
	root.Name = "Root"
	root.Transparency = 1
	root.Size = Vector3.one * 0.2
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root
	local scale = 1.5 * (if rarity == "Epic" then 1.3 elseif rarity == "Rare" then 1.12 else 1)
	for _, p in parts do
		p.Size *= scale
		p.CFrame = CFrame.new(p.CFrame.Position * scale) * p.CFrame.Rotation
		p.Color = kind.color
		if rarity == "Common" then
			p.Material = Enum.Material.SmoothPlastic
		elseif rarity == "Rare" then
			p.Material = Enum.Material.Glass
			p.Reflectance = 0.25
			p.Color = kind.color:Lerp(Color3.new(1, 1, 1), 0.15)
		else
			p.Material = Enum.Material.Neon
		end
		p.Parent = model
	end
	if withEffects and rarity ~= "Common" then
		local info = Config.RarityInfo[rarity]
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 1
		hl.OutlineColor = info.color
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
		local light = Instance.new("PointLight")
		light.Color = info.color
		light.Range = if rarity == "Epic" then 14 else 9
		light.Brightness = if rarity == "Epic" then 4 else 2
		light.Parent = root
		sparkles(root, info.color, if rarity == "Epic" then 40 else 14, if rarity == "Epic" then 0.7 else 0.45)
	end
	return model
end

return ItemVisual
