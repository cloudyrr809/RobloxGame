--!strict
-- Разгонное кольцо: после круга сервер присылает время. Лучший круг записывается,
-- и в начале следующего по кольцу бежит «тень» — твой рекорд. Обогнал тень —
-- круг засчитывается в полтора раза.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Effects = require(script.Parent.Effects)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LapRemote = Remotes:WaitForChild("Lap") :: RemoteEvent

local player = Players.LocalPlayer
local Ring = {}

type Point = { t: number, cf: CFrame }
local trail: { Point } = {}
local best: { Point }? = nil
local ghost: Model? = nil
local ghostStart = 0

local GHOST_COLOR = Color3.fromRGB(255, 140, 215)

local function makeGhost(): Model
	local m = Instance.new("Model")
	m.Name = "Ghost"
	local function p(shape: Enum.PartType, size: Vector3, offset: CFrame): Part
		local part = Instance.new("Part")
		part.Shape = shape
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.ForceField
		part.Color = GHOST_COLOR
		part.Size = size
		part.CFrame = offset
		part.Parent = m
		return part
	end
	local body = p(Enum.PartType.Block, Vector3.new(2, 2.6, 1.2), CFrame.new(0, 0, 0))
	p(Enum.PartType.Ball, Vector3.one * 1.6, CFrame.new(0, 2.1, 0))
	p(Enum.PartType.Block, Vector3.new(0.8, 2.2, 0.8), CFrame.new(-0.55, -2.4, 0))
	p(Enum.PartType.Block, Vector3.new(0.8, 2.2, 0.8), CFrame.new(0.55, -2.4, 0))
	m.PrimaryPart = body
	local light = Instance.new("PointLight")
	light.Color = GHOST_COLOR
	light.Range = 10
	light.Parent = body
	return m
end

local function ghostAt(path: { Point }, t: number): CFrame?
	if t > path[#path].t then
		return nil
	end
	for i = 2, #path do
		if path[i].t >= t then
			local a, b = path[i - 1], path[i]
			local k = (t - a.t) / math.max(b.t - a.t, 1e-3)
			return a.cf:Lerp(b.cf, k)
		end
	end
	return nil
end

function Ring.start()
	-- пишем свой путь 10 раз в секунду (последние 90 секунд)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				table.insert(trail, { t = os.clock(), cf = root.CFrame })
				while #trail > 0 and os.clock() - trail[1].t > 90 do
					table.remove(trail, 1)
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		local path = best
		if not path or not ghost then
			return
		end
		local cf = ghostAt(path, os.clock() - ghostStart + path[1].t)
		local g = ghost :: Model
		if cf then
			g:PivotTo(cf)
			g.Parent = Workspace
		else
			g.Parent = nil
		end
	end)

	LapRemote.OnClientEvent:Connect(function(lapTime: number, bestTime: number, beatGhost: boolean, leveled: boolean)
		local now = os.clock()
		if math.abs(lapTime - bestTime) < 1e-3 then
			-- этот круг — новый рекорд: он и станет тенью
			local path: { Point } = {}
			for _, p in trail do
				if p.t >= now - lapTime - 0.15 then
					table.insert(path, p)
				end
			end
			if #path >= 2 then
				best = path
			end
		end
		if not ghost then
			ghost = makeGhost()
		end
		ghostStart = now
		local text = string.format("Круг %.1f с", lapTime)
		if beatGhost then
			Effects.popup(text .. " — РЕКОРД! ×1.5", GHOST_COLOR, true)
			Effects.play("Rare", 0.7, 1.2)
		else
			Effects.popup(text .. string.format(" (рекорд %.1f)", bestTime), Color3.new(1, 1, 1), false)
			Effects.play("Pop", 0.5, 1.2)
		end
		if leveled then
			local level = player:GetAttribute("SpeedLevel")
			local speed = Config.walkSpeed(if type(level) == "number" then level else 0)
			task.delay(0.5, function()
				Effects.popup("СКОРОСТЬ " .. speed .. "!", Color3.fromRGB(120, 255, 170), true)
				Effects.play("Buy", 0.8)
				Effects.flash(Color3.fromRGB(120, 255, 170), 0.25)
			end)
		end
	end)
end

return Ring
