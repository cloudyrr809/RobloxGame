--!strict
-- База: авто-продажа и коллекция при входе, улучшения, ворота зон.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EconomyMath = require(ReplicatedStorage.Shared.EconomyMath)
local State = require(script.Parent.State)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SoldRemote = Remotes:WaitForChild("Sold") :: RemoteEvent
local NoticeRemote = Remotes:WaitForChild("Notice") :: RemoteEvent
local BuyUpgradeRemote = Remotes:WaitForChild("BuyUpgrade") :: RemoteEvent

local Base = {}

local function sellBag(player: Player, s: State.Session)
	if #s.bag == 0 then
		return
	end
	local mult = State.incomeMult(s)
	local earned = 0
	local sold = 0
	local newKeys = {}
	for _, item in s.bag do
		local kind = Config.ItemById[item.id]
		local key = Config.collectionKey(item.id, item.rarity)
		if item.rarity ~= "Common" and not s.collection[key] then
			s.collection[key] = true
			table.insert(newKeys, key)
		else
			earned += kind.value * Config.RarityInfo[item.rarity].sellMult
			sold += 1
		end
	end
	-- новые слоты коллекции сразу повышают множитель
	earned = math.floor(earned * mult + 0.5)
	s.coins += earned
	s.bag = {}
	State.publish(player)
	SoldRemote:FireClient(player, earned, sold, newKeys)
end

local function startSellLoop(floor: BasePart)
	local radius = floor:GetAttribute("Radius")
	local r = if type(radius) == "number" then radius else 45
	local center = floor.Position
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				local s = State.get(player)
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if s and root and #s.bag > 0 then
					local d = root.Position - center
					if Vector2.new(d.X, d.Z).Magnitude < r and d.Y > -2 and d.Y < 20 then
						sellBag(player, s)
					end
				end
			end
		end
	end)
end

local function onBuyUpgrade(player: Player, upgradeId: unknown)
	local s = State.get(player)
	if not s or type(upgradeId) ~= "string" then
		return
	end
	local upgrade = Config.UpgradeById[upgradeId]
	if not upgrade then
		return
	end
	local owned = State.level(s, upgrade.id)
	if owned >= upgrade.maxLevel then
		return
	end
	local price = EconomyMath.levelCost(upgrade.baseCost, upgrade.costGrowth, owned)
	local wallet = { coins = s.coins }
	if not EconomyMath.trySpend(wallet, { coins = price }) then
		NoticeRemote:FireClient(player, "Не хватает монет")
		return
	end
	s.coins = wallet.coins
	s.levels[upgrade.id] = owned + 1
	State.applySpeed(player)
	State.publish(player)
end

local function bindGate(gate: Instance)
	local zone = gate:GetAttribute("Zone")
	local barrier = gate:FindFirstChild("Barrier")
	local prompt = barrier and barrier:FindFirstChildOfClass("ProximityPrompt")
	if type(zone) ~= "number" or not prompt then
		warn("Ворота настроены неверно:", gate:GetFullName())
		return
	end
	prompt.Triggered:Connect(function(player: Player)
		local s = State.get(player)
		if not s or s.gates[zone] then
			return
		end
		if not s.gates[zone - 1] then
			NoticeRemote:FireClient(player, "Сначала открой предыдущую зону")
			return
		end
		local price = Config.GatePrices[zone]
		if s.coins < price then
			NoticeRemote:FireClient(player, "Нужно " .. EconomyMath.formatNumber(price) .. " монет")
			return
		end
		s.coins -= price
		s.gates[zone] = true
		State.publish(player)
	end)
end

function Base.start()
	BuyUpgradeRemote.OnServerEvent:Connect(onBuyUpgrade)
	for _, floor in CollectionService:GetTagged("BaseFloor") do
		if floor:IsA("BasePart") then
			startSellLoop(floor)
		end
	end
	for _, gate in CollectionService:GetTagged("Gate") do
		bindGate(gate)
	end
end

return Base
