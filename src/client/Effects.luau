--!strict
-- Всё, что видит и слышит только этот игрок: всплывашки, звуки, кристаллы (дрожь,
-- раскол, восстановление), парящий декор, открытые ворота, луч «неси к алтарю».
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

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

function Effects.burst(position: Vector3, color: Color3, count: number)
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
					Effects.burst(barrier.Position, Config.ZoneColors[zone], 80)
					Effects.flash(Config.ZoneColors[zone], 0.25)
				end
			end
		end
	end
end

-- ===== Луч «неси к алтарю», пока несёшь ядро =====
local guide: Beam? = nil
local guideTarget: Attachment? = nil
local function refreshGuide()
	local zone = player:GetAttribute("CarryZone")
	local carrying = type(zone) == "number" and zone > 0
	-- кнопка алтаря видна только с ядром
	for _, altar in CollectionService:GetTagged("Altar") do
		local prompt = altar.Parent and altar.Parent:FindFirstChild("Crack", true) :: ProximityPrompt?
		if prompt then
			prompt.Enabled = carrying and player:GetAttribute("Pending") ~= true
		end
	end
	local root = rootPart()
	if carrying and root then
		if not guideTarget then
			local altar = CollectionService:GetTagged("Altar")[1] :: BasePart?
			if not altar then
				return
			end
			local att = Instance.new("Attachment")
			att.Name = "GuideTarget"
			att.WorldPosition = altar.Position + Vector3.new(0, 3, 0)
			att.Parent = altar
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

-- ===== Кристаллы: что видит этот игрок =====
type CrystalView = {
	model: Model,
	body: BasePart,
	baseSize: Vector3,
	prompt: ProximityPrompt,
	zone: number,
	kind: Config.CrystalKind,
	extras: { BasePart },
}
type Hold = { model: Model, cf: CFrame, t0: number, tick: number }
local crystals: { CrystalView } = {}
local readyAt: { [Model]: number } = {}
local regrowTime: { [Model]: number } = {}
local holding: Hold? = nil

local function viewOf(model: Model): CrystalView?
	for _, c in crystals do
		if c.model == model then
			return c
		end
	end
	return nil
end

local function addCrystal(inst: Instance)
	if not inst:IsA("Model") or viewOf(inst) then
		return
	end
	-- части модели могут прийти чуть позже самой модели
	local body = inst:WaitForChild("Body", 10) :: BasePart?
	local promptPart = inst:WaitForChild("PromptPart", 10)
	local prompt = promptPart and promptPart:WaitForChild("Mine", 10) :: ProximityPrompt?
	local zone = inst:GetAttribute("Zone")
	local kind = inst:GetAttribute("Kind")
	if not body or not prompt or type(zone) ~= "number" or type(kind) ~= "string" then
		return
	end
	local size = body:GetAttribute("BaseSize")
	local extras = {}
	for _, p in inst:GetDescendants() do
		if p:IsA("BasePart") and p ~= body and p.Name ~= "PromptPart" and p.Name ~= "BeamTop" then
			p:SetAttribute("BaseTransparency", p.Transparency)
			table.insert(extras, p)
		end
	end
	table.insert(crystals, {
		model = inst,
		body = body,
		baseSize = if typeof(size) == "Vector3" then size else body.Size,
		prompt = prompt,
		zone = zone,
		kind = kind :: Config.CrystalKind,
		extras = extras,
	})
end

local function gatesOpen(): { [number]: boolean }
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
	return open
end

local function refreshCrystals()
	local now = os.clock()
	local zoneAttr = player:GetAttribute("CarryZone")
	local carrying = type(zoneAttr) == "number" and zoneAttr > 0
	local strength = player:GetAttribute("Level_Strength")
	local open = gatesOpen()
	for _, c in crystals do
		local hidden = c.kind == "Shining" and c.model:GetAttribute("Hidden") == true
		local ready = readyAt[c.model] or 0
		local depleted = c.kind ~= "Shining" and ready > now
		c.prompt.HoldDuration = Config.mineTime(c.zone, c.kind, if type(strength) == "number" then strength else 0)
		c.prompt.Enabled = not carrying and not hidden and not depleted and open[c.zone] == true
		-- вид: исчез / растёт заново / целый
		local grow = 1
		if hidden then
			grow = 0.05
		elseif depleted then
			local total = regrowTime[c.model] or 20
			grow = 0.25 + 0.75 * math.clamp(1 - (ready - now) / total, 0, 1)
		end
		local h = holding
		if not (h and h.model == c.model) then
			c.body.Size = c.baseSize * grow
		end
		c.body.Transparency = if hidden then 1 elseif depleted then 0.55 else 0
		for _, p in c.extras do
			local baseT = p:GetAttribute("BaseTransparency")
			p.Transparency = if hidden then 1 elseif depleted then 0.85 else (if type(baseT) == "number" then baseT else 0)
		end
		for _, d in c.model:GetDescendants() do
			if d:IsA("Beam") or d:IsA("ParticleEmitter") or d:IsA("PointLight") then
				(d :: any).Enabled = not hidden and not depleted
			end
		end
	end
end

-- держишь кнопку — кристалл дрожит всё сильнее и звенит выше
local function onHoldBegan(prompt: ProximityPrompt)
	if prompt.Name ~= "Mine" then
		return
	end
	local model = prompt:FindFirstAncestorWhichIsA("Model")
	local view = model and viewOf(model)
	if not view then
		return
	end
	holding = { model = view.model, cf = view.body.CFrame, t0 = os.clock(), tick = 0 }
end

local function stopHold()
	local h = holding
	if h then
		local view = viewOf(h.model)
		if view then
			view.body.CFrame = h.cf
			view.body.Size = view.baseSize
		end
		holding = nil
	end
end

local function updateHold()
	local h = holding
	if not h then
		return
	end
	local view = viewOf(h.model)
	if not view then
		return
	end
	local need = math.max(view.prompt.HoldDuration, 0.1)
	local k = math.clamp((os.clock() - h.t0) / need, 0, 1)
	local a = 0.04 + k * 0.18
	view.body.CFrame = h.cf * CFrame.new((math.random() - 0.5) * a * 2, 0, (math.random() - 0.5) * a * 2) * CFrame.Angles(0, (math.random() - 0.5) * a, (math.random() - 0.5) * a)
	view.body.Size = view.baseSize * (1 + k * 0.08 + math.sin(os.clock() * 30) * 0.015)
	local ticks = math.floor(k * 8)
	if ticks > h.tick then
		h.tick = ticks
		Effects.play("Pop", 0.25 + k * 0.2, 0.8 + k * 0.9)
		Effects.burst(view.body.Position + Vector3.new(0, view.baseSize.Y * 0.3, 0), Config.ZoneColors[view.zone], 4 + ticks * 2)
	end
end

function Effects.mined(model: Model, regrow: number)
	local view = viewOf(model)
	if not view then
		return
	end
	stopHold()
	readyAt[model] = os.clock() + regrow
	regrowTime[model] = regrow
	local color = Config.ZoneColors[view.zone]
	local pos = view.body.Position
	Effects.burst(pos, color, if view.kind == "Small" then 40 else 90)
	Effects.flash(color, if view.kind == "Shining" then 0.45 else 0.2)
	Effects.shake(if view.kind == "Small" then 0.2 else 0.45, 0.35)
	Effects.play(if view.kind == "Small" then "Rare" else "Epic", 0.7, 1.1)
	Effects.popup(Config.Crystals[view.kind].coreName .. "!", color, true)
	refreshCrystals()
end

local function startCrystals()
	for _, inst in CollectionService:GetTagged("Crystal") do
		task.spawn(addCrystal, inst)
	end
	CollectionService:GetInstanceAddedSignal("Crystal"):Connect(addCrystal)
	CollectionService:GetInstanceRemovedSignal("Crystal"):Connect(function(inst: Instance)
		for i, c in crystals do
			if c.model == inst then
				table.remove(crystals, i)
				break
			end
		end
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(onHoldBegan)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "Mine" then
			stopHold()
		end
	end)
	RunService.RenderStepped:Connect(updateHold)
	task.spawn(function()
		while true do
			refreshCrystals()
			task.wait(0.25)
		end
	end)
	player:GetAttributeChangedSignal("CarryZone"):Connect(refreshCrystals)
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
	player:GetAttributeChangedSignal("CarryZone"):Connect(refreshGuide)
	player:GetAttributeChangedSignal("Pending"):Connect(refreshGuide)
	refreshGuide()
	startCrystals()
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		refreshGuide()
	end)
end

return Effects
