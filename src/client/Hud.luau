--!strict
-- Интерфейс: монеты, рюкзак, подсказки, панели «Улучшения» и «Коллекция».
-- Всё читается из атрибутов игрока, которые ставит сервер.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local EconomyMath = require(ReplicatedStorage.Shared.EconomyMath)
local ItemVisual = require(ReplicatedStorage.Shared.ItemVisual)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BuyUpgrade = Remotes:WaitForChild("BuyUpgrade") :: RemoteEvent

local player = Players.LocalPlayer
local fmt = EconomyMath.formatNumber

-- ===== Токены оформления =====
local FONT = Enum.Font.FredokaOne
local C = {
	panel = Color3.fromRGB(40, 30, 70),
	panelLight = Color3.fromRGB(62, 48, 102),
	text = Color3.fromRGB(255, 255, 255),
	muted = Color3.fromRGB(190, 180, 220),
	gold = Color3.fromRGB(255, 205, 90),
	goldDark = Color3.fromRGB(200, 140, 40),
	green = Color3.fromRGB(105, 215, 135),
	disabled = Color3.fromRGB(95, 88, 120),
	cyan = Color3.fromRGB(110, 215, 255),
	danger = Color3.fromRGB(255, 120, 110),
}

local function corner(parent: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function stroke(parent: GuiObject, color: Color3, thickness: number, transparency: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function label(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color or C.text
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.Parent = parent
	return l
end

local function panelFrame(name: string, size: UDim2): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.BackgroundColor3 = C.panel
	f.BackgroundTransparency = 0.08
	f.BorderSizePixel = 0
	corner(f, 14)
	stroke(f, Color3.new(1, 1, 1), 2, 0.82)
	return f
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Font = FONT
	b.Text = text
	b.TextSize = 20
	b.TextColor3 = C.text
	b.Parent = parent
	corner(b, 10)
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(0, 0, 0)
	s.Transparency = 0.6
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	local quick = TweenInfo.new(0.08)
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, quick, { Scale = 1.04 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, quick, { Scale = 1 }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, quick, { Scale = 0.95 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, quick, { Scale = 1 }):Play()
	end)
	return b
end

local function bump(obj: GuiObject)
	local sc = obj:FindFirstChildOfClass("UIScale")
	if sc == nil then
		local created = Instance.new("UIScale")
		created.Parent = obj
		sc = created
	end
	assert(sc, "UIScale")
	sc.Scale = 1.15
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function attrNumber(name: string): number
	local v = player:GetAttribute(name)
	return if type(v) == "number" then v else 0
end

local function collectionSet(): { [string]: boolean }
	local raw = player:GetAttribute("Collection")
	local set: { [string]: boolean } = {}
	if type(raw) == "string" then
		local ok, list = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and type(list) == "table" then
			for _, k in list do
				set[k] = true
			end
		end
	end
	return set
end

local function gatesSet(): { [number]: boolean }
	local raw = player:GetAttribute("Gates")
	local set: { [number]: boolean } = {}
	if type(raw) == "string" then
		local ok, list = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and type(list) == "table" then
			for _, z in list do
				set[z] = true
			end
		end
	end
	return set
end

local Hud = {}

local noticeFn: (string) -> () = function(_text: string) end
local soldFn: (number, number) -> () = function(_earned: number, _soldCount: number) end

function Hud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = player:WaitForChild("PlayerGui")

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
	local function rescale()
		local vp = Workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 760), 0.6, 1.25)
	end
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	-- ===== Монеты =====
	local coins = panelFrame("Coins", UDim2.fromOffset(240, 56))
	coins.AnchorPoint = Vector2.new(0.5, 0)
	coins.Position = UDim2.new(0.5, 0, 0, 10)
	coins.Parent = gui
	local coinIcon = Instance.new("Frame")
	coinIcon.Size = UDim2.fromOffset(34, 34)
	coinIcon.Position = UDim2.fromOffset(14, 11)
	coinIcon.BackgroundColor3 = C.gold
	coinIcon.Parent = coins
	corner(coinIcon, 17)
	stroke(coinIcon, C.goldDark, 3, 0)
	local coinShine = Instance.new("Frame")
	coinShine.Size = UDim2.fromOffset(10, 10)
	coinShine.Position = UDim2.fromOffset(7, 6)
	coinShine.BackgroundColor3 = Color3.new(1, 1, 1)
	coinShine.BackgroundTransparency = 0.3
	coinShine.Parent = coinIcon
	corner(coinShine, 5)
	local coinText = label(coins, "0", 32)
	coinText.TextXAlignment = Enum.TextXAlignment.Left
	coinText.Position = UDim2.fromOffset(60, 6)
	coinText.Size = UDim2.new(1, -70, 0, 32)
	local multText = label(coins, "доход ×1.00", 14, C.muted)
	multText.TextXAlignment = Enum.TextXAlignment.Left
	multText.Position = UDim2.fromOffset(61, 36)
	multText.Size = UDim2.new(1, -70, 0, 14)

	-- ===== Подсказка =====
	local hint = panelFrame("Hint", UDim2.fromOffset(420, 40))
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 74)
	hint.BackgroundColor3 = C.panelLight
	hint.Parent = gui
	local hintText = label(hint, "", 20, C.gold)
	hintText.Size = UDim2.fromScale(1, 1)

	-- ===== Сообщение (рюкзак полон и т.п.) =====
	local notice = label(gui, "", 26, C.danger)
	notice.AnchorPoint = Vector2.new(0.5, 0)
	notice.Position = UDim2.new(0.5, 0, 0, 124)
	notice.Size = UDim2.fromOffset(600, 32)
	notice.TextStrokeTransparency = 0.3
	notice.TextStrokeColor3 = Color3.fromRGB(40, 20, 40)
	notice.TextTransparency = 1
	notice.TextStrokeTransparency = 1

	-- ===== Рюкзак =====
	local bag = panelFrame("Bag", UDim2.fromOffset(210, 84))
	bag.AnchorPoint = Vector2.new(0, 0.5)
	bag.Position = UDim2.new(0, 14, 0.45, 0)
	bag.Parent = gui
	local bagTitle = label(bag, "Рюкзак", 18, C.muted)
	bagTitle.TextXAlignment = Enum.TextXAlignment.Left
	bagTitle.Position = UDim2.fromOffset(14, 8)
	bagTitle.Size = UDim2.new(1, -28, 0, 20)
	local bagCount = label(bag, "0/10", 26)
	bagCount.TextXAlignment = Enum.TextXAlignment.Right
	bagCount.Position = UDim2.fromOffset(14, 4)
	bagCount.Size = UDim2.new(1, -28, 0, 28)
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromOffset(14, 40)
	barBack.Size = UDim2.new(1, -28, 0, 16)
	barBack.BackgroundColor3 = Color3.fromRGB(25, 18, 45)
	barBack.BorderSizePixel = 0
	barBack.Parent = bag
	corner(barBack, 8)
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = C.green
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	corner(barFill, 8)
	local bagRare = label(bag, "", 15, C.cyan)
	bagRare.TextXAlignment = Enum.TextXAlignment.Left
	bagRare.Position = UDim2.fromOffset(14, 60)
	bagRare.Size = UDim2.new(1, -28, 0, 16)

	-- ===== Кнопки справа =====
	local side = Instance.new("Frame")
	side.Name = "Side"
	side.AnchorPoint = Vector2.new(1, 0.5)
	side.Position = UDim2.new(1, -14, 0.45, 0)
	side.Size = UDim2.fromOffset(170, 130)
	side.BackgroundTransparency = 1
	side.Parent = gui
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.Parent = side
	local upgradesBtn = button(side, "Улучшения", C.goldDark, UDim2.fromOffset(170, 56))
	local collectionBtn = button(side, "Коллекция", Color3.fromRGB(60, 130, 200), UDim2.fromOffset(170, 56))
	local badge = Instance.new("TextLabel")
	badge.Size = UDim2.fromOffset(26, 26)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromOffset(4, 4)
	badge.BackgroundColor3 = C.danger
	badge.Font = FONT
	badge.Text = "!"
	badge.TextSize = 18
	badge.TextColor3 = C.text
	badge.Visible = false
	badge.Parent = upgradesBtn
	corner(badge, 13)

	-- ===== Модальные панели =====
	local openPanel: Frame? = nil
	local openedAt: Vector3? = nil
	local function rootPosition(): Vector3?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		return root and root.Position
	end
	local function setPanel(p: Frame?)
		if openPanel and openPanel ~= p then
			openPanel.Visible = false
		end
		openPanel = p
		openedAt = rootPosition()
		if p then
			p.Visible = true
			bump(p)
		end
	end
	-- панель закрывается сама, если игрок ушёл (иначе она мешает кликать по кристаллам)
	task.spawn(function()
		while true do
			task.wait(0.3)
			local here = rootPosition()
			if openPanel and openedAt and here and (here - openedAt).Magnitude > 14 then
				setPanel(nil)
			end
		end
	end)

	local function modal(name: string, title: string, size: UDim2): (Frame, Frame, TextLabel)
		local p = panelFrame(name, size)
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(0.5, 0.52)
		p.Visible = false
		p.ZIndex = 5
		p.Parent = gui
		local head = label(p, title, 30, C.gold)
		head.Position = UDim2.fromOffset(0, 14)
		local close = button(p, "X", C.danger, UDim2.fromOffset(40, 40))
		close.AnchorPoint = Vector2.new(1, 0)
		close.Position = UDim2.new(1, -12, 0, 12)
		close.Activated:Connect(function()
			setPanel(nil)
		end)
		local body = Instance.new("Frame")
		body.BackgroundTransparency = 1
		body.Position = UDim2.fromOffset(20, 74)
		body.Size = UDim2.new(1, -40, 1, -90)
		body.Parent = p
		return p, body, head
	end

	-- Улучшения
	local upPanel, upBody = modal("Upgrades", "Улучшения", UDim2.fromOffset(520, 380))
	local upList = Instance.new("UIListLayout")
	upList.Padding = UDim.new(0, 10)
	upList.Parent = upBody
	type Row = { up: Config.Upgrade, level: TextLabel, buy: TextButton, effect: TextLabel }
	local rows: { Row } = {}
	for _, up in Config.Upgrades do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 88)
		row.BackgroundColor3 = C.panelLight
		row.BorderSizePixel = 0
		row.Parent = upBody
		corner(row, 12)
		local name = label(row, up.name, 24)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(16, 10)
		name.Size = UDim2.new(0.6, 0, 0, 26)
		local lvl = label(row, "", 16, C.muted)
		lvl.TextXAlignment = Enum.TextXAlignment.Left
		lvl.Position = UDim2.fromOffset(16, 38)
		lvl.Size = UDim2.new(0.6, 0, 0, 18)
		local eff = label(row, up.description, 15, C.cyan)
		eff.TextXAlignment = Enum.TextXAlignment.Left
		eff.Position = UDim2.fromOffset(16, 60)
		eff.Size = UDim2.new(0.62, 0, 0, 18)
		local buy = button(row, "", C.green, UDim2.fromOffset(150, 56))
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, -16, 0.5, 0)
		buy.Activated:Connect(function()
			BuyUpgrade:FireServer(up.id)
		end)
		table.insert(rows, { up = up, level = lvl, buy = buy, effect = eff })
	end

	local function effectNow(id: string, level: number): string
		if id == "Speed" then
			return "скорость " .. (Config.BaseWalkSpeed + level * Config.SpeedPerLevel)
		elseif id == "Bag" then
			return "мест " .. (Config.BaseCapacity + level * Config.CapacityPerLevel)
		else
			return "шанс ×" .. string.format("%.1f", 1 + level * Config.LuckPerLevel)
		end
	end

	local function refreshUpgrades()
		local money = attrNumber("Coins")
		local anyAffordable = false
		for _, r in rows do
			local level = attrNumber("Level_" .. r.up.id)
			r.level.Text = "Ур. " .. level .. "/" .. r.up.maxLevel .. " · сейчас " .. effectNow(r.up.id, level)
			if level >= r.up.maxLevel then
				r.buy.Text = "МАКС"
				r.buy.BackgroundColor3 = C.disabled
			else
				local price = EconomyMath.levelCost(r.up.baseCost, r.up.costGrowth, level)
				r.buy.Text = fmt(price) .. " ◉"
				local can = money >= price
				r.buy.BackgroundColor3 = if can then C.green else C.disabled
				anyAffordable = anyAffordable or can
			end
		end
		badge.Visible = anyAffordable
	end

	-- Коллекция
	local colPanel, colBody, colHead = modal("Collection", "Коллекция", UDim2.fromOffset(600, 510))
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(128, 92)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = colBody
	local colInfo = label(colPanel, "", 16, C.muted)
	colInfo.Position = UDim2.fromOffset(0, 46)
	type Cell = { key: string, vp: ViewportFrame, name: TextLabel, model: Model, frame: Frame, rarity: Config.Rarity, itemName: string }
	local cells: { Cell } = {}
	local order = 0
	for _, item in Config.Items do
		local rarities: { Config.Rarity } = { "Rare", "Epic" }
		for _, rarity in rarities do
			order += 1
			local info = Config.RarityInfo[rarity]
			local cell = Instance.new("Frame")
			cell.BackgroundColor3 = C.panelLight
			cell.BorderSizePixel = 0
			cell.LayoutOrder = order
			cell.Parent = colBody
			corner(cell, 10)
			stroke(cell, info.color, 2, 0.4)
			local vp = Instance.new("ViewportFrame")
			vp.BackgroundTransparency = 1
			vp.Size = UDim2.new(1, 0, 1, -22)
			vp.Ambient = Color3.fromRGB(200, 200, 220)
			vp.LightColor = Color3.new(1, 1, 1)
			vp.LightDirection = Vector3.new(-1, -1, -1)
			vp.Parent = cell
			local cam = Instance.new("Camera")
			cam.FieldOfView = 40
			cam.CFrame = CFrame.lookAt(Vector3.new(0, 2, 8), Vector3.zero)
			cam.Parent = vp
			vp.CurrentCamera = cam
			local model = ItemVisual.make(item.id, rarity :: Config.Rarity, false)
			model.Parent = vp
			local n = label(cell, "", 14)
			n.Position = UDim2.new(0, 0, 1, -20)
			n.Size = UDim2.new(1, 0, 0, 18)
			table.insert(cells, { key = Config.collectionKey(item.id, rarity :: Config.Rarity), vp = vp, name = n, model = model, frame = cell, rarity = rarity :: Config.Rarity, itemName = item.name })
		end
	end

	local function refreshCollection()
		local set = collectionSet()
		local have = 0
		for _, c in cells do
			local got = set[c.key] == true
			if got then
				have += 1
			end
			c.vp.ImageColor3 = if got then Color3.new(1, 1, 1) else Color3.fromRGB(20, 14, 36)
			c.name.Text = if got then c.itemName .. " · " .. Config.RarityInfo[c.rarity].name else "???"
			c.name.TextColor3 = if got then Config.RarityInfo[c.rarity].color else C.muted
		end
		colHead.Text = "Коллекция " .. have .. "/" .. #cells
		colInfo.Text = "Каждый слот: +" .. math.floor(Config.CollectionBonus * 100) .. "% к доходу навсегда · сейчас +" .. math.floor(have * Config.CollectionBonus * 100 + 0.5) .. "%"
	end

	RunService.RenderStepped:Connect(function()
		if openPanel == colPanel then
			local t = os.clock()
			for i, c in cells do
				c.model:PivotTo(CFrame.Angles(0.3, t * 0.9 + i, 0))
			end
		end
	end)

	upgradesBtn.Activated:Connect(function()
		setPanel(if openPanel == upPanel then nil else upPanel)
	end)
	collectionBtn.Activated:Connect(function()
		setPanel(if openPanel == colPanel then nil else colPanel)
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player or prompt.Name ~= "Open" then
			return
		end
		local station = prompt:FindFirstAncestorWhichIsA("Model")
		if station and station.Name == "UpgradeStation" then
			setPanel(upPanel)
		elseif station and station.Name == "CollectionStation" then
			setPanel(colPanel)
		end
	end)

	-- ===== Подсказки для новичка =====
	local tutorial = 1
	local function refreshHint()
		local text = ""
		if tutorial == 1 then
			text = "Кликай по кристаллам на дорожке!"
		elseif tutorial == 2 then
			text = "Набери рюкзак и вернись на базу"
		elseif tutorial == 3 then
			text = "Купи улучшение — жёлтая кнопка справа"
		else
			local gates = gatesSet()
			for z = 2, Config.ZoneCount do
				if not gates[z] then
					if attrNumber("Coins") >= Config.GatePrices[z] then
						text = "Хватает на ворота: " .. Config.ZoneNames[z] .. " зона!"
					end
					break
				end
			end
		end
		hintText.Text = text
		hint.Visible = text ~= ""
		if text ~= "" then
			hint.Size = UDim2.fromOffset(math.max(260, (utf8.len(text) or #text) * 10 + 48), 40)
		end
	end

	-- ===== Обновление из атрибутов =====
	local shownCoins = attrNumber("Coins")
	local targetCoins = shownCoins
	RunService.Heartbeat:Connect(function(dt: number)
		if shownCoins ~= targetCoins then
			local diff = targetCoins - shownCoins
			local step = math.max(math.abs(diff) * math.min(dt * 8, 1), 1)
			if math.abs(diff) <= step then
				shownCoins = targetCoins
			else
				shownCoins += math.sign(diff) * step
			end
			coinText.Text = fmt(math.floor(shownCoins))
		end
	end)

	local function refreshCoins()
		local v = attrNumber("Coins")
		if v > targetCoins then
			bump(coins)
		end
		targetCoins = v
		multText.Text = "доход ×" .. string.format("%.2f", math.max(attrNumber("IncomeMult"), 1))
		refreshUpgrades()
		refreshHint()
	end

	local pulse: Tween? = nil
	local function refreshBag()
		local count = attrNumber("BagCount")
		local cap = math.max(attrNumber("Capacity"), 1)
		bagCount.Text = count .. "/" .. cap
		local full = count >= cap
		TweenService:Create(barFill, TweenInfo.new(0.15), { Size = UDim2.fromScale(math.clamp(count / cap, 0, 1), 1) }):Play()
		barFill.BackgroundColor3 = if full then C.danger elseif count / cap > 0.7 then C.gold else C.green
		bagTitle.Text = if full then "Рюкзак ПОЛОН" else "Рюкзак"
		bagTitle.TextColor3 = if full then C.danger else C.muted
		local rare = attrNumber("BagRare")
		bagRare.Text = if rare > 0 then "★ редких: " .. rare else ""
		if full and not pulse then
			local t = TweenService:Create(bag, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundColor3 = Color3.fromRGB(110, 40, 70) })
			t:Play()
			pulse = t
		elseif not full and pulse then
			pulse:Cancel()
			pulse = nil
			bag.BackgroundColor3 = C.panel
		end
		if count > 0 and tutorial == 1 then
			tutorial = 2
			refreshHint()
		end
	end

	player:GetAttributeChangedSignal("Coins"):Connect(refreshCoins)
	player:GetAttributeChangedSignal("IncomeMult"):Connect(refreshCoins)
	player:GetAttributeChangedSignal("BagCount"):Connect(refreshBag)
	player:GetAttributeChangedSignal("Capacity"):Connect(refreshBag)
	player:GetAttributeChangedSignal("Collection"):Connect(refreshCollection)
	player:GetAttributeChangedSignal("Gates"):Connect(refreshHint)
	for _, up in Config.Upgrades do
		player:GetAttributeChangedSignal("Level_" .. up.id):Connect(function()
			refreshUpgrades()
			if tutorial == 3 then
				tutorial = 4
				refreshHint()
			end
		end)
	end
	refreshCoins()
	refreshBag()
	refreshCollection()
	refreshHint()
	coinText.Text = fmt(math.floor(shownCoins))

	-- ===== Публичные функции для других модулей =====
	local noticeToken = 0
	noticeFn = function(text: string)
		noticeToken += 1
		local my = noticeToken
		notice.Text = text
		notice.TextTransparency = 0
		notice.TextStrokeTransparency = 0.3
		bump(notice)
		task.delay(1.8, function()
			if my == noticeToken then
				TweenService:Create(notice, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end)
	end

	soldFn = function(earned: number, soldCount: number)
		if earned <= 0 then
			return
		end
		local big = label(gui, "+" .. fmt(earned) .. " монет", 54, C.gold)
		big.AnchorPoint = Vector2.new(0.5, 0.5)
		big.Position = UDim2.fromScale(0.5, 0.38)
		big.Size = UDim2.fromOffset(600, 60)
		big.TextStrokeTransparency = 0.2
		big.TextStrokeColor3 = Color3.fromRGB(110, 60, 10)
		local sub = label(big, "продано предметов: " .. soldCount, 20, C.text)
		sub.Position = UDim2.fromScale(0, 1)
		sub.TextStrokeTransparency = 0.4
		bump(big)
		TweenService:Create(big, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.3) }):Play()
		task.delay(1.1, function()
			TweenService:Create(big, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(sub, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end)
		task.delay(1.7, function()
			big:Destroy()
		end)
		if tutorial <= 2 then
			tutorial = 3
			refreshHint()
		end
	end
end

function Hud.notice(text: string)
	noticeFn(text)
end

function Hud.sold(earned: number, soldCount: number)
	soldFn(earned, soldCount)
end

return Hud
