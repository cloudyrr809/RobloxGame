--!nocheck
-- Строит карту прототипа в Workspace.Map. Запуск: через Roblox Studio MCP (execute_luau, Edit).
-- Повторный запуск удаляет старую карту и строит заново.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")

local BASE_R = 45 -- радиус базы
local PATH_W = 22
local ZONE_LEN = 80
local PATH_START = BASE_R - 2
local ZONES = {
	{ name = "Мятная", color = Color3.fromRGB(110, 230, 185) },
	{ name = "Небесная", color = Color3.fromRGB(110, 185, 255) },
	{ name = "Лиловая", color = Color3.fromRGB(185, 135, 255) },
	{ name = "Закатная", color = Color3.fromRGB(255, 165, 105) },
}
local GATE_PRICES = { 0, 150, 1200, 9000 }

local old = workspace:FindFirstChild("Map")
if old then
	old:Destroy()
end
for _, n in { "Baseplate" } do
	local p = workspace:FindFirstChild(n)
	if p then
		p:Destroy()
	end
end

local rng = Random.new(7)

local function part(props)
	local p = Instance.new(props.Class or "Part")
	props.Class = nil
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- порядок важен: форма → размер → положение
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

local function disc(parent, name, radius, height, cf, color, material, variant)
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = cf * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
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

-- ===== Освещение =====
Lighting.ClockTime = 15.2
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(120, 110, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 180)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.8
Lighting.GlobalShadows = true
local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
atm.Density = 0.32
atm.Offset = 0.15
atm.Color = Color3.fromRGB(230, 205, 255)
atm.Decay = Color3.fromRGB(150, 120, 210)
atm.Glare = 0.4
atm.Haze = 1.6
local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect", Lighting)
bloom.Intensity = 0.6
bloom.Size = 30
bloom.Threshold = 1.6
local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
if dof then
	dof.Enabled = false
end
local cc = Lighting:FindFirstChild("RoblohColor") or Instance.new("ColorCorrectionEffect", Lighting)
cc.Name = "RoblohColor"
cc.Saturation = 0.12
cc.Contrast = 0.06
cc.TintColor = Color3.fromRGB(255, 250, 255)
workspace.FallenPartsDestroyHeight = -120

local map = Instance.new("Folder")
map.Name = "Map"
map.Parent = workspace

-- ===== База =====
local base = Instance.new("Model")
base.Name = "Base"
base.Parent = map
local floor = disc(base, "Floor", BASE_R, 4, CFrame.new(0, -2, 0), Color3.fromRGB(245, 240, 250), Enum.Material.Marble, "RoblohFloor")
disc(base, "Rim", BASE_R + 1.2, 3, CFrame.new(0, -2.3, 0), Color3.fromRGB(200, 175, 255), Enum.Material.Neon)
disc(base, "Under", BASE_R - 4, 10, CFrame.new(0, -9, 0), Color3.fromRGB(70, 60, 95), Enum.Material.Slate, "RoblohStone")
disc(base, "UnderTip", BASE_R - 16, 10, CFrame.new(0, -18, 0), Color3.fromRGB(60, 50, 85), Enum.Material.Slate, "RoblohStone")
CollectionService:AddTag(floor, "BaseFloor")
floor:SetAttribute("Radius", BASE_R)

-- зона сдачи: светящееся кольцо в центре
local sell = disc(base, "SellRing", 12, 0.3, CFrame.new(0, 0.1, 8), Color3.fromRGB(255, 220, 120), Enum.Material.Neon)
sell.CanCollide = false
local sellIn = disc(base, "SellInner", 10.8, 0.4, CFrame.new(0, 0.12, 8), Color3.fromRGB(250, 245, 235), Enum.Material.Marble, "RoblohFloor")
sellIn.CanCollide = false
local sellSign = part({ Name = "SellSign", Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false, Position = Vector3.new(0, 7, 8), Parent = base })
local bb = Instance.new("BillboardGui")
bb.Size = UDim2.fromOffset(260, 70)
bb.MaxDistance = 120
bb.LightInfluence = 0
bb.Parent = sellSign
local t = Instance.new("TextLabel")
t.Size = UDim2.fromScale(1, 1)
t.BackgroundTransparency = 1
t.Text = "БАЗА\nсдача — автоматически"
t.Font = Enum.Font.FredokaOne
t.TextScaled = true
t.TextColor3 = Color3.new(1, 1, 1)
t.TextStrokeTransparency = 0.4
t.TextStrokeColor3 = Color3.fromRGB(90, 60, 140)
t.Parent = bb

-- спавн
local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
if not spawn then
	spawn = Instance.new("SpawnLocation")
end
spawn.Name = "Spawn"
spawn.Anchored = true
spawn.Size = Vector3.new(8, 0.4, 8)
spawn.CFrame = CFrame.new(0, 0.2, -18)
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

-- станции: улучшения (слева) и коллекция (справа)
local function station(name, x, color, label)
	local m = Instance.new("Model")
	m.Name = name
	disc(m, "Pad", 7, 1, CFrame.new(x, 0.5, -2), Color3.fromRGB(80, 70, 110), Enum.Material.Slate, "RoblohStone")
	disc(m, "PadGlow", 7.4, 0.6, CFrame.new(x, 0.3, -2), color, Enum.Material.Neon)
	local body = part({
		Name = "Monolith",
		Size = Vector3.new(4, 11, 4),
		CFrame = CFrame.new(x, 6.5, -2) * CFrame.Angles(0, math.rad(45), 0),
		Color = Color3.fromRGB(70, 62, 100),
		Material = Enum.Material.Slate,
		MaterialVariant = "RoblohStone",
		Parent = m,
	})
	local core = part({
		Name = "Core",
		Size = Vector3.new(2.2, 2.2, 2.2),
		CFrame = CFrame.new(x, 14.5, -2) * CFrame.Angles(math.rad(45), math.rad(45), 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = m,
	})
	CollectionService:AddTag(core, "Spin")
	light(core, color, 18, 2)
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(220, 46)
	sign.StudsOffset = Vector3.new(0, 4, 0)
	sign.MaxDistance = 90
	sign.LightInfluence = 0
	sign.Parent = core
	local l = t:Clone()
	l.Text = label
	l.Parent = sign
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Open"
	prompt.ActionText = label
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	m.Parent = base
	CollectionService:AddTag(m, name)
	return m
end
station("UpgradeStation", -24, Color3.fromRGB(255, 205, 90), "Улучшения")
station("CollectionStation", 24, Color3.fromRGB(120, 220, 255), "Коллекция")

-- ===== Дорожка и зоны =====
local path = Instance.new("Folder")
path.Name = "Path"
path.Parent = map
local white = Color3.fromRGB(240, 238, 246)

for z = 1, #ZONES do
	local zone = ZONES[z]
	local zf = Instance.new("Folder")
	zf.Name = "Zone" .. z
	zf:SetAttribute("Zone", z)
	zf.Parent = path
	local z0 = PATH_START + (z - 1) * ZONE_LEN
	local tint = white:Lerp(zone.color, 0.22)

	-- плитки дорожки
	local tiles = ZONE_LEN / 10
	for i = 0, tiles - 1 do
		local zc = z0 + i * 10 + 5
		local c = if i % 2 == 0 then tint else tint:Lerp(white, 0.5)
		part({ Name = "Tile", Size = Vector3.new(PATH_W, 4, 10), Position = Vector3.new(0, -2, zc), Color = c, Material = Enum.Material.CeramicTiles, MaterialVariant = "RoblohPath", Parent = zf })
		-- бортики
		for _, s in { -1, 1 } do
			part({ Name = "Curb", Size = Vector3.new(1.2, 0.8, 10), Position = Vector3.new(s * (PATH_W / 2 + 0.6), 0.4, zc), Color = zone.color, Material = Enum.Material.SmoothPlastic, Parent = zf })
		end
	end
	-- подложка дорожки
	part({ Name = "Under", Size = Vector3.new(PATH_W - 4, 6, ZONE_LEN), Position = Vector3.new(0, -7, z0 + ZONE_LEN / 2), Color = Color3.fromRGB(70, 60, 95), Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = zf })

	-- ворота в начале зоны (кроме первой)
	if GATE_PRICES[z] > 0 then
		local gate = Instance.new("Model")
		gate.Name = "Gate"
		gate:SetAttribute("Zone", z)
		gate:SetAttribute("Price", GATE_PRICES[z])
		for _, s in { -1, 1 } do
			part({ Name = "Pillar", Size = Vector3.new(3, 16, 3), Position = Vector3.new(s * (PATH_W / 2 + 1.5), 8, z0), Color = Color3.fromRGB(70, 62, 100), Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = gate })
			local cap = part({ Name = "Cap", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = CFrame.new(s * (PATH_W / 2 + 1.5), 17.6, z0) * CFrame.Angles(math.rad(45), math.rad(45), 0), Color = zone.color, Material = Enum.Material.Neon, CanCollide = false, Parent = gate })
			light(cap, zone.color, 16, 1.5)
		end
		part({ Name = "Lintel", Size = Vector3.new(PATH_W + 6, 2, 3), Position = Vector3.new(0, 16.5, z0), Color = Color3.fromRGB(70, 62, 100), Material = Enum.Material.Slate, MaterialVariant = "RoblohStone", Parent = gate })
		local wall = part({ Name = "Barrier", Size = Vector3.new(PATH_W, 15.5, 1), Position = Vector3.new(0, 7.75, z0), Color = zone.color, Material = Enum.Material.Glass, Transparency = 0.55, Parent = gate })
		part({ Name = "BarrierFx", Size = Vector3.new(PATH_W, 15.5, 1.4), Position = Vector3.new(0, 7.75, z0), Color = zone.color, Material = Enum.Material.ForceField, CanCollide = false, CanQuery = false, CanTouch = false, Parent = gate })
		local gsign = Instance.new("BillboardGui")
		gsign.Name = "PriceSign"
		gsign.Size = UDim2.fromOffset(300, 90)
		gsign.StudsOffset = Vector3.new(0, 0, 0)
		gsign.MaxDistance = 140
		gsign.LightInfluence = 0
		gsign.Parent = wall
		local gl = t:Clone()
		gl.Name = "Label"
		gl.Text = zone.name .. " зона\n" .. GATE_PRICES[z] .. " монет"
		gl.Parent = gsign
		local gp = Instance.new("ProximityPrompt")
		gp.Name = "Buy"
		gp.ActionText = "Открыть за " .. GATE_PRICES[z]
		gp.ObjectText = zone.name .. " зона"
		gp.HoldDuration = 0.3
		gp.MaxActivationDistance = 14
		gp.RequiresLineOfSight = false
		gp.Parent = wall
		gate.Parent = zf
		CollectionService:AddTag(gate, "Gate")
	end

	-- источники: 3 на зону, на боковых площадках
	for s = 1, 3 do
		local side = if s % 2 == 1 then -1 else 1
		local zc = z0 + 14 + (s - 1) * 24
		local x = side * (PATH_W / 2 + 7)
		local src = Instance.new("Model")
		src.Name = "Source" .. s
		src:SetAttribute("Zone", z)
		src:SetAttribute("Index", (z - 1) * 3 + s)
		-- мостик и площадка
		part({ Name = "Bridge", Size = Vector3.new(6, 3, 8), Position = Vector3.new(side * (PATH_W / 2 + 2), -1.5, zc), Color = tint, Material = Enum.Material.CeramicTiles, MaterialVariant = "RoblohPath", Parent = src })
		disc(src, "Pad", 7, 3, CFrame.new(x, -1.5, zc), Color3.fromRGB(80, 70, 110), Enum.Material.Slate, "RoblohStone")
		disc(src, "PadGlow", 7.5, 0.8, CFrame.new(x, -0.7, zc), zone.color, Enum.Material.Neon)
		disc(src, "Under", 5, 6, CFrame.new(x, -6, zc), Color3.fromRGB(60, 50, 85), Enum.Material.Slate, "RoblohStone")
		-- кристалл: центральный + 4 малых
		local ccf = CFrame.new(x, 5.2, zc) * CFrame.Angles(0, math.rad(45), 0)
		local crystal = part({ Name = "Crystal", Size = Vector3.new(3.6, 6.5, 3.6), CFrame = ccf, Color = zone.color, Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.15, Parent = src })
		local core = part({ Name = "Core", Size = Vector3.new(1.6, 4.2, 1.6), CFrame = ccf, Color = zone.color, Material = Enum.Material.Neon, CanCollide = false, Parent = src })
		part({ Name = "Tip", Class = "WedgePart", Size = Vector3.new(3.6, 2.4, 1.8), CFrame = ccf * CFrame.new(0, 4.45, 0.9), Color = zone.color, Material = Enum.Material.Glass, Transparency = 0.25, Parent = src })
		part({ Name = "Tip2", Class = "WedgePart", Size = Vector3.new(3.6, 2.4, 1.8), CFrame = ccf * CFrame.new(0, 4.45, -0.9) * CFrame.Angles(0, math.rad(180), 0), Color = zone.color, Material = Enum.Material.Glass, Transparency = 0.25, Parent = src })
		for k = 1, 4 do
			local a = math.rad(k * 90 + rng:NextNumber(-20, 20))
			local h = rng:NextNumber(2, 3.4)
			part({
				Name = "Shard",
				Size = Vector3.new(1.4, h, 1.4),
				CFrame = CFrame.new(x + math.cos(a) * 3, 0.2 + h / 2, zc + math.sin(a) * 3) * CFrame.Angles(0, a, math.rad(rng:NextNumber(-25, 25))),
				Color = zone.color:Lerp(white, 0.3),
				Material = Enum.Material.Glass,
				Transparency = 0.2,
				Parent = src,
			})
		end
		local halo = part({ Name = "Halo", Size = Vector3.new(0.4, 9, 9), Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(x, 5.2, zc) * CFrame.Angles(0, 0, math.rad(90)), Color = zone.color, Material = Enum.Material.ForceField, CanCollide = false, CanQuery = false, Parent = src })
		halo.Transparency = 0.2
		light(core, zone.color, 20, 2.2)
		local att = Instance.new("Attachment")
		att.Name = "Sparkle"
		att.Parent = core
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(zone.color, Color3.new(1, 1, 1))
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new(0.2)
		pe.Lifetime = NumberRange.new(1, 1.8)
		pe.Rate = 4
		pe.Speed = NumberRange.new(1, 2.5)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = att
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 36
		cd.CursorIcon = ""
		cd.Parent = src
		src.PrimaryPart = crystal
		src.Parent = zf
		CollectionService:AddTag(src, "Source")
	end

	-- декор: парящие абстрактные формы
	for _ = 1, 14 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local pos = Vector3.new(side * rng:NextNumber(30, 70), rng:NextNumber(-10, 40), z0 + rng:NextNumber(0, ZONE_LEN))
		local size = rng:NextNumber(3, 10)
		local kind = rng:NextInteger(1, 4)
		local c = zone.color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.5))
		local d
		if kind == 1 then
			d = part({ Name = "Floaty", Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = pos, Color = c, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false, Parent = zf })
		elseif kind == 2 then
			d = part({ Name = "Floaty", Size = Vector3.one * size, CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0), Color = c, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false, Parent = zf })
		elseif kind == 3 then
			d = part({ Name = "Floaty", Shape = Enum.PartType.Cylinder, Size = Vector3.new(size * 0.25, size * 1.4, size * 1.4), CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(0, 3), 0, rng:NextNumber(0, 3)), Color = c, Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, CanQuery = false, Parent = zf })
		else
			d = part({ Name = "Floaty", Size = Vector3.new(size * 0.4, size * 1.6, size * 0.4), CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 3), rng:NextNumber(-0.5, 0.5)), Color = zone.color, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Parent = zf })
		end
		d.CastShadow = false
		CollectionService:AddTag(d, "Floaty")
	end
	task.wait()
end

-- конец дорожки: финальная площадка
local endZ = PATH_START + #ZONES * ZONE_LEN
disc(path, "EndPad", 16, 4, CFrame.new(0, -2, endZ + 12), white:Lerp(ZONES[4].color, 0.3), Enum.Material.Marble, "RoblohFloor")
disc(path, "EndGlow", 16.8, 3, CFrame.new(0, -2.3, endZ + 12), ZONES[4].color, Enum.Material.Neon)
part({ Name = "EndLink", Size = Vector3.new(PATH_W, 4, 8), Position = Vector3.new(0, -2, endZ + 2), Color = white, Material = Enum.Material.CeramicTiles, MaterialVariant = "RoblohPath", Parent = path })

-- декор вокруг базы
for _ = 1, 16 do
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(60, 95)
	local pos = Vector3.new(math.cos(a) * r, rng:NextNumber(-15, 35), math.sin(a) * r)
	if pos.Z > 30 and math.abs(pos.X) < 30 then
		continue
	end
	local size = rng:NextNumber(4, 12)
	local c = Color3.fromHSV(rng:NextNumber(0.7, 0.95), 0.35, 1)
	local d = part({ Name = "Floaty", Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = pos, Color = c, Material = Enum.Material.SmoothPlastic, CanCollide = false, CanQuery = false, CastShadow = false, Parent = base })
	CollectionService:AddTag(d, "Floaty")
end

-- Сгенерированные ИИ кристаллы (ServerStorage.MapAssets.CrystalZone1..4) вместо кристаллов из блоков
local assets = game:GetService("ServerStorage"):FindFirstChild("MapAssets")
if assets then
	for z = 1, #ZONES do
		local tpl = assets:FindFirstChild("CrystalZone" .. z)
		if tpl then
			for _, src in path["Zone" .. z]:GetChildren() do
				if src:IsA("Model") and src.Name:match("^Source") then
					local core = src.Core
					local pos = core.Position
					for _, c in src:GetChildren() do
						if c.Name == "Crystal" or c.Name == "Tip" or c.Name == "Tip2" or c.Name == "Shard" then
							c:Destroy()
						end
					end
					local m = tpl:Clone()
					m.Name = "Crystal"
					m.Size *= 9.5 / m.Size.Y
					m.Anchored = true
					m.CollisionFidelity = Enum.CollisionFidelity.Box
					m.CFrame = CFrame.new(pos.X, m.Size.Y / 2 - 0.1, pos.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
					m.Parent = src
					src.PrimaryPart = m
					core.Transparency = 1
					core.Position = Vector3.new(pos.X, 6, pos.Z)
					src.Halo.Size = Vector3.new(0.3, 12, 12)
					src.Halo.Position = Vector3.new(pos.X, 1.2, pos.Z)
				end
			end
		end
	end
end

return "Map built"
