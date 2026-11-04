--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Effects = require(script.Effects)
local Hud = require(script.Hud)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Drop = Remotes:WaitForChild("Drop") :: RemoteEvent
local Sold = Remotes:WaitForChild("Sold") :: RemoteEvent
local Notice = Remotes:WaitForChild("Notice") :: RemoteEvent

Hud.start()
Effects.start()

Drop.OnClientEvent:Connect(function(source: Model, itemId: string, rarity: Config.Rarity)
	if typeof(source) == "Instance" and source:IsA("Model") and Config.ItemById[itemId] then
		Effects.drop(source, itemId, rarity)
	end
end)

Sold.OnClientEvent:Connect(function(earned: number, soldCount: number, newKeys: { string })
	Hud.sold(earned, soldCount)
	Effects.sold(earned, newKeys)
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
