--!strict
-- Горки домой. Каждая начинается на дальнем острове зоны и кончается на базе.
-- Форма пути задаётся кусками «черепашки»; карта строит рельсы по тем же точкам.
local Turtle = require(script.Parent.Turtle)

export type Def = {
	id: string,
	name: string,
	zone: number,
	color: Color3,
	exitOffset: Vector3, -- куда поставить игрока после поездки (от конца пути)
	build: () -> { CFrame },
}

export type Track = {
	def: Def,
	samples: { CFrame },
	dist: { number },
	times: { number },
	length: number,
	duration: number,
}

local Coasters = {}

Coasters.Defs = {
	{
		id = "Sky",
		name = "Небесный штопор",
		zone = 2,
		color = Color3.fromRGB(110, 185, 255),
		exitOffset = Vector3.new(7, 0, -2),
		build = function()
			local t = Turtle.new(Vector3.new(-30, 49.5, 170), 90)
			Turtle.straight(t, 20)
			Turtle.slope(t, 40, -20)
			Turtle.helix(t, 22, -540, -22, 25)
			Turtle.turn(t, 90, 20, 20)
			Turtle.straight(t, 10)
			Turtle.loop(t, 16, -8)
			Turtle.straight(t, 6)
			Turtle.corkscrew(t, 30, 1)
			Turtle.connect(t, Vector3.new(-40, 1.5, 30), 0)
			Turtle.straight(t, 30)
			return t.samples
		end,
	},
	{
		id = "Flip",
		name = "Перевёртыш",
		zone = 3,
		color = Color3.fromRGB(185, 135, 255),
		exitOffset = Vector3.new(-7, 0, -2),
		build = function()
			local t = Turtle.new(Vector3.new(14, 41, 440), -90)
			Turtle.straight(t, 22)
			Turtle.turn(t, 90, 18, 20)
			Turtle.slope(t, 40, -12)
			Turtle.corkscrew(t, 48, 1)
			Turtle.straight(t, 12)
			Turtle.inverted(t, 70)
			Turtle.straight(t, 8)
			Turtle.slope(t, 60, -24)
			Turtle.loop(t, 15, 8)
			Turtle.straight(t, 24)
			Turtle.connect(t, Vector3.new(40, 1.5, 30), 0)
			Turtle.straight(t, 30)
			return t.samples
		end,
	},
	{
		id = "Sunset",
		name = "Закат-экспресс",
		zone = 4,
		color = Color3.fromRGB(255, 165, 105),
		exitOffset = Vector3.new(2, 0, 7),
		build = function()
			local t = Turtle.new(Vector3.new(-14, 61, 566), 90)
			Turtle.straight(t, 100)
			Turtle.turn(t, -90, 20, 20)
			Turtle.slope(t, 50, -40)
			Turtle.loop(t, 17, -8)
			Turtle.straight(t, 16)
			Turtle.helix(t, 16, 720, -16, 30)
			Turtle.straight(t, 20)
			Turtle.slope(t, 30, 18)
			Turtle.inverted(t, 60)
			Turtle.slope(t, 40, -18)
			Turtle.corkscrew(t, 40, 1)
			Turtle.straight(t, 40)
			Turtle.connect(t, Vector3.new(-50, 1.5, -40), -90)
			Turtle.straight(t, 40)
			return t.samples
		end,
	},
} :: { Def }

Coasters.ById = {} :: { [string]: Def }
for _, d in Coasters.Defs do
	Coasters.ById[d.id] = d
end

-- Скорость как у настоящих горок: разгон со станции, быстрее внизу, медленнее наверху, тормоз в конце
local GRAVITY = 70
local V_START = 26
local V_MIN = 22
local V_MAX = 115
local LAUNCH = 60
local BRAKE = 70
local V_END = 10

local cache: { [string]: Track } = {}

function Coasters.get(id: string): Track
	local cached = cache[id]
	if cached then
		return cached
	end
	local def = Coasters.ById[id]
	local samples = def.build()
	local dist = Turtle.distances(samples)
	local length = dist[#dist]
	local y0 = samples[1].Position.Y
	local function speed(i: number): number
		local s = dist[i]
		local y = samples[i].Position.Y
		local v = math.sqrt(math.max(V_START * V_START + 2 * GRAVITY * (y0 - y), V_MIN * V_MIN))
		v = math.min(v, V_MAX, math.sqrt(12 * 12 + 2 * LAUNCH * s), math.sqrt(V_END * V_END + 2 * BRAKE * (length - s)))
		return v
	end
	local times = { 0 }
	for i = 2, #samples do
		local ds = dist[i] - dist[i - 1]
		times[i] = times[i - 1] + ds / ((speed(i) + speed(i - 1)) / 2)
	end
	local track: Track = { def = def, samples = samples, dist = dist, times = times, length = length, duration = times[#times] }
	cache[id] = track
	return track
end

-- положение на пути через t секунд после старта
function Coasters.at(track: Track, t: number): CFrame
	local times = track.times
	if t <= 0 then
		return track.samples[1]
	end
	if t >= track.duration then
		return track.samples[#track.samples]
	end
	local lo, hi = 1, #times
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	local k = (t - times[lo]) / (times[hi] - times[lo])
	return track.samples[lo]:Lerp(track.samples[hi], k)
end

return Coasters
