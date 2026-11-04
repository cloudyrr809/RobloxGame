--!strict
-- «Черепашка»: собирает путь из кусков (прямая, поворот, горка, петля, спираль,
-- штопор, участок вверх ногами, волна). Результат — список CFrame через ~step стадов:
-- LookVector — направление пути, UpVector — «верх» дорожки (в петле он смотрит в центр).
-- Им пользуются и постройка карты, и поездка на горках, поэтому рельсы и вагонетка совпадают.
local Turtle = {}

export type T = {
	pos: Vector3,
	yaw: number,
	pitch: number,
	roll: number,
	step: number,
	samples: { CFrame },
}

local TAU = math.pi * 2

local function smooth(k: number): number
	return k * k * (3 - 2 * k)
end

local function flatForward(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function flatRight(yaw: number): Vector3
	return Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
end

local function forward(yaw: number, pitch: number): Vector3
	return Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
end

local function emit(t: T)
	table.insert(t.samples, CFrame.new(t.pos) * CFrame.fromEulerAnglesYXZ(t.pitch, t.yaw, t.roll))
end

local function count(t: T, len: number): number
	return math.max(1, math.ceil(math.abs(len) / t.step))
end

-- направление по разнице двух точек
local function aim(t: T, d: Vector3)
	local flat = Vector3.new(d.X, 0, d.Z).Magnitude
	if flat > 1e-4 then
		t.yaw = math.atan2(-d.X, -d.Z)
	end
	t.pitch = math.atan2(d.Y, math.max(flat, 1e-4))
end

function Turtle.new(pos: Vector3, yawDeg: number, step: number?): T
	local t: T = { pos = pos, yaw = math.rad(yawDeg), pitch = 0, roll = 0, step = step or 3, samples = {} }
	emit(t)
	return t
end

function Turtle.straight(t: T, len: number)
	local n = count(t, len)
	for _ = 1, n do
		t.pos += forward(t.yaw, t.pitch) * (len / n)
		emit(t)
	end
end

-- angle > 0 — налево. bank — крен в поворот (градусы)
function Turtle.turn(t: T, angleDeg: number, radius: number, bankDeg: number?)
	local a = math.rad(angleDeg)
	local len = radius * math.abs(a)
	local n = count(t, len)
	local bank = math.rad(bankDeg or 0) * math.sign(a)
	for i = 1, n do
		local k = i / n
		local mid = t.yaw + a / n / 2
		t.pos += flatForward(mid) * (len / n)
		t.yaw += a / n
		t.pitch = 0
		t.roll = bank * math.sin(math.pi * k)
		emit(t)
	end
	t.roll = 0
end

-- горка вверх/вниз на dy за горизонтальную длину len (плавный S-профиль)
function Turtle.slope(t: T, len: number, dy: number)
	local p0 = t.pos
	local dir = flatForward(t.yaw)
	local n = count(t, math.sqrt(len * len + dy * dy))
	for i = 1, n do
		local k = i / n
		t.pos = p0 + dir * (len * k) + Vector3.new(0, dy * smooth(k), 0)
		t.pitch = math.atan(dy * 6 * k * (1 - k) / len)
		emit(t)
	end
	t.pitch = 0
end

-- мёртвая петля; shift — сдвиг вбок, чтобы выезд не совпал со въездом
function Turtle.loop(t: T, radius: number, shift: number)
	local p0 = t.pos
	local dir = flatForward(t.yaw)
	local right = flatRight(t.yaw)
	local n = count(t, TAU * radius)
	for i = 1, n do
		local k = i / n
		local th = TAU * k
		t.pos = p0 + dir * (radius * math.sin(th)) + Vector3.new(0, radius * (1 - math.cos(th)), 0) + right * (shift * smooth(k))
		t.pitch = th
		emit(t)
	end
	t.pitch = 0
end

-- спираль: поворот на angle (>0 налево) с подъёмом/спуском dy
function Turtle.helix(t: T, radius: number, angleDeg: number, dy: number, bankDeg: number?)
	local a = math.rad(angleDeg)
	local flat = radius * math.abs(a)
	local n = count(t, math.sqrt(flat * flat + dy * dy))
	local bank = math.rad(bankDeg or 0) * math.sign(a)
	local slopeAngle = math.atan(dy / flat)
	for i = 1, n do
		local k = i / n
		local ramp = math.min(1, k * 8, (1 - k) * 8 + 1 / 8)
		local mid = t.yaw + a / n / 2
		t.pos += flatForward(mid) * (flat / n) + Vector3.new(0, dy / n, 0)
		t.yaw += a / n
		t.pitch = slopeAngle
		t.roll = bank * ramp
		emit(t)
	end
	t.pitch = 0
	t.roll = 0
end

-- штопор: едем прямо и переворачиваемся вокруг рельсов
function Turtle.corkscrew(t: T, len: number, turns: number)
	local n = count(t, len)
	local r0 = t.roll
	for i = 1, n do
		local k = i / n
		t.pos += forward(t.yaw, t.pitch) * (len / n)
		t.roll = r0 + TAU * turns * smooth(k)
		emit(t)
	end
	t.roll = r0
end

-- участок «по потолку»: переворот, едем вверх ногами, переворот обратно
function Turtle.inverted(t: T, len: number)
	local n = count(t, len)
	for i = 1, n do
		local k = i / n
		t.pos += forward(t.yaw, t.pitch) * (len / n)
		if k < 0.25 then
			t.roll = math.pi * smooth(k / 0.25)
		elseif k < 0.75 then
			t.roll = math.pi
		else
			t.roll = math.pi + math.pi * smooth((k - 0.75) / 0.25)
		end
		emit(t)
	end
	t.roll = 0
end

export type WaveOpts = {
	len: number,
	side: number?, -- размах змейки вбок
	bump: number?, -- высота горбов
	bumps: number?, -- число горбов
	dy: number?, -- общий подъём
	twist: number?, -- крен-скрутка, градусы
	twists: number?, -- число скруток
	bankFactor: number?, -- крен в повороты
}

-- волна-змейка: вбок и вверх-вниз, с креном. Начало и конец — по прямой.
function Turtle.wave(t: T, o: WaveOpts)
	local p0 = t.pos
	local dir = flatForward(t.yaw)
	local right = flatRight(t.yaw)
	local side, bump, bumps = o.side or 0, o.bump or 0, o.bumps or 1
	local dy, twist, twists = o.dy or 0, math.rad(o.twist or 0), o.twists or 1
	local bankFactor = o.bankFactor or 1.5
	local yaw0 = t.yaw
	local function at(k: number): Vector3
		local s = math.sin(math.pi * k)
		local x = side * math.sin(TAU * k) * s
		local y = bump * math.sin(math.pi * bumps * k) * s + dy * smooth(k)
		return p0 + dir * (o.len * k) + right * x + Vector3.new(0, y, 0)
	end
	local function lateral(k: number): number
		return side * math.sin(TAU * k) * math.sin(math.pi * k)
	end
	local n = count(t, o.len * 1.15)
	local e = 1 / (n * 4)
	for i = 1, n do
		local k = i / n
		t.pos = at(k)
		aim(t, at(math.min(k + e, 1)) - at(math.max(k - e, 0)))
		local curv = (lateral(math.min(k + e, 1)) - 2 * lateral(k) + lateral(math.max(k - e, 0))) / (e * e) / (o.len * o.len)
		t.roll = math.clamp(-curv * bankFactor, -0.4, 0.4) + twist * math.sin(TAU * twists * k) * math.sin(math.pi * k)
		emit(t)
	end
	t.yaw = yaw0
	t.pitch = 0
	t.roll = 0
end

-- плавная дуга в точку target с направлением targetYaw (градусы)
function Turtle.connect(t: T, target: Vector3, targetYawDeg: number, tension: number?)
	local p0 = t.pos
	local y1 = math.rad(targetYawDeg)
	local flat0 = Vector3.new(p0.X, 0, p0.Z)
	local flat1 = Vector3.new(target.X, 0, target.Z)
	local d = (flat1 - flat0).Magnitude * (tension or 1)
	local m0 = flatForward(t.yaw) * d
	local m1 = flatForward(y1) * d
	local function at(k: number): Vector3
		local k2, k3 = k * k, k * k * k
		local h00, h10, h01, h11 = 2 * k3 - 3 * k2 + 1, k3 - 2 * k2 + k, -2 * k3 + 3 * k2, k3 - k2
		local f = flat0 * h00 + m0 * h10 + flat1 * h01 + m1 * h11
		return Vector3.new(f.X, p0.Y + (target.Y - p0.Y) * smooth(k), f.Z)
	end
	local len = 0
	local prev = p0
	for i = 1, 24 do
		local p = at(i / 24)
		len += (p - prev).Magnitude
		prev = p
	end
	local n = count(t, len)
	local e = 1 / (n * 4)
	for i = 1, n do
		local k = i / n
		t.pos = at(k)
		aim(t, at(math.min(k + e, 1)) - at(math.max(k - e, 0)))
		t.roll = 0
		emit(t)
	end
	t.pos = target
	t.yaw = y1
	t.pitch = 0
	t.roll = 0
end

-- длины от начала до каждой точки
function Turtle.distances(samples: { CFrame }): { number }
	local d = { 0 }
	for i = 2, #samples do
		d[i] = d[i - 1] + (samples[i].Position - samples[i - 1].Position).Magnitude
	end
	return d
end

return Turtle
