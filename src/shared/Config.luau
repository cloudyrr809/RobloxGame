--!strict
-- Все числа игры в одном месте. Сервер и клиент читают одну таблицу.

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"
export type CrystalKind = "Small" | "Big" | "Shining"

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

export type CrystalInfo = {
	name: string,
	coreName: string,
	holdMult: number, -- во сколько раз дольше добывать
	regrow: number, -- секунд до восстановления (свой у каждого игрока; у сияющего — общий)
	rareMult: number,
	epicMult: number,
	legendaryMult: number,
	noCommon: boolean,
	coreSize: number,
}

local Config = {}

Config.Items = {
	{ id = "Ball", name = "Шарик", zone = 1, value = 8, shape = "Ball", color = Color3.fromRGB(255, 170, 200) },
	{ id = "Cube", name = "Кубик", zone = 1, value = 12, shape = "Block", color = Color3.fromRGB(140, 230, 190) },
	{ id = "Disc", name = "Шайба", zone = 2, value = 30, shape = "Disc", color = Color3.fromRGB(130, 190, 255) },
	{ id = "Wedge", name = "Клин", zone = 2, value = 45, shape = "Wedge", color = Color3.fromRGB(255, 220, 130) },
	{ id = "Corner", name = "Уголок", zone = 3, value = 110, shape = "Corner", color = Color3.fromRGB(200, 160, 255) },
	{ id = "Ring", name = "Кольцо", zone = 3, value = 160, shape = "Ring", color = Color3.fromRGB(120, 235, 245) },
	{ id = "Prism", name = "Призма", zone = 4, value = 400, shape = "Prism", color = Color3.fromRGB(255, 170, 120) },
	{ id = "Star", name = "Звезда", zone = 4, value = 600, shape = "Star", color = Color3.fromRGB(255, 235, 150) },
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
Config.GatePrices = { 0, 200, 1200, 5000 }

-- Базовые шансы (%) по зонам для малого кристалла; удача и тип кристалла их умножают
Config.RareChance = { 20, 22, 24, 26 }
Config.EpicChance = { 4, 5, 6, 7 }
Config.LegendaryChance = { 0.5, 0.7, 1, 1.3 }

Config.Rarities = { "Common", "Rare", "Epic", "Legendary" } :: { Rarity }
Config.CollectRarities = { "Rare", "Epic", "Legendary" } :: { Rarity }
Config.RarityInfo = {
	Common = { name = "Обычный", color = Color3.fromRGB(235, 235, 245), sellMult = 1, tier = 1 },
	Rare = { name = "Редкий", color = Color3.fromRGB(90, 200, 255), sellMult = 5, tier = 2 },
	Epic = { name = "Эпик", color = Color3.fromRGB(255, 120, 230), sellMult = 20, tier = 3 },
	Legendary = { name = "Легендарный", color = Color3.fromRGB(255, 200, 60), sellMult = 80, tier = 4 },
}

-- Три вида кристаллов в каждой зоне: быстрый, долгий-но-щедрый и редкий блуждающий
Config.Crystals = {
	Small = {
		name = "Осколок",
		coreName = "Малое ядро",
		holdMult = 1,
		regrow = 20,
		rareMult = 1,
		epicMult = 1,
		legendaryMult = 1,
		noCommon = false,
		coreSize = 1.8,
	},
	Big = {
		name = "Глыба",
		coreName = "Крупное ядро",
		holdMult = 2.5,
		regrow = 40,
		rareMult = 1.5,
		epicMult = 2,
		legendaryMult = 2.5,
		noCommon = false,
		coreSize = 2.4,
	},
	Shining = {
		name = "Сияющий кристалл",
		coreName = "Сияющее ядро",
		holdMult = 3,
		regrow = 45,
		rareMult = 1,
		epicMult = 3,
		legendaryMult = 4,
		noCommon = true,
		coreSize = 2.8,
	},
} :: { [CrystalKind]: CrystalInfo }

Config.MineBaseTime = { 3, 4, 5, 6 } -- секунды удержания по зонам (малый кристалл, сила 0)
Config.StrengthFactor = 0.93 -- каждый уровень силы: ×0.93 к времени
Config.CarrySpeedMult = 0.85 -- с ядром идёшь медленнее
Config.MineRange = 14
Config.AltarRange = 16
Config.RevealTimeout = 15 -- сервер выдаёт награду сам, если клиент не досмотрел раскол

Config.PityEpic = 20 -- эпик гарантирован, если его не было столько ядер
Config.PityLegendary = 80
Config.CollectionBonus = 0.05 -- +5% дохода за слот

Config.BaseWalkSpeed = 16
Config.SpeedPerLevel = 2
Config.LuckPerLevel = 0.10

-- Скорость не покупается: её качают на разгонном кольце вокруг базы
Config.SpeedMaxLevel = 12
Config.LapsPerLevel = { 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4 } -- сколько кругов до следующего уровня
Config.RecordBonusLaps = 0.5 -- круг быстрее своей тени засчитывается как 1.5 круга
Config.RingGateCount = 8 -- контрольные арки на кольце, проходить по порядку
Config.RingGateRadius = 9

-- Жар ядра: остывает, пока несёшь. Чем горячее донёс, тем выше шансы на редкое
Config.HeatTime = { 14, 24, 30, 36 } -- секунд до полного остывания, по зонам
Config.HeatBonus = 1.0 -- горячее ядро: шансы редкого и выше ×2

Config.Upgrades = {
	{ id = "Strength", name = "Сила", description = "кристаллы добываются на 7% быстрее", baseCost = 40, costGrowth = 1.55, maxLevel = 10 },
	{ id = "Luck", name = "Удача", description = "+10% к шансу редкого и выше", baseCost = 60, costGrowth = 1.6, maxLevel = 10 },
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

function Config.mineTime(zone: number, kind: CrystalKind, strengthLevel: number): number
	return Config.MineBaseTime[zone] * Config.Crystals[kind].holdMult * Config.StrengthFactor ^ strengthLevel
end

-- Шансы (%) для ядра: (обычный, редкий, эпик, легендарный), в сумме 100
function Config.walkSpeed(speedLevel: number): number
	return Config.BaseWalkSpeed + speedLevel * Config.SpeedPerLevel
end

-- heat 0..1 — насколько горячим донесли ядро
function Config.odds(zone: number, luckLevel: number, kind: CrystalKind, heat: number?): (number, number, number, number)
	local info = Config.Crystals[kind]
	local mult = (1 + luckLevel * Config.LuckPerLevel) * (1 + math.clamp(heat or 0, 0, 1) * Config.HeatBonus)
	local leg = Config.LegendaryChance[zone] * mult * info.legendaryMult
	local epic = Config.EpicChance[zone] * mult * info.epicMult
	local rare = Config.RareChance[zone] * mult * info.rareMult
	if info.noCommon then
		-- редкий минимум; эпик и легендарный вместе не больше 90%
		if epic + leg > 90 then
			local k = 90 / (epic + leg)
			epic, leg = epic * k, leg * k
		end
		return 0, 100 - epic - leg, epic, leg
	end
	local total = rare + epic + leg
	if total > 95 then
		local k = 95 / total
		rare, epic, leg = rare * k, epic * k, leg * k
	end
	return 100 - rare - epic - leg, rare, epic, leg
end

return Config
