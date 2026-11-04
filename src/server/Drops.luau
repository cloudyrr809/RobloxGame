--!strict
-- Источники: клик → проверка → случайный предмет в рюкзак → клиенту событие Drop.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DropRemote = Remotes:WaitForChild("Drop") :: RemoteEvent
local NoticeRemote = Remotes:WaitForChild("Notice") :: RemoteEvent

local rng = Random.new()

local Drops = {}

local function itemsOfZone(zone: number): { Config.ItemKind }
	local list = {}
	for _, item in Config.Items do
		if item.zone == zone then
			table.insert(list, item)
		end
	end
	return list
end

local zoneItems: { { Config.ItemKind } } = {}
for z = 1, Config.ZoneCount do
	zoneItems[z] = itemsOfZone(z)
end

local function rollRarity(s: State.Session, zone: number): Config.Rarity
	if not s.gotFirstDrop then
		return "Rare" -- награда в первые 30 секунд
	end
	if s.dropsSinceEpic + 1 >= Config.PityEpic then
		return "Epic"
	end
	local _, rare, epic = Config.odds(zone, State.level(s, "Luck"))
	local roll = rng:NextNumber() * 100
	if roll < epic then
		return "Epic"
	elseif roll < epic + rare then
		return "Rare"
	end
	return "Common"
end

-- Дешёвый предмет зоны выпадает чаще (60/40)
local function rollItem(zone: number): Config.ItemKind
	local list = zoneItems[zone]
	if #list == 1 or rng:NextNumber() < 0.6 then
		return list[1]
	end
	return list[2]
end

local function onClick(player: Player, source: Model)
	local s = State.get(player)
	if not s then
		return
	end
	local zone = source:GetAttribute("Zone")
	if type(zone) ~= "number" or not zoneItems[zone] then
		return
	end
	local now = os.clock()
	if now - s.lastClick < Config.GlobalClickCooldown then
		return
	end
	local last = s.sourceClicks[source] or 0
	if now - last < Config.SourceCooldown then
		return
	end
	if not s.gates[zone] then
		NoticeRemote:FireClient(player, "Зона закрыта — открой ворота")
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pivot = source:GetPivot().Position
	if not root or (root.Position - pivot).Magnitude > Config.ClickRange then
		return
	end
	if #s.bag >= State.capacity(s) then
		NoticeRemote:FireClient(player, "Рюкзак полон! Неси на базу")
		return
	end

	s.lastClick = now
	s.sourceClicks[source] = now
	local rarity = rollRarity(s, zone)
	local item = rollItem(zone)
	s.gotFirstDrop = true
	if rarity == "Epic" then
		s.dropsSinceEpic = 0
	else
		s.dropsSinceEpic += 1
	end
	local entry: State.BagItem = { id = item.id, rarity = rarity :: Config.Rarity }
	table.insert(s.bag, entry)
	State.publish(player)
	DropRemote:FireClient(player, source, item.id, rarity)
end

local function bind(source: Instance)
	if not source:IsA("Model") then
		return
	end
	local detector = source:FindFirstChildOfClass("ClickDetector")
	if not detector then
		warn("Source без ClickDetector:", source:GetFullName())
		return
	end
	detector.MouseClick:Connect(function(player: Player)
		onClick(player, source)
	end)
end

function Drops.start()
	for _, src in CollectionService:GetTagged("Source") do
		bind(src)
	end
	CollectionService:GetInstanceAddedSignal("Source"):Connect(bind)
end

return Drops
