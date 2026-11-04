--!strict
-- База: раскол ядер на алтаре, улучшения, ворота зон, разгонное кольцо.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EconomyMath = require(ReplicatedStorage.Shared.EconomyMath)
local State = require(script.Parent.State)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenedRemote = Remotes:WaitForChild("Opened") :: RemoteEvent
local RevealDoneRemote = Remotes:WaitForChild("RevealDone") :: RemoteEvent
local LapRemote = Remotes:WaitForChild("Lap") :: RemoteEvent
local NoticeRemote = Remotes:WaitForChild("Notice") :: RemoteEvent
local BuyUpgradeRemote = Remotes:WaitForChild("BuyUpgrade") :: RemoteEvent

local rng = Random.new()
local Base = {}

local zoneItems: { { Config.ItemKind } } = {}
for z = 1, Config.ZoneCount do
	zoneItems[z] = {}
	for _, item in Config.Items do
		if item.zone == z then
			table.insert(zoneItems[z], item)
		end
	end
end

-- ===== Раскол ядра =====
local function rollRarity(s: State.Session, zone: number, kind: Config.CrystalKind, heat: number): Config.Rarity
	if s.coresOpened == 0 then
		return "Rare" -- награда в первые 30 секунд
	end
	if s.sinceLegendary + 1 >= Config.PityLegendary then
		return "Legendary"
	end
	if s.sinceEpic + 1 >= Config.PityEpic then
		return "Epic"
	end
	local _, rare, epic, leg = Config.odds(zone, State.level(s, "Luck"), kind, heat)
	local roll = rng:NextNumber() * 100
	if roll < leg then
		return "Legendary"
	elseif roll < leg + epic then
		return "Epic"
	elseif roll < leg + epic + rare then
		return "Rare"
	end
	return "Common"
end

local function applyPending(player: Player)
	local s = State.get(player)
	local p = s and s.pending
	if not s or not p then
		return
	end
	s.pending = nil
	s.coins += p.coins
	if p.key then
		s.collection[p.key] = true
	end
	State.publish(player)
end

local function onCrack(player: Player, altarPos: Vector3)
	local s = State.get(player)
	if not s then
		return
	end
	local carry = s.carry
	if not carry then
		NoticeRemote:FireClient(player, "Сначала добудь ядро из кристалла")
		return
	end
	if s.pending then
		return
	end
	local root = State.root(player)
	if not root or (root.Position - altarPos).Magnitude > Config.AltarRange then
		return
	end
	local heat = State.heat(s)
	local rarity = rollRarity(s, carry.zone, carry.kind, heat)
	local list = zoneItems[carry.zone]
	local item = if #list == 1 or rng:NextNumber() < 0.6 then list[1] else list[2]
	s.coresOpened += 1
	s.sinceEpic = if rarity == "Epic" or rarity == "Legendary" then 0 else s.sinceEpic + 1
	s.sinceLegendary = if rarity == "Legendary" then 0 else s.sinceLegendary + 1

	local key = Config.collectionKey(item.id, rarity :: any)
	local isNew = rarity ~= "Common" and not s.collection[key]
	local coins = 0
	if not isNew then
		coins = math.floor(item.value * Config.RarityInfo[rarity].sellMult * State.incomeMult(s) + 0.5)
	end
	-- награда выдаётся, когда игрок досмотрел раскол (или по таймеру)
	s.pending = { coins = coins, key = if isNew then key else nil, deadline = os.clock() + Config.RevealTimeout }
	local zone, kind = carry.zone, carry.kind
	State.endCarry(player)
	OpenedRemote:FireClient(player, {
		zone = zone,
		kind = kind,
		itemId = item.id,
		rarity = rarity,
		coins = coins,
		isNew = isNew,
		heat = heat,
	})
	local pending = s.pending
	task.delay(Config.RevealTimeout, function()
		local now = State.get(player)
		if now and now.pending == pending then
			applyPending(player)
		end
	end)
end

-- ===== Улучшения =====
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
	State.publish(player)
end

-- ===== Ворота =====
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

-- ===== Разгонное кольцо: арки по порядку, полный круг = прогресс скорости =====
local function awardLap(player: Player, s: State.Session, lapTime: number)
	local record = s.bestLap == nil or lapTime < (s.bestLap :: number)
	local beatGhost = record and s.bestLap ~= nil
	if record then
		s.bestLap = lapTime
	end
	local leveled = false
	if s.speedLevel < Config.SpeedMaxLevel then
		s.speedProgress += 1 + (if beatGhost then Config.RecordBonusLaps else 0)
		while s.speedLevel < Config.SpeedMaxLevel and s.speedProgress >= Config.LapsPerLevel[s.speedLevel + 1] do
			s.speedProgress -= Config.LapsPerLevel[s.speedLevel + 1]
			s.speedLevel += 1
			leveled = true
		end
		if s.speedLevel >= Config.SpeedMaxLevel then
			s.speedProgress = 0
		end
	end
	State.applySpeed(player)
	State.publish(player)
	LapRemote:FireClient(player, lapTime, s.bestLap, beatGhost, leveled)
end

local function startRing()
	local gates: { BasePart } = {}
	for _, m in CollectionService:GetTagged("RingGate") do
		local i = m:GetAttribute("Index")
		if m:IsA("BasePart") and type(i) == "number" then
			gates[i] = m
		end
	end
	local n = #gates
	if n < 3 then
		warn("Разгонное кольцо: нет арок")
		return
	end
	local ringLength = 0
	for i = 1, n do
		ringLength += (gates[i].Position - gates[i % n + 1].Position).Magnitude
	end
	task.spawn(function()
		while true do
			task.wait(0.1)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local s = State.get(player)
				local root = State.root(player)
				if not s or not root then
					continue
				end
				local at: number? = nil
				for i, g in gates do
					local d = root.Position - g.Position
					if Vector2.new(d.X, d.Z).Magnitude < Config.RingGateRadius and math.abs(d.Y) < 9 then
						at = i
						break
					end
				end
				local run = s.ring
				if not at or at == run.last then
					continue
				end
				local g = at :: number
				local last = run.last
				local step = if last then (if (g - last) % n == 1 then 1 elseif (g - last) % n == n - 1 then -1 else 0) else 0
				if step == 0 or (run.dir ~= 0 and step ~= run.dir) then
					-- начали заново (пропуск арки или развернулись)
					run.last, run.dir, run.count, run.lapStart = g, 0, 0, now
					continue
				end
				run.dir = step
				run.last = g
				run.count += 1
				if run.count >= n then
					local lapTime = now - run.lapStart
					run.count = 0
					run.lapStart = now
					-- быстрее, чем можно пробежать, — не засчитываем (телепорт)
					if lapTime >= ringLength / (State.walkSpeed(s) * 1.4) then
						awardLap(player, s, lapTime)
					end
				end
			end
		end
	end)
end

function Base.start()
	BuyUpgradeRemote.OnServerEvent:Connect(onBuyUpgrade)
	RevealDoneRemote.OnServerEvent:Connect(function(player: Player)
		applyPending(player)
	end)
	for _, altar in CollectionService:GetTagged("Altar") do
		local prompt = altar.Parent and altar.Parent:FindFirstChild("Crack", true) :: ProximityPrompt?
		if altar:IsA("BasePart") and prompt then
			local pos = altar.Position
			prompt.Triggered:Connect(function(player: Player)
				onCrack(player, pos)
			end)
		end
	end
	for _, gate in CollectionService:GetTagged("Gate") do
		bindGate(gate)
	end
	startRing()
end

return Base
