--!strict
-- Движение по заданному пути: поездка на горках (с вагонеткой и камерой «из вагона»)
-- и прыжки с площадок по дуге. Персонажем управляет его же клиент, поэтому
-- двигаем его здесь, а сервер видит результат как обычное движение.
-- Плюс страховка: упал с трассы — возвращаешься на последний остров.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Coasters = require(ReplicatedStorage.Shared.Coasters)

local player = Players.LocalPlayer
local Motion = {}

local busy = false

-- чтобы подсказки «прокатиться» не висели во время поездки
local function setRidePrompts(enabled: boolean)
	for _, st in CollectionService:GetTagged("CoasterStation") do
		local prompt = st:FindFirstChild("Ride", true) :: ProximityPrompt?
		if prompt then
			prompt.Enabled = enabled
		end
	end
end
local onRideStart: (string) -> () = function(_id: string) end
local onRideEnd: () -> () = function() end
local onPadLaunch: (BasePart) -> () = function(_pad: BasePart) end

function Motion.busy(): boolean
	return busy
end

function Motion.hooks(rideStart: (string) -> (), rideEnd: () -> (), padLaunch: (BasePart) -> ())
	onRideStart, onRideEnd, onPadLaunch = rideStart, rideEnd, padLaunch
end

local function parts(): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- общий проигрыватель пути: pose(t) → CFrame корня; duration; по окончании finish()
local function play(duration: number, pose: (number) -> CFrame, step: ((number, CFrame) -> ())?, finish: (() -> ())?)
	local character, _, root = parts()
	if not character or not root then
		return
	end
	busy = true
	local t0 = os.clock()
	local prev = pose(0)
	local connection: RBXScriptConnection
	connection = RunService.PreSimulation:Connect(function(frameDt: number)
		local _, _, r = parts()
		if not r or player.Character ~= character then
			connection:Disconnect()
			busy = false
			if finish then
				finish()
			end
			return
		end
		local t = math.min(os.clock() - t0, duration)
		local cf = pose(t)
		local dt = math.max(frameDt, 1 / 240)
		r.CFrame = cf
		r.AssemblyLinearVelocity = (cf.Position - prev.Position) / dt
		r.AssemblyAngularVelocity = Vector3.zero
		prev = cf
		if step then
			step(t, cf)
		end
		if t >= duration then
			connection:Disconnect()
			busy = false
			if finish then
				finish()
			end
		end
	end)
end

-- ===== Горки =====
local RIDER = CFrame.new(0, 3.3, 0)

local function makeCart(color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "LocalCart"
	local function p(size: Vector3, cf: CFrame, c: Color3, mat: Enum.Material)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Size = size
		part.CFrame = cf
		part.Color = c
		part.Material = mat
		part.Parent = m
		return part
	end
	local body = p(Vector3.new(3.8, 1.2, 5), CFrame.new(0, 1, 0), Color3.fromRGB(60, 50, 90), Enum.Material.SmoothPlastic)
	p(Vector3.new(4, 0.3, 5.2), CFrame.new(0, 1.7, 0), color, Enum.Material.Neon)
	p(Vector3.new(3.8, 1.6, 0.4), CFrame.new(0, 2.2, -2.4), color, Enum.Material.Neon)
	p(Vector3.new(3.2, 2.4, 0.3), CFrame.new(0, 2.6, 2.4), Color3.fromRGB(80, 70, 120), Enum.Material.SmoothPlastic)
	m.PrimaryPart = body
	return m
end

function Motion.ride(id: string)
	if busy or not Coasters.ById[id] then
		return
	end
	local character, humanoid, root = parts()
	if not character or not humanoid or not root then
		return
	end
	local track = Coasters.get(id)
	local cart = makeCart(track.def.color)
	cart.Parent = Workspace
	local camera = Workspace.CurrentCamera
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	camera.CameraType = Enum.CameraType.Scriptable
	local camCF = camera.CFrame
	onRideStart(id)
	setRidePrompts(false)
	local hum = humanoid
	play(track.duration, function(t: number): CFrame
		return Coasters.at(track, t) * RIDER
	end, function(t: number, _cf: CFrame)
		local base = Coasters.at(track, t)
		cart:PivotTo(base)
		-- камера за вагонеткой, крутится вместе с рельсами
		local ahead = Coasters.at(track, t + 0.35)
		local want = CFrame.lookAt((base * CFrame.new(0, 7, 11)).Position, (ahead * CFrame.new(0, 3, 0)).Position, base.UpVector)
		camCF = camCF:Lerp(want, 0.25)
		camera.CFrame = camCF
	end, function()
		cart:Destroy()
		setRidePrompts(true)
		camera.CameraType = Enum.CameraType.Custom
		hum.PlatformStand = false
		hum.AutoRotate = true
		local _, _, r = parts()
		local last = track.samples[#track.samples]
		if r then
			local exit = last.Position + track.def.exitOffset + Vector3.new(0, 3.5, 0)
			local look = last.LookVector * Vector3.new(1, 0, 1)
			r.CFrame = CFrame.lookAt(exit, exit + (if look.Magnitude > 0.1 then look.Unit else Vector3.zAxis))
			r.AssemblyLinearVelocity = Vector3.zero
		end
		onRideEnd()
	end)
end

-- ===== Прыжковые площадки =====
local function launch(pad: BasePart)
	if busy then
		return
	end
	local target = pad:GetAttribute("Target")
	local height = pad:GetAttribute("Height")
	local duration = pad:GetAttribute("Duration")
	local _, humanoid, root = parts()
	if typeof(target) ~= "Vector3" or type(height) ~= "number" or type(duration) ~= "number" or not humanoid or not root then
		return
	end
	local from = root.Position
	local to = target + Vector3.new(0, 3, 0)
	local flat = (to - from) * Vector3.new(1, 0, 1)
	local face = if flat.Magnitude > 0.1 then flat.Unit else root.CFrame.LookVector
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	onPadLaunch(pad)
	play(duration, function(t: number): CFrame
		local k = t / duration
		local pos = from:Lerp(to, k) + Vector3.new(0, 4 * height * k * (1 - k), 0)
		return CFrame.lookAt(pos, pos + face)
	end, nil, function()
		local _, _, r = parts()
		if r then
			r.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
		end
	end)
end

-- ===== Страховка от падения =====
local lastSafe: CFrame? = nil
local function trackCheckpoints()
	local _, _, root = parts()
	if not root or busy then
		return
	end
	local pos = root.Position
	for _, cp in CollectionService:GetTagged("Checkpoint") do
		if cp:IsA("BasePart") then
			local r = cp:GetAttribute("Radius")
			local top = cp.Position.Y + cp.Size.X / 2
			local d = pos - cp.Position
			if type(r) == "number" and Vector2.new(d.X, d.Z).Magnitude < r and pos.Y > top - 1 and pos.Y < top + 9 then
				lastSafe = CFrame.new(cp.Position.X, top + 4, cp.Position.Z)
			end
		end
	end
	local safe = lastSafe
	if safe and pos.Y < safe.Position.Y - 45 then
		root.CFrame = safe
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

function Motion.start()
	local cooldown: { [BasePart]: number } = {}
	local function bindPad(pad: Instance)
		if not pad:IsA("BasePart") then
			return
		end
		pad.Touched:Connect(function(hit: BasePart)
			local character = player.Character
			if not character or not hit:IsDescendantOf(character) then
				return
			end
			local now = os.clock()
			if (cooldown[pad] or 0) > now then
				return
			end
			cooldown[pad] = now + 1
			launch(pad)
		end)
	end
	for _, pad in CollectionService:GetTagged("JumpPad") do
		bindPad(pad)
	end
	CollectionService:GetInstanceAddedSignal("JumpPad"):Connect(bindPad)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= player or prompt.Name ~= "Ride" then
			return
		end
		local stationModel = prompt:FindFirstAncestorWhichIsA("Model")
		local id = stationModel and stationModel:GetAttribute("Track")
		if type(id) == "string" then
			Motion.ride(id)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			trackCheckpoints()
		end
	end)
	player.CharacterAdded:Connect(function()
		lastSafe = nil
		busy = false
		setRidePrompts(true)
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
	end)
end

return Motion
