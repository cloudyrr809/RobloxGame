--!strict
-- Данные игрока на время сессии (сохранение — Шаг 4) и публикация их клиенту через атрибуты.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ItemVisual = require(ReplicatedStorage.Shared.ItemVisual)

export type Carry = {
	zone: number,
	kind: Config.CrystalKind,
	startedAt: number, -- os.clock()
}

export type Pending = {
	coins: number,
	key: string?,
	deadline: number,
}

export type RingRun = {
	last: number?,
	dir: number,
	count: number,
	lapStart: number,
}

export type Session = {
	coins: number,
	levels: { [string]: number },
	speedLevel: number,
	speedProgress: number,
	bestLap: number?,
	collection: { [string]: boolean },
	gates: { [number]: boolean },
	coresOpened: number,
	sinceEpic: number,
	sinceLegendary: number,
	carry: Carry?,
	pending: Pending?,
	crystalReady: { [Instance]: number },
	holdStart: { [Instance]: number },
	ring: RingRun,
	coinsStat: IntValue,
	collectionStat: IntValue,
	speedStat: IntValue,
}

local State = {}
local sessions: { [Player]: Session } = {}

function State.get(player: Player): Session?
	return sessions[player]
end

function State.level(s: Session, id: string): number
	return s.levels[id] or 0
end

function State.collectionCount(s: Session): number
	local n = 0
	for _ in s.collection do
		n += 1
	end
	return n
end

function State.incomeMult(s: Session): number
	return 1 + State.collectionCount(s) * Config.CollectionBonus
end

function State.walkSpeed(s: Session): number
	local v = Config.walkSpeed(s.speedLevel)
	if s.carry then
		v *= Config.CarrySpeedMult
	end
	return v
end

function State.root(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function State.applySpeed(player: Player)
	local s = sessions[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if s and humanoid then
		humanoid.WalkSpeed = State.walkSpeed(s)
	end
end

-- ядро над головой: видно и себе, и другим
function State.refreshCore(player: Player)
	local s = sessions[player]
	local character = player.Character
	if not s or not character then
		return
	end
	local old = character:FindFirstChild("CarriedCore")
	if old then
		old:Destroy()
	end
	local carry = s.carry
	local head = character:FindFirstChild("Head") :: BasePart?
	if not carry or not head then
		return
	end
	local model = ItemVisual.core(carry.zone, carry.kind, true)
	model.Name = "CarriedCore"
	local root = model.PrimaryPart :: BasePart
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	model:PivotTo(head.CFrame * CFrame.new(0, 3.2, 0))
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = root
	weld.Parent = root
	model.Parent = character
end

local function encode(set: { [any]: boolean }): string
	local keys = {}
	for k in set do
		table.insert(keys, k)
	end
	return HttpService:JSONEncode(keys)
end

-- Клиент читает всё из атрибутов игрока (только чтение, сервер — источник правды)
function State.publish(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	player:SetAttribute("Coins", s.coins)
	player:SetAttribute("IncomeMult", State.incomeMult(s))
	for _, u in Config.Upgrades do
		player:SetAttribute("Level_" .. u.id, State.level(s, u.id))
	end
	player:SetAttribute("SpeedLevel", s.speedLevel)
	player:SetAttribute("SpeedProgress", s.speedProgress)
	player:SetAttribute("SpeedNeed", Config.LapsPerLevel[s.speedLevel + 1] or 0)
	player:SetAttribute("BestLap", s.bestLap or 0)
	player:SetAttribute("Collection", encode(s.collection))
	player:SetAttribute("Gates", encode(s.gates))
	player:SetAttribute("CoresOpened", s.coresOpened)
	local carry = s.carry
	player:SetAttribute("CarryZone", if carry then carry.zone else 0)
	player:SetAttribute("CarryKind", if carry then carry.kind else "")
	player:SetAttribute("Pending", s.pending ~= nil)
	s.coinsStat.Value = math.floor(s.coins)
	s.collectionStat.Value = State.collectionCount(s)
	s.speedStat.Value = math.floor(Config.walkSpeed(s.speedLevel))
end

-- начать нести ядро: время старта для остывания — по часам сервера
function State.startCarry(player: Player, zone: number, kind: Config.CrystalKind)
	local s = sessions[player]
	if not s then
		return
	end
	s.carry = { zone = zone, kind = kind, startedAt = os.clock() }
	player:SetAttribute("CarryStart", Workspace:GetServerTimeNow())
	player:SetAttribute("HeatTime", Config.HeatTime[zone])
	State.refreshCore(player)
	State.applySpeed(player)
	State.publish(player)
end

function State.endCarry(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	s.carry = nil
	State.refreshCore(player)
	State.applySpeed(player)
	State.publish(player)
end

-- 0..1: насколько ядро ещё горячее
function State.heat(s: Session): number
	local carry = s.carry
	if not carry then
		return 0
	end
	return math.clamp(1 - (os.clock() - carry.startedAt) / Config.HeatTime[carry.zone], 0, 1)
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coinsStat = Instance.new("IntValue")
	coinsStat.Name = "Монеты"
	coinsStat.Parent = leaderstats
	local speedStat = Instance.new("IntValue")
	speedStat.Name = "Скорость"
	speedStat.Parent = leaderstats
	local collectionStat = Instance.new("IntValue")
	collectionStat.Name = "Коллекция"
	collectionStat.Parent = leaderstats
	leaderstats.Parent = player

	sessions[player] = {
		coins = 0,
		levels = {},
		speedLevel = 0,
		speedProgress = 0,
		bestLap = nil,
		collection = {},
		gates = { [1] = true },
		coresOpened = 0,
		sinceEpic = 0,
		sinceLegendary = 0,
		carry = nil,
		pending = nil,
		crystalReady = {},
		holdStart = {},
		ring = { last = nil, dir = 0, count = 0, lapStart = 0 },
		coinsStat = coinsStat,
		collectionStat = collectionStat,
		speedStat = speedStat,
	}
	State.publish(player)
	-- Только для тестов в Studio: атрибут StudioGrant = N → +N монет
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("StudioGrant"):Connect(function()
			local grant = player:GetAttribute("StudioGrant")
			local s = sessions[player]
			if s and type(grant) == "number" then
				s.coins += grant
				player:SetAttribute("StudioGrant", nil)
				State.publish(player)
			end
		end)
	end
	local function onCharacter(character: Model)
		character:WaitForChild("Head", 10)
		character:WaitForChild("Humanoid", 10)
		if player.Character ~= character then
			return
		end
		State.applySpeed(player)
		State.refreshCore(player) -- ядро не теряется после смерти
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

function State.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in Players:GetPlayers() do
		onPlayerAdded(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return State
