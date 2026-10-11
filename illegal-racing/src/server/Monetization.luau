-- 2x Cash game pass + cash developer products. IDs are configured in Config.Monetization.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)

local Monetization = {}

local PASS_ID = Config.Monetization.DoubleCashPassId

local function checkPass(player: Player)
	if PASS_ID == 0 then
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, PASS_ID)
	if ok and owns then
		player:SetAttribute("DoubleCash", true)
	end
end

function Monetization.init()
	Players.PlayerAdded:Connect(checkPass)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPass, player)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == PASS_ID then
			player:SetAttribute("DoubleCash", true)
		end
	end)

	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		local cash = Config.Monetization.CashProducts[receipt.ProductId]
		if not (player and cash and PlayerData.get(player)) then
			-- Roblox retries later (e.g. next time the player joins).
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		PlayerData.update(player, function(data)
			if not data.Purchases[receipt.PurchaseId] then
				data.Purchases[receipt.PurchaseId] = true
				data.Cash += cash
			end
		end)
		PlayerData.save(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

return Monetization
