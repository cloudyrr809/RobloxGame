--!nocheck
-- Строит карту в Workspace.Map. Запуск: через Roblox Studio MCP (execute_luau, Edit).
-- Повторный запуск удаляет старую карту и строит заново.
-- Нужны синхронизированные Rojo модули ReplicatedStorage.Shared (Turtle, Coasters, Config).
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- require кэширует модули в Studio: берём свежие копии
local function fresh(name)
	local folder = Instance.new("Folder")
	for _, m in ReplicatedStorage.Shared:GetChildren() do
		m:Clone().Parent = folder
	end
	local mod = require(folder[name])
	return mod, folder
end
local Turtle = fresh("Turtle")
local Coasters = fresh("Coasters")
local Config = fresh("Config")

local ZONE_COLORS = Config.ZoneColors
local WHITE = Color3.fromRGB(240, 238, 246)
local STONE = Color3.fromRGB(70, 62, 100)
local DARK = Color3.fromRGB(55, 46, 80)

local old = workspace:FindFirstChild("Map")
if old then
	old:Destroy()
end
local bp = workspace:FindFirstChild("Baseplate")
if bp then
	bp:Destroy()
end

local rng = Random.new(7)

local function part(props)
	local p = Instance.new(props.Class or "Part")
	props.Class = nil
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for _, k in { "Shape", "Size", "CFrame", "Position" } do
		if props[k] ~= nil then
			p[k] = props[k]
		end
	end
	for k, v in props do
		if k ~= "Parent" and k ~= "Shape" and k ~= "Size" and k ~= "CFrame" and k ~= "Position" then
			p[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

-- диск: top — высота верхней грани
local function disc(parent, name, radius, height, center, top, color, material, variant)
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(center.X, top - height / 2, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.Marble,
		MaterialVariant = variant or "",
		Parent = parent,
	})
end

local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

local function textLabel(text)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.4
	t.TextStrokeColor3 = Color3.fromRGB(90, 60, 140)
	return t
end

local function sign(parent, text, offsetY, w, h, maxDist)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Sign"
	bb.Size = UDim2.fromOffset(w or 240, h or 60)
	bb.StudsOffsetWorldSpace = Vector3.new(0, offsetY or 0, 0)
	bb.MaxDistance = maxDist or 110
	bb.LightInfluence = 0
	bb.Parent = parent
	local t = textLabel(text)
	t.Name = "Label"
	t.Parent = bb
	return bb, t
end

local function sparkles(parent, color, rate, size)
	local att = Instance.new("Attachment")
	att.Parent = parent
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(1, 1.8)
	pe.Rate = rate
	pe.Speed = NumberRange.new(1, 2.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Parent = att
	return pe
end

local function checkpoint(p, radius)
	CollectionService:AddTag(p, "Checkpoint")
	p:SetAttribute("Radius", radius)
end

-- ===== Освещение =====
Lighting.ClockTime = 15.2
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(120, 110, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 180)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.8
Lighting.GlobalShadows = true
local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
atm.Density = 0.28
atm.Offset = 0.15
atm.Color = Color3.fromRGB(230, 205, 255)
atm.Decay = Color3.fromRGB(150, 120, 210)
atm.Glare = 0.4
atm.Haze = 1.4
local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect", Lighting)
bloom.Intensity = 0.6
bloom.Size = 30
bloom.Threshold = 1.6
local cc = Lighting:FindFirstChild("RoblohColor") or Instance.new("ColorCorrectionEffect", Lighting)
cc.Name = "RoblohColor"
cc.Saturation = 0.12
cc.Contrast = 0.06
workspace.FallenPartsDestroyHeight = -200
-- карта маленькая (~4 тыс. деталей): грузим целиком, иначе клиент видит кристаллы и ворота по кускам
workspace.StreamingEnabled = false

local map = Instance.new("Folder")
map.Name = "Map"
map.Parent = workspace

-- ===== Дорожка по точкам «черепашки» =====
local function walkway(parent, samples, width, color, curbColor)
	local tint = WHITE:Lerp(color, 0.25)
	for i = 1, #samples - 1 do
		local a, b = samples[i], samples[i + 1]
		local mid = (a.Position + b.Position) / 2
		local len = (b.Position - a.Position).Magnitude
		local cf = CFrame.lookAt(mid, b.Position, a.UpVector)
		local c = if (i // 2) % 2 == 0 then tint else tint:Lerp(WHITE, 0.5)
		part({ Name = "Tile", Size = Vector3.new(width, 1.2, len + 0.9), CFrame = cf * CFrame.new(0, -0.6, 0), Color = c, Material = Enum.Material.CeramicTiles, MaterialVariant = "RoblohPath", Parent = parent })
		for _, s in { -1, 1 } do
			part({ Name = "Curb", Size = Vector3.new(0.8, 1.1, len + 0.9), CFrame = cf * CFrame.new(s * (width / 2 + 0.4), 0.1, 0), Color = curbColor or color, Material = Enum.Material.Neon, CanCollide = true, Parent = parent })
		end
		if i % 2 == 0 then
			part({ Name = "Under", Size = Vector3.new(width * 0.5, 1.6, len + 1), CFrame = cf * CFrame.new(0, -1.9, 0), Color = DARK, Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = parent })
		end
	end
end

-- остров-диск с подложкой
local function island(parent, name, center, top, radius, color)
	local m = Instance.new("Model")
	m.Name = name
	local floor = disc(m, "Floor", radius, 3, center, top, WHITE:Lerp(color, 0.18), Enum.Material.Marble, "RoblohFloor")
	disc(m, "Rim", radius + 0.8, 2.4, center, top - 0.5, color, Enum.Material.Neon)
	disc(m, "Under", radius * 0.8, 6, center, top - 3, STONE, Enum.Material.Slate, "RoblohStone")
	disc(m, "UnderTip", radius * 0.45, 7, center, top - 9, DARK, Enum.Material.Slate, "RoblohStone")
	m.Parent = parent
	return m, floor
end

-- прыжковая площадка: полёт по дуге в target (клиент двигает персонажа сам)
local function jumpPad(parent, pos, target, height, duration, color)
	local pad = disc(parent, "JumpPad", 2.6, 0.6, pos, pos.Y + 0.35, color, Enum.Material.Neon)
	pad.CanCollide = false
	CollectionService:AddTag(pad, "JumpPad")
	pad:SetAttribute("Target", target)
	pad:SetAttribute("Height", height)
	pad:SetAttribute("Duration", duration)
	disc(parent, "PadBase", 3.2, 0.5, pos, pos.Y + 0.1, DARK, Enum.Material.Slate, "RoblohStone")
	local arrow = part({ Name = "PadArrow", Class = "WedgePart", Size = Vector3.new(1.6, 0.8, 1.6), CFrame = CFrame.new(pos + Vector3.new(0, 1.4, 0), pos + Vector3.new(0, 1.4, 0) + (Vector3.new(target.X, pos.Y, target.Z) - pos).Unit) * CFrame.Angles(math.rad(-90), 0, 0), Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Parent = parent })
	CollectionService:AddTag(arrow, "Floaty")
	light(pad, color, 10, 1.5)
	sparkles(pad, color, 6, 0.4)
	return pad
end

-- тонкий мостик-балка между точками
local function beam(parent, a, b, width, color)
	local len = (b - a).Magnitude
	part({ Name = "Beam", Size = Vector3.new(width, 1, len + 1), CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, -0.5, 0), Color = WHITE:Lerp(color, 0.3), Material = Enum.Material.CeramicTiles, MaterialVariant = "RoblohPath", Parent = parent })
	for _, s in { -1, 1 } do
		part({ Name = "Curb", Size = Vector3.new(0.5, 0.8, len + 1), CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.new(s * (width / 2 + 0.25), 0, 0), Color = color, Material = Enum.Material.Neon, Parent = parent })
	end
end

-- ворота зоны поперёк пути: cf — центр низа, LookVector — вдоль пути
local function gate(parent, zone, cf, width)
	local color = ZONE_COLORS[zone]
	local price = Config.GatePrices[zone]
	local g = Instance.new("Model")
	g.Name = "Gate" .. zone
	g:SetAttribute("Zone", zone)
	for _, s in { -1, 1 } do
		part({ Name = "Pillar", Size = Vector3.new(3, 16, 3), CFrame = cf * CFrame.new(s * (width / 2 + 1.5), 8, 0), Color = STONE, Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = g })
		local cap = part({ Name = "Cap", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = cf * CFrame.new(s * (width / 2 + 1.5), 17.6, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = g })
		light(cap, color, 16, 1.5)
	end
	part({ Name = "Lintel", Size = Vector3.new(width + 6, 2, 3), CFrame = cf * CFrame.new(0, 16.5, 0), Color = STONE, Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = g })
	local wall = part({ Name = "Barrier", Size = Vector3.new(width + 2, 15.5, 1), CFrame = cf * CFrame.new(0, 7.75, 0), Color = color, Material = Enum.Material.Glass, Transparency = 0.55, Parent = g })
	part({ Name = "BarrierFx", Size = Vector3.new(width + 2, 15.5, 1.4), CFrame = cf * CFrame.new(0, 7.75, 0), Color = color, Material = Enum.Material.ForceField, CanCollide = false, CanQuery = false, CanTouch = false, Parent = g })
	local bb = sign(wall, Config.ZoneNames[zone] .. " зона\n" .. price .. " монет", 0, 300, 90, 140)
	bb.Name = "PriceSign"
	local gp = Instance.new("ProximityPrompt")
	gp.Name = "Buy"
	gp.ActionText = "Открыть за " .. price
	gp.ObjectText = Config.ZoneNames[zone] .. " зона"
	gp.HoldDuration = 0.3
	gp.MaxActivationDistance = 14
	gp.RequiresLineOfSight = false
	gp.Parent = wall
	g.Parent = parent
	CollectionService:AddTag(g, "Gate")
	return g
end

-- ===== Кристаллы =====
local assets = ServerStorage:FindFirstChild("MapAssets")
local HEIGHT = { Small = 6.5, Big = 11, Shining = 8.5 }

local function crystal(parent, zone, kind, pos, name)
	local color = ZONE_COLORS[zone]
	local info = Config.Crystals[kind]
	local m = Instance.new("Model")
	m.Name = name or (kind .. "Crystal")
	m:SetAttribute("Zone", zone)
	m:SetAttribute("Kind", kind)
	local h = HEIGHT[kind]
	local tint = if kind == "Shining" then color:Lerp(Color3.new(1, 1, 1), 0.55) else color
	local body
	local tpl = assets and assets:FindFirstChild("CrystalZone" .. zone)
	if tpl then
		body = tpl:Clone()
		body.Size *= h / body.Size.Y
		body.Anchored = true
		body.CollisionFidelity = Enum.CollisionFidelity.Box
		body.CFrame = CFrame.new(pos.X, pos.Y + body.Size.Y / 2 - 0.1, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		if kind == "Shining" then
			body.Color = tint
		end
	else
		body = part({ Size = Vector3.new(h * 0.5, h, h * 0.5), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = tint, Material = Enum.Material.Glass, Transparency = 0.25 })
	end
	body.Name = "Body"
	body.Parent = m
	body:SetAttribute("BaseSize", body.Size)
	body:SetAttribute("BaseCFrame", body.CFrame)
	local core = part({ Name = "Core", Size = Vector3.new(h * 0.18, h * 0.55, h * 0.18), CFrame = CFrame.new(pos + Vector3.new(0, h * 0.45, 0)), Color = tint, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Transparency = 0.2, Parent = m })
	light(core, tint, if kind == "Big" then 24 else 18, if kind == "Shining" then 3.5 else 2)
	sparkles(core, tint, if kind == "Shining" then 14 else 4, if kind == "Big" then 0.7 else 0.5)
	local haloSize = if kind == "Big" then 15 else 10
	local halo = part({ Name = "Halo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, haloSize, haloSize), CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = tint, Material = Enum.Material.ForceField, CanCollide = false, CanQuery = false, Parent = m })
	halo.Transparency = 0.2
	if kind == "Shining" then
		-- столб света в небо, чтобы искать издалека
		local a0 = Instance.new("Attachment")
		a0.Name = "BeamBottom"
		a0.Parent = core
		local top = part({ Name = "BeamTop", Size = Vector3.one, CFrame = CFrame.new(pos + Vector3.new(0, 160, 0)), Transparency = 1, CanCollide = false, CanQuery = false, Parent = m })
		local a1 = Instance.new("Attachment")
		a1.Parent = top
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Width0 = 3
		b.Width1 = 7
		b.LightEmission = 1
		b.FaceCamera = true
		b.Color = ColorSequence.new(tint)
		b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		b.Parent = core
	end
	local promptPart = part({ Name = "PromptPart", Size = Vector3.one, CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0)), Transparency = 1, CanCollide = false, CanQuery = false, Parent = m })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Mine"
	prompt.ActionText = "Добыть"
	prompt.ObjectText = info.name
	prompt.HoldDuration = Config.mineTime(zone, kind, 0)
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart
	m.PrimaryPart = body
	m.Parent = parent
	CollectionService:AddTag(m, "Crystal")
	if kind == "Shining" then
		CollectionService:AddTag(m, "Shining")
	end
	return m
end

-- места, где может появиться сияющий кристалл
local function shineSpot(folder, pos)
	local p = part({ Name = "Spot", Size = Vector3.one, Position = pos, Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, Parent = folder })
	return p
end

-- маленькая парящая скала-площадка
local function rock(parent, pos, radius, color)
	local m = Instance.new("Model")
	m.Name = "Rock"
	disc(m, "Floor", radius, 2, pos, pos.Y, WHITE:Lerp(color, 0.3), Enum.Material.Marble, "RoblohFloor")
	disc(m, "Rim", radius + 0.5, 1.6, pos, pos.Y - 0.4, color, Enum.Material.Neon)
	part({ Name = "Under", Class = "WedgePart", Size = Vector3.new(radius * 1.4, radius * 1.5, radius * 1.4), CFrame = CFrame.new(pos - Vector3.new(0, radius * 0.75 + 1, 0)) * CFrame.Angles(math.rad(180), math.rad(45), 0), Color = STONE, Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = m })
	m.Parent = parent
	return m
end

-- станция горок на старте
local function station(parent, coasterId, from, to, zone)
	local color = ZONE_COLORS[zone]
	local m = Instance.new("Model")
	m.Name = "Station_" .. coasterId
	m:SetAttribute("Track", coasterId)
	local dir = (to - from)
	local len = dir.Magnitude
	local cf = CFrame.lookAt((from + to) / 2, to)
	part({ Name = "Deck", Size = Vector3.new(12, 1.5, len), CFrame = cf * CFrame.new(0, -1.6, 0), Color = WHITE:Lerp(color, 0.3), Material = Enum.Material.Marble, MaterialVariant = "RoblohFloor", Parent = m })
	for _, s in { -1, 1 } do
		part({ Name = "Post", Size = Vector3.new(1, 9, 1), CFrame = cf * CFrame.new(s * 5.5, 3, len / 2 - 1), Color = STONE, Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = m })
	end
	local roof = part({ Name = "Roof", Size = Vector3.new(13, 0.8, 6), CFrame = cf * CFrame.new(0, 7.8, len / 2 - 2), Color = color, Material = Enum.Material.Neon, Parent = m })
	sign(roof, "ДОМОЙ НА ГОРКАХ\n" .. Coasters.ById[coasterId].name, 3, 280, 70)
	local promptPart = part({ Name = "PromptPart", Size = Vector3.one, CFrame = cf * CFrame.new(0, 2.5, len / 2 - 2), Transparency = 1, CanCollide = false, CanQuery = false, Parent = m })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Ride"
	prompt.ActionText = "Прокатиться"
	prompt.ObjectText = "Домой"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart
	m.Parent = parent
	CollectionService:AddTag(m, "CoasterStation")
	return m
end

-- рельсы горок
local function rails(parent, track, color)
	local s = track.samples
	local f = Instance.new("Folder")
	f.Name = "Rails"
	f.Parent = parent
	local invertedRun = {}
	for i = 1, #s - 1 do
		local a, b = s[i], s[i + 1]
		local mid = (a.Position + b.Position) / 2
		local len = (b.Position - a.Position).Magnitude
		local cf = CFrame.lookAt(mid, b.Position, a.UpVector:Lerp(b.UpVector, 0.5))
		for _, side in { -1, 1 } do
			part({ Name = "Rail", Size = Vector3.new(0.45, 0.45, len + 0.3), CFrame = cf * CFrame.new(side * 1.5, 0, 0), Color = color, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false, Parent = f })
		end
		part({ Name = "Spine", Size = Vector3.new(0.8, 0.8, len + 0.3), CFrame = cf * CFrame.new(0, -0.7, 0), Color = DARK, Material = Enum.Material.Metal, CanCollide = false, CanQuery = false, Parent = f })
		if i % 2 == 0 then
			part({ Name = "Tie", Size = Vector3.new(3.4, 0.3, 0.5), CFrame = cf * CFrame.new(0, -0.35, 0), Color = STONE, Material = Enum.Material.Metal, CanCollide = false, CanQuery = false, Parent = f })
		end
		-- участки «вверх ногами» на ровном месте — под потолок
		local inverted = a.UpVector.Y < -0.9 and math.abs(a.LookVector.Y) < 0.2
		if inverted then
			table.insert(invertedRun, a.Position)
		end
		if (not inverted or i == #s - 1) and #invertedRun >= 8 then
			local p0, p1 = invertedRun[1], invertedRun[#invertedRun]
			local mid2 = (p0 + p1) / 2
			local l = (p1 - p0).Magnitude + 10
			local slab = part({ Name = "Ceiling", Size = Vector3.new(26, 2.5, l), CFrame = CFrame.lookAt(mid2 + Vector3.new(0, 2.2, 0), p1 + Vector3.new(0, 2.2, 0)), Color = WHITE:Lerp(color, 0.2), Material = Enum.Material.Marble, MaterialVariant = "RoblohFloor", Parent = f })
			part({ Name = "CeilingGlow", Size = Vector3.new(27, 1.2, l + 1), CFrame = slab.CFrame * CFrame.new(0, 0.4, 0), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = f })
			for _, z in { -0.5, 0.5 } do
				part({ Name = "Pylon", Size = Vector3.new(2, 14, 2), CFrame = slab.CFrame * CFrame.new(12, 8, z * (l - 4)), Color = STONE, Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = f })
				part({ Name = "Pylon", Size = Vector3.new(2, 14, 2), CFrame = slab.CFrame * CFrame.new(-12, 8, z * (l - 4)), Color = STONE, Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = f })
			end
		end
		if not inverted then
			invertedRun = {}
		end
		if i % 60 == 0 then
			task.wait()
		end
	end
	-- платформа прибытия на базе
	local last = s[#s]
	local endDeck = part({ Name = "ArrivalDeck", Size = Vector3.new(10, 1, 18), CFrame = CFrame.new(last.Position) * last.Rotation * CFrame.new(0, -1.6, 6), Color = WHITE:Lerp(color, 0.3), Material = Enum.Material.Marble, MaterialVariant = "RoblohFloor", Parent = f })
	endDeck.CanCollide = false
end

-- ===== База =====
local base = Instance.new("Model")
base.Name = "Base"
base.Parent = map
local BASE_R = 45
local floor = disc(base, "Floor", BASE_R, 4, Vector3.zero, 0, Color3.fromRGB(245, 240, 250), Enum.Material.Marble, "RoblohFloor")
disc(base, "Rim", BASE_R + 1.2, 3, Vector3.zero, -0.3, Color3.fromRGB(200, 175, 255), Enum.Material.Neon)
disc(base, "Under", BASE_R - 4, 10, Vector3.zero, -4, STONE, Enum.Material.Slate, "RoblohStone")
disc(base, "UnderTip", BASE_R - 16, 10, Vector3.zero, -13, DARK, Enum.Material.Slate, "RoblohStone")
CollectionService:AddTag(floor, "BaseFloor")
floor:SetAttribute("Radius", BASE_R)
checkpoint(floor, BASE_R)

-- алтарь раскола
local altar = Instance.new("Model")
altar.Name = "Altar"
local ALTAR = Vector3.new(0, 0, 8)
disc(altar, "Step", 9, 0.8, ALTAR, 0.8, STONE, Enum.Material.Slate, "RoblohStone")
disc(altar, "StepGlow", 9.4, 0.5, ALTAR, 0.4, Color3.fromRGB(255, 210, 110), Enum.Material.Neon)
disc(altar, "Pillar", 3.2, 3.2, ALTAR, 4, Color3.fromRGB(85, 75, 120), Enum.Material.Slate, "RoblohStone")
local bowl = disc(altar, "Bowl", 4.4, 0.8, ALTAR, 4.6, Color3.fromRGB(85, 75, 120), Enum.Material.Slate, "RoblohStone")
disc(altar, "BowlRim", 4.7, 0.4, ALTAR, 4.4, Color3.fromRGB(255, 210, 110), Enum.Material.Neon)
bowl:SetAttribute("CoreHeight", 9)
CollectionService:AddTag(bowl, "Altar")
light(bowl, Color3.fromRGB(255, 215, 120), 14, 0.8)
for i = 1, 4 do
	local a = i * math.pi / 2 + math.pi / 4
	local shard = part({ Name = "Prong", Size = Vector3.new(0.9, 5, 0.9), CFrame = CFrame.new(ALTAR + Vector3.new(math.cos(a) * 3.6, 6.2, math.sin(a) * 3.6)) * CFrame.Angles(math.sin(a) * 0.35, 0, -math.cos(a) * 0.35), Color = Color3.fromRGB(255, 215, 130), Material = Enum.Material.Glass, Transparency = 0.15, CanCollide = false, Parent = altar })
	shard.CastShadow = false
end
local altarPromptPart = part({ Name = "PromptPart", Size = Vector3.one, Position = ALTAR + Vector3.new(0, 4, 0), Transparency = 1, CanCollide = false, CanQuery = false, Parent = altar })
local ap = Instance.new("ProximityPrompt")
ap.Name = "Crack"
ap.ActionText = "Расколоть ядро"
ap.ObjectText = "Алтарь"
ap.HoldDuration = 0
ap.MaxActivationDistance = 12
ap.RequiresLineOfSight = false
ap.Enabled = true -- клиент скрывает, пока нет ядра
ap.Parent = altarPromptPart
sign(altarPromptPart, "АЛТАРЬ\nнеси сюда ядро", 9, 240, 64, 140)
altar.Parent = base

-- спавн
local spawn = workspace:FindFirstChildOfClass("SpawnLocation") or Instance.new("SpawnLocation")
spawn.Name = "Spawn"
spawn.Anchored = true
spawn.Size = Vector3.new(8, 0.4, 8)
spawn.CFrame = CFrame.new(0, 0.2, -22)
spawn.Material = Enum.Material.Neon
spawn.Color = Color3.fromRGB(200, 175, 255)
spawn.Transparency = 0.3
spawn.CanCollide = false
spawn.Duration = 0
for _, d in spawn:GetChildren() do
	if d:IsA("Decal") then
		d:Destroy()
	end
end
spawn.Parent = base

-- станции: улучшения и коллекция
local function stationPad(name, pos, color, text)
	local m = Instance.new("Model")
	m.Name = name
	disc(m, "Pad", 6, 1, pos, 1, Color3.fromRGB(80, 70, 110), Enum.Material.Slate, "RoblohStone")
	disc(m, "PadGlow", 6.4, 0.6, pos, 0.6, color, Enum.Material.Neon)
	local body = part({ Name = "Monolith", Size = Vector3.new(3, 7, 3), CFrame = CFrame.new(pos + Vector3.new(0, 4.5, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = STONE, Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = m })
	local core = part({ Name = "Core", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(pos + Vector3.new(0, 10, 0)) * CFrame.Angles(math.rad(45), math.rad(45), 0), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = m })
	CollectionService:AddTag(core, "Spin")
	light(core, color, 16, 2)
	sign(core, text, 3, 200, 44, 90)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Open"
	prompt.ActionText = text
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	m.Parent = base
	CollectionService:AddTag(m, name)
end
stationPad("UpgradeStation", Vector3.new(-20, 0, -12), Color3.fromRGB(255, 205, 90), "Улучшения")
stationPad("CollectionStation", Vector3.new(20, 0, -12), Color3.fromRGB(120, 220, 255), "Коллекция")

-- ===== Разгонное кольцо вокруг базы =====
local ring = Instance.new("Folder")
ring.Name = "SpeedRing"
ring.Parent = map
local RING_R, RING_H, RING_N = 50, 16, 120
local function ringPos(th)
	return Vector3.new(RING_R * math.sin(th), RING_H + 3 * math.sin(3 * th), RING_R * math.cos(th))
end
local ringSamples = {}
for i = 0, RING_N do
	local th = i / RING_N * math.pi * 2
	local p = ringPos(th)
	local nextP = ringPos(th + 0.01)
	local roll = math.rad(16) * math.sin(4 * th)
	table.insert(ringSamples, CFrame.lookAt(p, nextP) * CFrame.Angles(0, 0, roll))
end
walkway(ring, ringSamples, 12, Color3.fromRGB(255, 120, 200), Color3.fromRGB(255, 150, 220))
for g = 1, Config.RingGateCount do
	local th = (g - 1) / Config.RingGateCount * math.pi * 2
	local p = ringPos(th)
	local cf = CFrame.lookAt(p, ringPos(th + 0.01))
	local arch = Instance.new("Model")
	arch.Name = "RingGate" .. g
	for _, s in { -1, 1 } do
		part({ Name = "Post", Size = Vector3.new(1, 10, 1), CFrame = cf * CFrame.new(s * 7, 5, 0), Color = Color3.fromRGB(255, 150, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = arch })
	end
	local top = part({ Name = "Top", Size = Vector3.new(15, 1, 1), CFrame = cf * CFrame.new(0, 10, 0), Color = Color3.fromRGB(255, 150, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = arch })
	local marker = part({ Name = "Marker", Size = Vector3.one, CFrame = cf * CFrame.new(0, 2, 0), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, Parent = arch })
	marker:SetAttribute("Index", g)
	CollectionService:AddTag(marker, "RingGate")
	if g == 1 then
		sign(top, "РАЗГОННОЕ КОЛЬЦО\nбеги круги — растёт скорость", 3, 320, 70, 160)
	end
	arch.Parent = ring
end
-- запрыгнуть на кольцо с базы
for _, side in { -1, 1 } do
	local th = side * math.rad(135)
	local target = ringPos(th) + Vector3.new(0, 0.3, 0)
	local from = Vector3.new(math.sin(th) * 30, 0, math.cos(th) * 30)
	jumpPad(base, from, target, 10, 1.1, Color3.fromRGB(255, 150, 220))
end
task.wait()

-- ===== Зона 1: Мятная — волны и острова =====
local z1 = Instance.new("Folder")
z1.Name = "Zone1"
z1.Parent = map
local c1 = ZONE_COLORS[1]
local t = Turtle.new(Vector3.new(0, 0, 44), 180, 3)
Turtle.wave(t, { len = 54, side = 10, bump = 2.5, bumps = 2, dy = 3, bankFactor = 2 })
walkway(z1, t.samples, 14, c1)
local _, i1floor = island(z1, "Island", Vector3.new(0, 0, 120), 3, 24, c1)
checkpoint(i1floor, 24)
crystal(z1, 1, "Small", Vector3.new(-12, 3, 108))
crystal(z1, 1, "Small", Vector3.new(12, 3, 112))
rock(z1, Vector3.new(16, 16, 140), 7, c1)
crystal(z1, 1, "Big", Vector3.new(16, 16, 140))
jumpPad(z1, Vector3.new(12, 3, 128), Vector3.new(14, 16.3, 136), 8, 0.9, c1)
local spots1 = Instance.new("Folder")
spots1.Name = "ShineSpots"
spots1.Parent = z1
rock(z1, Vector3.new(-34, 7, 70), 5, c1)
beam(z1, Vector3.new(-6, 1.8, 70), Vector3.new(-30, 7, 70), 4, c1)
shineSpot(spots1, Vector3.new(-34, 7, 70))
shineSpot(spots1, Vector3.new(-16, 3, 136))
rock(z1, Vector3.new(36, 12, 112), 5, c1)
jumpPad(z1, Vector3.new(18, 3, 124), Vector3.new(34, 12.3, 113), 7, 0.9, c1)
shineSpot(spots1, Vector3.new(37, 12, 112))
crystal(z1, 1, "Shining", Vector3.new(-34, 7, 70))
-- мост к башне и ворота
local tb = Turtle.new(Vector3.new(0, 3, 142), 180, 3)
Turtle.straight(tb, 32)
walkway(z1, tb.samples, 14, ZONE_COLORS[2])
gate(z1, 2, CFrame.new(0, 3, 147), 14)
task.wait()

-- ===== Зона 2: Небесная — башня-спираль =====
local z2 = Instance.new("Folder")
z2.Name = "Zone2"
z2.Parent = map
local c2 = ZONE_COLORS[2]
local TOWER = Vector3.new(-26, 0, 174)
local th = Turtle.new(Vector3.new(0, 3, 174), 180, 3)
Turtle.helix(th, 26, -450, 45, 8)
walkway(z2, th.samples, 12, c2)
disc(z2, "Column", 12, 46, TOWER, 46, STONE, Enum.Material.Slate, "RoblohStone")
disc(z2, "ColumnGlow", 12.4, 1.5, TOWER, 30, c2, Enum.Material.Neon)
disc(z2, "ColumnGlow2", 12.4, 1.5, TOWER, 15, c2, Enum.Material.Neon)
local _, topFloor = island(z2, "Top", TOWER, 48, 21, c2)
checkpoint(topFloor, 21)
-- балкон на середине спирали (270° — сторона к базе)
rock(z2, Vector3.new(-26, 30.2, 139), 6, c2)
crystal(z2, 2, "Small", Vector3.new(-26, 30.2, 139))
crystal(z2, 2, "Small", Vector3.new(-26, 48, 160))
crystal(z2, 2, "Big", Vector3.new(-14, 48, 186))
-- балкон к прыжку в Лиловую зону
local tbal = Turtle.new(Vector3.new(-6, 48, 174), -90, 3)
Turtle.straight(tbal, 18)
walkway(z2, tbal.samples, 12, ZONE_COLORS[3])
gate(z2, 3, CFrame.new(-1, 48, 174) * CFrame.Angles(0, math.rad(90), 0), 12)
jumpPad(z2, Vector3.new(9, 48, 174), Vector3.new(0, 31.3, 296), 30, 2.6, ZONE_COLORS[3])
-- шпиль
local spire = part({ Name = "Spire", Size = Vector3.new(4, 18, 4), CFrame = CFrame.new(TOWER + Vector3.new(0, 57, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = STONE, Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = z2 })
spire.CanCollide = true
rock(z2, TOWER + Vector3.new(0, 68, 0), 5, c2)
jumpPad(z2, TOWER + Vector3.new(-9, 48, 9), TOWER + Vector3.new(0, 68.3, 2), 8, 1.0, c2)
local spots2 = Instance.new("Folder")
spots2.Name = "ShineSpots"
spots2.Parent = z2
rock(z2, Vector3.new(-26, 12.2, 211), 5, c2)
shineSpot(spots2, Vector3.new(-26, 12.2, 212))
shineSpot(spots2, TOWER + Vector3.new(0, 68, 0))
rock(z2, Vector3.new(-62, 40, 150), 5, c2)
jumpPad(z2, Vector3.new(-40, 48, 162), Vector3.new(-60, 40.3, 151), 8, 1.0, c2)
shineSpot(spots2, Vector3.new(-62, 40, 150))
crystal(z2, 2, "Shining", Vector3.new(-26, 12.2, 212))
station(z2, "Sky", Vector3.new(-26, 49.5, 170), Vector3.new(-48, 49.5, 170), 2)
task.wait()

-- ===== Зона 3: Лиловая — скрученная лента и кольца =====
local z3 = Instance.new("Folder")
z3.Name = "Zone3"
z3.Parent = map
local c3 = ZONE_COLORS[3]
local _, i3a = island(z3, "Landing", Vector3.new(0, 0, 300), 31, 14, c3)
checkpoint(i3a, 14)
local tr = Turtle.new(Vector3.new(0, 31, 312), 180, 3)
Turtle.wave(tr, { len = 104, side = 16, bump = 3, bumps = 3, dy = 9, twist = 28, twists = 2, bankFactor = 2 })
walkway(z3, tr.samples, 12, c3)
-- кольца вокруг ленты
for _, k in { 0.18, 0.42, 0.66, 0.88 } do
	local cf = tr.samples[math.max(1, math.floor(#tr.samples * k))]
	for j = 1, 18 do
		local a = j / 18 * math.pi * 2
		local seg = part({ Name = "Hoop", Size = Vector3.new(1.2, 1.2, 4.2), CFrame = cf * CFrame.Angles(0, 0, a) * CFrame.new(0, 11, 0) * CFrame.Angles(0, math.rad(90), 0), Color = c3:Lerp(Color3.new(1, 1, 1), 0.2), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Parent = z3 })
		seg.CastShadow = false
	end
end
local _, i3b = island(z3, "Far", Vector3.new(0, 0, 436), 40, 20, c3)
checkpoint(i3b, 20)
crystal(z3, 3, "Small", Vector3.new(8, 31, 304))
crystal(z3, 3, "Small", Vector3.new(-12, 40, 428))
crystal(z3, 3, "Big", Vector3.new(-8, 40, 446))
local spots3 = Instance.new("Folder")
spots3.Name = "ShineSpots"
spots3.Parent = z3
rock(z3, Vector3.new(26, 34, 360), 5, c3)
beam(z3, Vector3.new(8, 32.5, 360), Vector3.new(22, 34, 360), 4, c3)
shineSpot(spots3, Vector3.new(27, 34, 360))
shineSpot(spots3, Vector3.new(12, 40, 452))
rock(z3, Vector3.new(-32, 52, 430), 5, c3)
jumpPad(z3, Vector3.new(-14, 40, 438), Vector3.new(-30, 52.3, 431), 8, 1.0, c3)
shineSpot(spots3, Vector3.new(-33, 52, 430))
crystal(z3, 3, "Shining", Vector3.new(27, 34, 360))
station(z3, "Flip", Vector3.new(10, 41, 440), Vector3.new(34, 41, 440), 3)
-- мост к зоне 4 и прыжки по островкам
local t4 = Turtle.new(Vector3.new(0, 40, 454), 180, 3)
Turtle.straight(t4, 18)
walkway(z3, t4.samples, 12, ZONE_COLORS[4])
gate(z3, 4, CFrame.new(0, 40, 459), 12)
local c4 = ZONE_COLORS[4]
jumpPad(z3, Vector3.new(0, 40, 469), Vector3.new(-18, 46.3, 488), 9, 1.0, c4)
rock(z3, Vector3.new(-18, 46, 490), 6, c4)
jumpPad(z3, Vector3.new(-18, 46, 493), Vector3.new(12, 53.3, 507), 9, 1.1, c4)
rock(z3, Vector3.new(12, 53, 510), 6, c4)
jumpPad(z3, Vector3.new(12, 53, 513), Vector3.new(0, 60.3, 542), 9, 1.1, c4)
task.wait()

-- ===== Зона 4: Закатная =====
local z4 = Instance.new("Folder")
z4.Name = "Zone4"
z4.Parent = map
local _, i4 = island(z4, "Sun", Vector3.new(0, 0, 560), 60, 26, c4)
checkpoint(i4, 26)
crystal(z4, 4, "Small", Vector3.new(-10, 60, 548))
crystal(z4, 4, "Small", Vector3.new(12, 60, 552))
crystal(z4, 4, "Big", Vector3.new(-8, 60, 578))
local spots4 = Instance.new("Folder")
spots4.Name = "ShineSpots"
spots4.Parent = z4
shineSpot(spots4, Vector3.new(18, 60, 574))
rock(z4, Vector3.new(42, 66, 560), 5, c4)
jumpPad(z4, Vector3.new(22, 60, 560), Vector3.new(40, 66.3, 560), 8, 1.0, c4)
shineSpot(spots4, Vector3.new(43, 66, 560))
rock(z4, Vector3.new(8, 72, 604), 5, c4)
jumpPad(z4, Vector3.new(6, 60, 582), Vector3.new(8, 72.3, 602), 10, 1.1, c4)
shineSpot(spots4, Vector3.new(8, 72, 605))
crystal(z4, 4, "Shining", Vector3.new(18, 60, 574))
station(z4, "Sunset", Vector3.new(-10, 61, 566), Vector3.new(-36, 61, 566), 4)
task.wait()

-- ===== Горки =====
local coasterFolder = Instance.new("Folder")
coasterFolder.Name = "Coasters"
coasterFolder.Parent = map
for _, def in Coasters.Defs do
	local track = Coasters.get(def.id)
	local f = Instance.new("Folder")
	f.Name = def.id
	f.Parent = coasterFolder
	rails(f, track, def.color)
	task.wait()
end

-- ===== Декор: парящие формы =====
local decorCenters = {
	{ Vector3.new(0, 10, 0), Color3.fromRGB(200, 175, 255) },
	{ Vector3.new(0, 10, 110), c1 },
	{ Vector3.new(-26, 30, 180), c2 },
	{ Vector3.new(0, 40, 380), c3 },
	{ Vector3.new(0, 60, 560), c4 },
}
local decor = Instance.new("Folder")
decor.Name = "Decor"
decor.Parent = map
for _, dc in decorCenters do
	for _ = 1, 14 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(75, 140)
		local pos = dc[1] + Vector3.new(math.cos(a) * r, rng:NextNumber(-30, 50), math.sin(a) * r)
		local size = rng:NextNumber(4, 12)
		local c = dc[2]:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.5))
		local kind = rng:NextInteger(1, 3)
		local d
		if kind == 1 then
			d = part({ Name = "Floaty", Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = pos, Color = c, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false, Parent = decor })
		elseif kind == 2 then
			d = part({ Name = "Floaty", Size = Vector3.one * size, CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), Color = c, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false, Parent = decor })
		else
			d = part({ Name = "Floaty", Size = Vector3.new(size * 0.4, size * 1.6, size * 0.4), CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 3), rng:NextNumber(-0.5, 0.5)), Color = dc[2], Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Parent = decor })
		end
		d.CastShadow = false
		CollectionService:AddTag(d, "Floaty")
	end
end

local n = 0
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		n += 1
	end
end
return "Map built, parts: " .. n
