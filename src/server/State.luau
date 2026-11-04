--!strict
-- Данные игрока на время сессии (сохранение — Шаг 4) и публикация их клиенту через атрибуты.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

export type BagItem = { id: string, rarity: Config.Rarity }

export type Session = {
	coins: number,
	levels: { [string]: number },
	bag: { BagItem },
	collection: { [string]: boolean },
	gates: { [number]: boolean },
	dropsSinceEpic: number,
	gotFirstDrop: boolean,
	lastClick: number,
	sourceClicks: { [Instance]: number },
	coinsStat: IntValue,
	collectionStat: IntValue,
}

local State = {}
local sessions: { [Player]: Session } = {}

function State.get(player: Player): Session?
	return sessions[player]
end

function State.level(s: Session, id: string): number
	return s.levels[id] or 0
end

function State.capacity(s: Session): number
	return Config.BaseCapacity + State.level(s, "Bag") * Config.CapacityPerLevel
end

function State.walkSpeed(s: Session): number
	return Config.BaseWalkSpeed + State.level(s, "Speed") * Config.SpeedPerLevel
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

function State.applySpeed(player: Player)
	local s = sessions[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if s and humanoid then
		humanoid.WalkSpeed = State.walkSpeed(s)
	end
end

-- Клиент читает всё из атрибутов игрока (только чтение, сервер — источник правды)
function State.publish(player: Player)
	local s = sessions[player]
	if not s then
		return
	end
	player:SetAttribute("Coins", s.coins)
	player:SetAttribute("BagCount", #s.bag)
	player:SetAttribute("Capacity", State.capacity(s))
	player:SetAttribute("IncomeMult", State.incomeMult(s))
	for _, u in Config.Upgrades do
		player:SetAttribute("Level_" .. u.id, State.level(s, u.id))
	end
	local keys = {}
	for k in s.collection do
		table.insert(keys, k)
	end
	player:SetAttribute("Collection", HttpService:JSONEncode(keys))
	local gates = {}
	for z in s.gates do
		table.insert(gates, z)
	end
	player:SetAttribute("Gates", HttpService:JSONEncode(gates))
	local counts = { Common = 0, Rare = 0, Epic = 0 }
	for _, item in s.bag do
		counts[item.rarity] += 1
	end
	player:SetAttribute("BagRare", counts.Rare + counts.Epic)
	s.coinsStat.Value = math.floor(s.coins)
	s.collectionStat.Value = State.collectionCount(s)
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coinsStat = Instance.new("IntValue")
	coinsStat.Name = "Монеты"
	coinsStat.Parent = leaderstats
	local collectionStat = Instance.new("IntValue")
	collectionStat.Name = "Коллекция"
	collectionStat.Parent = leaderstats
	leaderstats.Parent = player

	sessions[player] = {
		coins = 0,
		levels = {},
		bag = {},
		collection = {},
		gates = { [1] = true },
		dropsSinceEpic = 0,
		gotFirstDrop = false,
		lastClick = 0,
		sourceClicks = {},
		coinsStat = coinsStat,
		collectionStat = collectionStat,
	}
	State.publish(player)
	-- Только для тестов в Studio: сервер ставит атрибут StudioGrant = N → +N монет
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
	player.CharacterAdded:Connect(function()
		State.applySpeed(player)
	end)
	if player.Character then
		State.applySpeed(player)
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
