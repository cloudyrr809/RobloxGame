--!strict
-- Все числа игры в одном месте. Сервер и клиент читают одну таблицу.

export type Rarity = "Common" | "Rare" | "Epic"

export type ItemKind = {
	id: string,
	name: string,
	zone: number,
	value: number, -- цена обычного
	shape: string, -- как клиент рисует предмет
	color: Color3,
}

export type Upgrade = {
	id: string,
	name: string,
	description: string,
	baseCost: number,
	costGrowth: number,
	maxLevel: number,
}

local Config = {}

Config.Items = {
	{ id = "Ball", name = "Шарик", zone = 1, value = 1, shape = "Ball", color = Color3.fromRGB(255, 170, 200) },
	{ id = "Cube", name = "Кубик", zone = 1, value = 2, shape = "Block", color = Color3.fromRGB(140, 230, 190) },
	{ id = "Disc", name = "Шайба", zone = 2, value = 6, shape = "Disc", color = Color3.fromRGB(130, 190, 255) },
	{ id = "Wedge", name = "Клин", zone = 2, value = 9, shape = "Wedge", color = Color3.fromRGB(255, 220, 130) },
	{ id = "Corner", name = "Уголок", zone = 3, value = 25, shape = "Corner", color = Color3.fromRGB(200, 160, 255) },
	{ id = "Ring", name = "Кольцо", zone = 3, value = 35, shape = "Ring", color = Color3.fromRGB(120, 235, 245) },
	{ id = "Prism", name = "Призма", zone = 4, value = 90, shape = "Prism", color = Color3.fromRGB(255, 170, 120) },
	{ id = "Star", name = "Звезда", zone = 4, value = 130, shape = "Star", color = Color3.fromRGB(255, 235, 150) },
} :: { ItemKind }

Config.ItemById = {} :: { [string]: ItemKind }
for _, item in Config.Items do
	Config.ItemById[item.id] = item
end

Config.ZoneCount = 4
Config.ZoneNames = { "Мятная", "Небесная", "Лиловая", "Закатная" }
Config.ZoneColors = {
	Color3.fromRGB(110, 230, 185),
	Color3.fromRGB(110, 185, 255),
	Color3.fromRGB(185, 135, 255),
	Color3.fromRGB(255, 165, 105),
}
-- Цена ворот в зону (1-я открыта)
Config.GatePrices = { 0, 150, 1200, 9000 }

-- Базовые шансы (%) по зонам; удача умножает редкий и эпик
Config.RareChance = { 25, 27, 29, 31 }
Config.EpicChance = { 5, 6, 7, 8 }

Config.RarityInfo = {
	Common = { name = "Обычный", color = Color3.fromRGB(235, 235, 245), sellMult = 1 },
	Rare = { name = "Редкий", color = Color3.fromRGB(90, 200, 255), sellMult = 5 },
	Epic = { name = "Эпик", color = Color3.fromRGB(255, 120, 230), sellMult = 25 },
}

Config.SourceCooldown = 0.6 -- секунды на один источник
Config.GlobalClickCooldown = 0.15
Config.ClickRange = 40
Config.PityEpic = 60 -- эпик гарантирован, если его не было столько дропов
Config.CollectionBonus = 0.05 -- +5% дохода за слот

Config.BaseWalkSpeed = 16
Config.SpeedPerLevel = 2
Config.BaseCapacity = 10
Config.CapacityPerLevel = 5
Config.LuckPerLevel = 0.10

Config.Upgrades = {
	{ id = "Speed", name = "Скорость", description = "+2 к скорости бега", baseCost = 20, costGrowth = 1.5, maxLevel = 10 },
	{ id = "Bag", name = "Рюкзак", description = "+5 мест", baseCost = 25, costGrowth = 1.5, maxLevel = 20 },
	{ id = "Luck", name = "Удача", description = "+10% к шансу редкого и эпика", baseCost = 40, costGrowth = 1.6, maxLevel = 10 },
} :: { Upgrade }

Config.UpgradeById = {} :: { [string]: Upgrade }
for _, u in Config.Upgrades do
	Config.UpgradeById[u.id] = u
end

Config.Sounds = {
	Pop = "rbxassetid://140323850218372",
	Rare = "rbxassetid://135385970610304",
	Epic = "rbxassetid://1301186018",
	Coins = "rbxassetid://5314631765",
	Buy = "rbxassetid://1301186018",
	Music = "rbxassetid://77295456618099",
}

function Config.collectionKey(itemId: string, rarity: Rarity): string
	return itemId .. ":" .. rarity
end

-- Шансы (%) для зоны с учётом удачи
function Config.odds(zone: number, luckLevel: number): (number, number, number)
	local mult = 1 + luckLevel * Config.LuckPerLevel
	local epic = Config.EpicChance[zone] * mult
	local rare = Config.RareChance[zone] * mult
	return 100 - rare - epic, rare, epic
end

return Config
