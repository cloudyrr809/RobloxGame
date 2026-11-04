--!strict
-- Кристаллы: зажал кнопку нужное время → в руках ядро.
-- Осколок и глыба у каждого игрока свои (восстанавливаются отдельно),
-- сияющий — один на сервер и после добычи переезжает в другое укромное место.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MinedRemote = Remotes:WaitForChild("Mined") :: RemoteEvent
local NoticeRemote = Remotes:WaitForChild("Notice") :: RemoteEvent

local rng = Random.new()
local Mining = {}

local function spotsOf(model: Model): { BasePart }
	local list = {}
	local folder = model.Parent and model.Parent:FindFirstChild("ShineSpots")
	if folder then
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(list, p)
			end
		end
	end
	return list
end

-- переезд сияющего кристалла на случайное другое место
local function relocate(model: Model)
	local spots = spotsOf(model)
	local current = model:GetAttribute("SpotPos")
	if #spots == 0 or typeof(current) ~= "Vector3" then
		model:SetAttribute("Hidden", false)
		return
	end
	local choices = {}
	for _, p in spots do
		if (p.Position - current).Magnitude > 1 then
			table.insert(choices, p)
		end
	end
	local target = if #choices > 0 then choices[rng:NextInteger(1, #choices)] else spots[1]
	model:PivotTo(model:GetPivot() + (target.Position - current))
	model:SetAttribute("SpotPos", target.Position)
	model:SetAttribute("Hidden", false)
end

local function bind(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local zone = model:GetAttribute("Zone")
	local kind = model:GetAttribute("Kind")
	local promptPart = model:FindFirstChild("PromptPart") :: BasePart?
	local prompt = promptPart and promptPart:FindFirstChild("Mine") :: ProximityPrompt?
	if type(zone) ~= "number" or type(kind) ~= "string" or not Config.Crystals[kind :: Config.CrystalKind] or not prompt or not promptPart then
		warn("Кристалл настроен неверно:", model:GetFullName())
		return
	end
	local crystalKind: Config.CrystalKind = kind :: any
	local shining = crystalKind == "Shining"
	if shining then
		-- запоминаем, у какой точки стоит
		local best, bestD = nil, math.huge
		for _, p in spotsOf(model) do
			local d = (p.Position - promptPart.Position).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
		model:SetAttribute("SpotPos", if best then best.Position else promptPart.Position)
		model:SetAttribute("Hidden", false)
	end

	prompt.PromptButtonHoldBegan:Connect(function(player: Player)
		local s = State.get(player)
		if s then
			s.holdStart[model] = os.clock()
		end
	end)

	prompt.Triggered:Connect(function(player: Player)
		local s = State.get(player)
		if not s then
			return
		end
		local now = os.clock()
		local started = s.holdStart[model]
		s.holdStart[model] = nil
		if s.carry then
			NoticeRemote:FireClient(player, "Ты уже несёшь ядро — неси на базу")
			return
		end
		if not s.gates[zone] then
			NoticeRemote:FireClient(player, "Зона закрыта — открой ворота")
			return
		end
		local root = State.root(player)
		if not root or (root.Position - promptPart.Position).Magnitude > Config.MineRange then
			return
		end
		if shining then
			if model:GetAttribute("Hidden") == true then
				return
			end
		elseif (s.crystalReady[model] or 0) > now then
			return
		end
		-- держал ли кнопку столько, сколько положено (с запасом на пинг)
		local need = Config.mineTime(zone, crystalKind, State.level(s, "Strength"))
		if not started or now - started < need * 0.85 - 0.3 then
			return
		end

		local regrow = Config.Crystals[crystalKind].regrow
		if shining then
			model:SetAttribute("Hidden", true)
			task.delay(regrow, relocate, model)
		else
			s.crystalReady[model] = now + regrow
		end
		State.startCarry(player, zone, crystalKind)
		MinedRemote:FireClient(player, model, regrow)
	end)
end

function Mining.start()
	for _, m in CollectionService:GetTagged("Crystal") do
		bind(m)
	end
	CollectionService:GetInstanceAddedSignal("Crystal"):Connect(bind)
end

return Mining
