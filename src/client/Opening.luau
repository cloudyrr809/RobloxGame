--!strict
-- Раскол ядра на алтаре. Сервер уже решил, что внутри, и прислал результат;
-- здесь — представление: игрок бьёт по ядру 4 раза, из трещин светит цвет-подсказка
-- (белый → синий → розовый → золотой), иногда свет «дразнит» и гаснет на ступень ниже.
-- После последнего удара — взрыв и предмет. Награда на счёт приходит после показа.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local EconomyMath = require(ReplicatedStorage.Shared.EconomyMath)
local ItemVisual = require(ReplicatedStorage.Shared.ItemVisual)
local Effects = require(script.Parent.Effects)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RevealDone = Remotes:WaitForChild("RevealDone") :: RemoteEvent

local player = Players.LocalPlayer
local Opening = {}

export type Result = {
	zone: number,
	kind: Config.CrystalKind,
	itemId: string,
	rarity: Config.Rarity,
	coins: number,
	isNew: boolean,
	heat: number,
}

local HITS = 4
local CORE_SCALE = 2 -- на алтаре ядро крупнее, чем над головой
local TIER_RARITY: { Config.Rarity } = { "Common", "Rare", "Epic", "Legendary" }

local busy = false
local onDone: (Result) -> () = function(_r: Result) end

function Opening.onDone(fn: (Result) -> ())
	onDone = fn
end

function Opening.busy(): boolean
	return busy
end

-- последовательность цветов трещин: растёт к настоящей редкости
local function hintSequence(finalTier: number): { number }
	local seq = {}
	for i = 1, HITS do
		seq[i] = math.max(1, math.ceil(finalTier * i / HITS))
	end
	if finalTier < 4 and math.random() < 0.35 then
		seq[HITS - 1] = finalTier + 1 -- «почти!»
	end
	return seq
end

local function makeGui(): (ScreenGui, TextButton, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Opening"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")
	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.new(0.5, 0, 1, -40)
	btn.Size = UDim2.fromOffset(240, 84)
	btn.BackgroundColor3 = Color3.fromRGB(255, 190, 70)
	btn.Font = Enum.Font.FredokaOne
	btn.TextSize = 40
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = "БЕЙ!"
	btn.AutoButtonColor = true
	btn.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 18)
	c.Parent = btn
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = Color3.fromRGB(150, 90, 20)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = btn
	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -132)
	hint.Size = UDim2.fromOffset(500, 36)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.FredokaOne
	hint.TextSize = 28
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.TextStrokeTransparency = 0.3
	hint.Text = "Расколи ядро! (клик или кнопка)"
	hint.Parent = gui
	return gui, btn, hint
end

local function crackPart(core: Model, size: number, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	-- модель уже увеличена — трещина в её текущем масштабе
	local k = core:GetScale()
	p.Size = Vector3.new(0.18, size * 1.02, size * (0.35 + math.random() * 0.3)) * k
	p.CFrame = core:GetPivot() * CFrame.Angles(math.random() * 6.3, math.random() * 6.3, math.random() * 6.3)
	p.Parent = core
	return p
end

local function reveal(r: Result, at: Vector3)
	local info = Config.RarityInfo[r.rarity]
	local tier = info.tier
	local item = ItemVisual.make(r.itemId, r.rarity, true)
	item:PivotTo(CFrame.new(at))
	item.Parent = Workspace
	item:ScaleTo(0.2)
	local t0 = os.clock()
	local spin = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local k = math.min(t / 0.45, 1)
		local back = 1 + 2.7 * (k - 1) ^ 3 + 1.7 * (k - 1) ^ 2
		item:ScaleTo(CORE_SCALE * math.max(0.2 + 0.8 * back, 0.05))
		item:PivotTo(CFrame.new(at + Vector3.new(0, 1.5 * k + math.sin(t * 3) * 0.3, 0)) * CFrame.Angles(0.3, t * 2.5, 0))
	end)
	-- подпись
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.Position = at + Vector3.new(0, 7, 0)
	anchor.Parent = Workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(420, 110)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = anchor
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.55)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = info.color
	title.TextStrokeTransparency = 0.1
	title.TextStrokeColor3 = Color3.fromRGB(40, 25, 70)
	title.Text = string.upper(info.name) .. ": " .. Config.ItemById[r.itemId].name .. (if tier >= 3 then "!!" else "")
	title.Parent = bb
	local sub = title:Clone()
	sub.Position = UDim2.fromScale(0, 0.58)
	sub.Size = UDim2.fromScale(1, 0.4)
	sub.TextColor3 = if r.isNew then Color3.fromRGB(140, 230, 255) else Color3.fromRGB(255, 215, 90)
	sub.Text = if r.isNew then "НОВОЕ в коллекции!" else "+" .. EconomyMath.formatNumber(r.coins) .. " монет"
	sub.Parent = bb
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = title
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	Effects.burst(at, info.color, 40 + tier * 35)
	Effects.flash(info.color, 0.15 + tier * 0.1)
	Effects.shake(0.15 + tier * 0.12, 0.3 + tier * 0.1)
	if tier == 1 then
		Effects.play("Pop", 0.6, 0.9)
	elseif tier == 2 then
		Effects.play("Rare", 0.8)
	else
		Effects.play("Epic", 0.9, if tier == 4 then 0.85 else 1)
		if tier == 4 then
			for i = 1, 4 do
				task.delay(0.25 * i, function()
					Effects.burst(at + Vector3.new(math.random(-3, 3), math.random(0, 3), math.random(-3, 3)), info.color, 50)
				end)
			end
		end
	end
	if r.isNew then
		task.delay(0.5, function()
			Effects.play("Rare", 0.6, 1.2)
		end)
	elseif r.coins > 0 then
		task.delay(0.6, function()
			Effects.play("Coins", 0.6)
		end)
	end
	task.wait(if tier >= 3 then 2.6 else 1.8)
	spin:Disconnect()
	anchor:Destroy()
	-- предмет улетает к игроку
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = item:GetPivot().Position
	local t1 = os.clock()
	while os.clock() - t1 < 0.35 do
		local k = (os.clock() - t1) / 0.35
		local target = if root then root.Position else from
		item:PivotTo(CFrame.new(from:Lerp(target, k * k)))
		item:ScaleTo(CORE_SCALE * math.max(1 - k * 0.9, 0.05))
		RunService.RenderStepped:Wait()
	end
	item:Destroy()
end

function Opening.play(r: Result)
	if busy then
		return
	end
	local altar = CollectionService:GetTagged("Altar")[1] :: BasePart?
	if not altar then
		RevealDone:FireServer()
		return
	end
	busy = true
	local h = altar:GetAttribute("CoreHeight")
	local at = Vector3.new(altar.Position.X, if type(h) == "number" then h else altar.Position.Y + 3, altar.Position.Z)
	local info = Config.Crystals[r.kind]
	local core = ItemVisual.core(r.zone, r.kind, true)
	core:PivotTo(CFrame.new(at))
	core.Parent = Workspace
	local heart = core:FindFirstChild("Heart") :: BasePart?
	local light = heart and heart:FindFirstChildOfClass("PointLight")
	local finalTier = Config.RarityInfo[r.rarity].tier
	local seq = hintSequence(finalTier)
	local hits = 0
	local lastHit = os.clock()
	local spinT = 0
	local punch = 0
	local spin = RunService.RenderStepped:Connect(function(dt: number)
		spinT += dt * (1 + hits * 0.8)
		punch = math.max(punch - dt * 4, 0)
		local wobble = punch * 0.35
		core:PivotTo(CFrame.new(at + Vector3.new((math.random() - 0.5) * wobble, math.sin(spinT * 2) * 0.25, (math.random() - 0.5) * wobble)) * CFrame.Angles(0, spinT, 0))
		core:ScaleTo(CORE_SCALE * (1 + punch * 0.18 + hits * 0.04))
	end)
	local gui, btn, hint = makeGui()
	local finished = false

	local function hit()
		if finished then
			return
		end
		hits += 1
		lastHit = os.clock()
		punch = 1
		local tierNow = seq[hits]
		local color = Config.RarityInfo[TIER_RARITY[tierNow]].color
		crackPart(core, info.coreSize, color)
		if heart then
			heart.Color = color
		end
		if light then
			light.Color = color
			light.Brightness = 2 + tierNow * 1.5
		end
		Effects.burst(at, color, 10 + tierNow * 8)
		Effects.play("Pop", 0.5, 0.9 + hits * 0.15)
		if tierNow >= 3 then
			Effects.play("Rare", 0.4, 0.8 + tierNow * 0.1)
		end
		Effects.shake(0.08 + tierNow * 0.04, 0.15)
		hint.Text = if hits < HITS then "Ещё! " .. hits .. "/" .. HITS else "..."
		hint.TextColor3 = color
		if hits >= HITS then
			finished = true
		end
	end

	local c1 = btn.Activated:Connect(hit)
	local c2 = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			hit()
		end
	end)
	-- не кликает — бьём сами, чтобы раскол не висел
	while not finished do
		task.wait(0.1)
		if os.clock() - lastHit > (if hits == 0 then 3 else 1.6) then
			hit()
		end
	end
	c1:Disconnect()
	c2:Disconnect()
	gui:Destroy()
	task.wait(0.35)
	spin:Disconnect()
	core:Destroy()
	reveal(r, at)
	RevealDone:FireServer()
	busy = false
	onDone(r)
end

return Opening
