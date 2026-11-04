--!strict
-- Всё, что видит и слышит только этот игрок: полёт предметов, всплывашки, звуки,
-- парящий декор, открытые ворота, подсказка «неси на базу».
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemVisual = require(ReplicatedStorage.Shared.ItemVisual)

local player = Players.LocalPlayer
local Effects = {}

-- ===== Звук =====
local soundCache: { [string]: Sound } = {}
function Effects.play(name: string, volume: number?, pitch: number?)
	local id = (Config.Sounds :: any)[name] :: string?
	if not id then
		return
	end
	local base = soundCache[name]
	if not base then
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Parent = SoundService
		soundCache[name] = s
		base = s
	end
	local s = base:Clone()
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(6, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local function startMusic()
	local music = Instance.new("Sound")
	music.Name = "Music"
	music.SoundId = Config.Sounds.Music
	music.Looped = true
	music.Volume = 0.18
	music.Parent = SoundService
	music:Play()
end

-- ===== Всплывающий текст над игроком =====
local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Effects.popup(text: string, color: Color3, big: boolean)
	local root = rootPart()
	if not root then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.Position = root.Position + Vector3.new(math.random(-10, 10) / 10, 2.5, math.random(-10, 10) / 10)
	anchor.Parent = Workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = if big then UDim2.fromOffset(320, 70) else UDim2.fromOffset(200, 44)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(40, 25, 70)
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local life = if big then 1.6 else 0.9
	TweenService:Create(anchor, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = anchor.Position + Vector3.new(0, if big then 4 else 3, 0) }):Play()
	task.delay(life * 0.55, function()
		TweenService:Create(label, TweenInfo.new(life * 0.45), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(life + 0.05, function()
		anchor:Destroy()
	end)
end

-- ===== Вспышка экрана и тряска камеры =====
local flashFrame: Frame? = nil
local function ensureFlash(): Frame
	if flashFrame and flashFrame.Parent then
		return flashFrame
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Flash"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = gui
	flashFrame = f
	return f
end

function Effects.flash(color: Color3, strength: number)
	local f = ensureFlash()
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - strength
	TweenService:Create(f, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

local shakeUntil = 0
local shakePower = 0
function Effects.shake(power: number, duration: number)
	shakePower = power
	shakeUntil = os.clock() + duration
end

-- ===== Полёт предмета из кристалла в рюкзак =====
local function punchCrystal(source: Model)
	local crystal = source.PrimaryPart
	if not crystal then
		return
	end
	local original = crystal:GetAttribute("BaseSize")
	if typeof(original) ~= "Vector3" then
		original = crystal.Size
		crystal:SetAttribute("BaseSize", original)
	end
	local size = original :: Vector3
	crystal.Size = size * 1.1
	TweenService:Create(crystal, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = size }):Play()
	local halo = source:FindFirstChild("Halo") :: BasePart?
	if halo then
		halo.Transparency = 0
		TweenService:Create(halo, TweenInfo.new(0.4), { Transparency = 0.2 }):Play()
	end
end

local function burst(position: Vector3, color: Color3, count: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.1
	p.Position = position
	p.Parent = Workspace
	local att = Instance.new("Attachment")
	att.Parent = p
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.4, 0.8)
	pe.Speed = NumberRange.new(8, 16)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 4
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(count)
	task.delay(1.2, function()
		p:Destroy()
	end)
end

function Effects.drop(source: Model, itemId: string, rarity: Config.Rarity)
	local kind = Config.ItemById[itemId]
	if not kind then
		return
	end
	local info = Config.RarityInfo[rarity]
	punchCrystal(source)
	local pivot = source:GetPivot().Position
	local start = Vector3.new(pivot.X, 7, pivot.Z)
	local angle = math.random() * math.pi * 2
	local landing = Vector3.new(pivot.X + math.cos(angle) * 4, 1.2, pivot.Z + math.sin(angle) * 4)
	local model = ItemVisual.make(itemId, rarity, true)
	model:PivotTo(CFrame.new(start))
	model.Parent = Workspace

	if rarity == "Common" then
		Effects.play("Pop", 0.45, 0.9 + math.random() * 0.3)
	elseif rarity == "Rare" then
		Effects.play("Rare", 0.7)
		burst(start, info.color, 25)
		Effects.flash(info.color, 0.18)
	else
		Effects.play("Epic", 0.8)
		burst(start, info.color, 60)
		Effects.flash(info.color, 0.35)
		Effects.shake(0.35, 0.4)
	end

	local spin = Vector3.new(math.random() * 6 - 3, 4 + math.random() * 4, math.random() * 6 - 3)
	local t0 = os.clock()
	local arc, hover, fly = 0.42, if rarity == "Common" then 0.2 else 0.55, 0.32
	local connection: RBXScriptConnection
	local flyFrom: Vector3? = nil
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local rot = CFrame.Angles(spin.X * t, spin.Y * t, spin.Z * t)
		if t < arc then
			local k = t / arc
			local pos = start:Lerp(landing, k) + Vector3.new(0, math.sin(k * math.pi) * 5, 0)
			model:PivotTo(CFrame.new(pos) * rot)
		elseif t < arc + hover then
			local k = (t - arc) / hover
			local bounce = math.abs(math.sin(k * math.pi * 2)) * 0.8 * (1 - k)
			model:PivotTo(CFrame.new(landing + Vector3.new(0, bounce, 0)) * rot)
		else
			local root = rootPart()
			if not root then
				connection:Disconnect()
				model:Destroy()
				return
			end
			if not flyFrom then
				flyFrom = landing
			end
			local k = math.min((t - arc - hover) / fly, 1)
			local eased = k * k
			local target = root.Position + Vector3.new(0, 1, 0)
			local pos = (flyFrom :: Vector3):Lerp(target, eased)
			model:ScaleTo(math.max(1 - eased * 0.7, 0.05))
			model:PivotTo(CFrame.new(pos) * rot)
			if k >= 1 then
				connection:Disconnect()
				model:Destroy()
				if rarity == "Common" then
					Effects.popup("+1 " .. kind.name, Color3.new(1, 1, 1), false)
				elseif rarity == "Rare" then
					Effects.popup("РЕДКИЙ: " .. kind.name .. "!", info.color, true)
				else
					Effects.popup("ЭПИК: " .. kind.name .. "!!", info.color, true)
				end
			end
		end
	end)
end

-- ===== Продажа на базе =====
function Effects.sold(earned: number, newKeys: { string })
	if earned > 0 then
		Effects.play("Coins", 0.6)
		local root = rootPart()
		if root then
			burst(root.Position + Vector3.new(0, 2, 0), Color3.fromRGB(255, 215, 90), 30)
		end
	end
	for i, key in newKeys do
		task.delay(0.35 * i, function()
			local itemId, rarity = string.match(key, "^(.-):(.+)$")
			local kind = itemId and Config.ItemById[itemId]
			local info = rarity and (Config.RarityInfo :: any)[rarity]
			if kind and info then
				Effects.play("Rare", 0.6, 1.15)
				Effects.popup("В коллекцию: " .. kind.name .. " (" .. info.name .. ")", info.color, true)
			end
		end)
	end
end

-- ===== Парящий декор =====
type Floaty = { part: BasePart, base: CFrame, phase: number, amp: number, spin: number }
local floaties: { Floaty } = {}
local spinners: { BasePart } = {}

local function addFloaty(inst: Instance)
	if inst:IsA("BasePart") then
		table.insert(floaties, {
			part = inst,
			base = inst.CFrame,
			phase = math.random() * 10,
			amp = 0.6 + math.random() * 1.6,
			spin = (math.random() - 0.5) * 0.6,
		})
	end
end

local function addSpinner(inst: Instance)
	if inst:IsA("BasePart") then
		table.insert(spinners, inst)
	end
end

-- ===== Ворота: открытые для меня становятся проходимыми =====
local function refreshGates()
	local raw = player:GetAttribute("Gates")
	local ok, list = pcall(function()
		return HttpService:JSONDecode(if type(raw) == "string" then raw else "[]")
	end)
	local open: { [number]: boolean } = {}
	if ok and type(list) == "table" then
		for _, z in list do
			open[z] = true
		end
	end
	for _, gate in CollectionService:GetTagged("Gate") do
		local zone = gate:GetAttribute("Zone")
		local barrier = gate:FindFirstChild("Barrier") :: BasePart?
		if type(zone) == "number" and barrier then
			local isOpen = open[zone] == true
			local wasOpen = barrier:GetAttribute("OpenLocal") == true
			barrier.CanCollide = not isOpen
			local prompt = barrier:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = not isOpen
			end
			local sign = barrier:FindFirstChild("PriceSign") :: BillboardGui?
			if sign then
				sign.Enabled = not isOpen
			end
			if isOpen and not wasOpen then
				barrier:SetAttribute("OpenLocal", true)
				TweenService:Create(barrier, TweenInfo.new(0.6), { Transparency = 1 }):Play()
				local fx = gate:FindFirstChild("BarrierFx") :: BasePart?
				if fx then
					TweenService:Create(fx, TweenInfo.new(0.6), { Transparency = 1 }):Play()
				end
				if os.clock() > 3 then
					Effects.play("Buy", 0.7)
					burst(barrier.Position, Config.ZoneColors[zone], 80)
					Effects.flash(Config.ZoneColors[zone], 0.25)
				end
			end
		end
	end
end

-- ===== Подсказка «неси на базу», когда рюкзак полон =====
local guide: Beam? = nil
local guideTarget: Attachment? = nil
local function refreshGuide()
	local count = player:GetAttribute("BagCount")
	local cap = player:GetAttribute("Capacity")
	local full = type(count) == "number" and type(cap) == "number" and count >= cap
	local root = rootPart()
	if full and root then
		if not guideTarget then
			local floor = CollectionService:GetTagged("BaseFloor")[1] :: BasePart?
			if not floor then
				return
			end
			local att = Instance.new("Attachment")
			att.Name = "GuideTarget"
			att.WorldPosition = floor.Position + Vector3.new(0, 4, 0)
			att.Parent = floor
			guideTarget = att
		end
		local from = root:FindFirstChild("GuideFrom") :: Attachment?
		if not from then
			local a = Instance.new("Attachment")
			a.Name = "GuideFrom"
			a.Parent = root
			from = a
		end
		if not guide then
			local b = Instance.new("Beam")
			b.Color = ColorSequence.new(Color3.fromRGB(255, 220, 110))
			b.LightEmission = 1
			b.Width0 = 0.8
			b.Width1 = 0.8
			b.FaceCamera = true
			b.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			b.TextureMode = Enum.TextureMode.Wrap
			b.TextureLength = 3
			b.TextureSpeed = 2
			b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.6) })
			b.Parent = Workspace
			guide = b
		end
		local beam = guide :: Beam
		beam.Attachment0 = from
		beam.Attachment1 = guideTarget
		beam.Enabled = true
	elseif guide then
		guide.Enabled = false
	end
end

function Effects.start()
	startMusic()
	for _, inst in CollectionService:GetTagged("Floaty") do
		addFloaty(inst)
	end
	for _, inst in CollectionService:GetTagged("Spin") do
		addSpinner(inst)
	end
	local spinnerBase: { [BasePart]: CFrame } = {}
	for _, s in spinners do
		spinnerBase[s] = s.CFrame
	end
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, f in floaties do
			f.part.CFrame = f.base * CFrame.new(0, math.sin(t * 0.8 + f.phase) * f.amp, 0) * CFrame.Angles(0, t * f.spin, 0)
		end
		for _, s in spinners do
			local base = spinnerBase[s]
			if base then
				s.CFrame = CFrame.new(base.Position + Vector3.new(0, math.sin(t * 1.5) * 0.4, 0)) * CFrame.Angles(0, t * 1.2, 0) * base.Rotation
			end
		end
	end)
	-- тряска после того, как камера Roblox обновилась
	RunService:BindToRenderStep("RoblohShake", Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock()
		if t < shakeUntil then
			local camera = Workspace.CurrentCamera
			local p = shakePower * ((shakeUntil - t) / 0.4)
			camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * p * 4), math.rad((math.random() - 0.5) * p * 4), 0)
		end
	end)
	refreshGates()
	player:GetAttributeChangedSignal("Gates"):Connect(refreshGates)
	player:GetAttributeChangedSignal("BagCount"):Connect(refreshGuide)
	player:GetAttributeChangedSignal("Capacity"):Connect(refreshGuide)
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		refreshGuide()
	end)
end

return Effects
