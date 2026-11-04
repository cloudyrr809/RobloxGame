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
	local scale = 1.5 * (if rarity == "Legendary" then 1.45 elseif rarity == "Epic" then 1.3 elseif rarity == "Rare" then 1.12 else 1)
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
		elseif rarity == "Epic" then
			p.Material = Enum.Material.Neon
		else
			p.Material = Enum.Material.Neon
			p.Color = kind.color:Lerp(Config.RarityInfo.Legendary.color, 0.55)
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
		local big = rarity == "Epic" or rarity == "Legendary"
		light.Range = if rarity == "Legendary" then 20 elseif big then 14 else 9
		light.Brightness = if rarity == "Legendary" then 6 elseif big then 4 else 2
		light.Parent = root
		sparkles(root, info.color, if rarity == "Legendary" then 70 elseif big then 40 else 14, if big then 0.7 else 0.45)
	end
	return model
end

-- Ядро из кристалла: шар цвета зоны, размер и блеск по виду кристалла
function ItemVisual.core(zone: number, kind: Config.CrystalKind, withEffects: boolean): Model
	local info = Config.Crystals[kind]
	local color = Config.ZoneColors[zone]
	local model = Instance.new("Model")
	model.Name = "Core"
	local shell = newPart() :: Part
	shell.Name = "Shell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.one * info.coreSize
	shell.Material = Enum.Material.Glass
	shell.Transparency = 0.35
	shell.Reflectance = 0.2
	shell.Color = if kind == "Shining" then color:Lerp(Color3.new(1, 1, 1), 0.5) else color
	shell.Parent = model
	local heart = newPart() :: Part
	heart.Name = "Heart"
	heart.Shape = Enum.PartType.Ball
	heart.Size = Vector3.one * info.coreSize * 0.55
	heart.Material = Enum.Material.Neon
	heart.Color = shell.Color
	heart.Parent = model
	-- грани-осколки вокруг, чтобы читалось как «кристаллическое»
	for i = 1, (if kind == "Small" then 3 elseif kind == "Big" then 5 else 6) do
		local a = i * 2.4
		local shard = newPart()
		shard.Name = "Facet"
		shard.Size = Vector3.new(0.35, info.coreSize * 0.5, 0.35)
		shard.CFrame = CFrame.Angles(a, a * 1.7, a * 0.6) * CFrame.new(0, info.coreSize * 0.42, 0)
		shard.Material = Enum.Material.Neon
		shard.Color = shell.Color:Lerp(Color3.new(1, 1, 1), 0.4)
		shard.Parent = model
	end
	model.PrimaryPart = shell
	if withEffects then
		local light = Instance.new("PointLight")
		light.Color = shell.Color
		light.Range = 10 + info.coreSize * 2
		light.Brightness = if kind == "Shining" then 4 else 2
		light.Parent = heart
		sparkles(heart, shell.Color, if kind == "Shining" then 30 else 10, 0.4)
	end
	return model
end

return ItemVisual
