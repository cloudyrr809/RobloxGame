--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Effects = require(script.Effects)
local Hud = require(script.Hud)
local Motion = require(script.Motion)
local Opening = require(script.Opening)
local Ring = require(script.Ring)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Mined = Remotes:WaitForChild("Mined") :: RemoteEvent
local Opened = Remotes:WaitForChild("Opened") :: RemoteEvent
local Notice = Remotes:WaitForChild("Notice") :: RemoteEvent

Hud.start()
Effects.start()
Motion.start()
Ring.start()

Motion.hooks(function(_id: string)
	Effects.play("Buy", 0.6, 0.8)
end, function()
	Effects.play("Coins", 0.5, 1.2)
end, function(pad: BasePart)
	Effects.play("Pop", 0.6, 1.3)
	Effects.burst(pad.Position, pad.Color, 25)
end)

Mined.OnClientEvent:Connect(function(model: Model, regrow: number)
	if typeof(model) == "Instance" and model:IsA("Model") and type(regrow) == "number" then
		Effects.mined(model, regrow)
	end
end)

Opened.OnClientEvent:Connect(function(result: Opening.Result)
	if type(result) == "table" then
		task.spawn(Opening.play, result)
	end
end)
Opening.onDone(function()
	Hud.opened()
end)

local lastNotice = ""
local lastNoticeAt = 0
Notice.OnClientEvent:Connect(function(text: string)
	-- не спамим одно и то же сообщение
	if text == lastNotice and os.clock() - lastNoticeAt < 1.5 then
		return
	end
	lastNotice = text
	lastNoticeAt = os.clock()
	Hud.notice(text)
end)
