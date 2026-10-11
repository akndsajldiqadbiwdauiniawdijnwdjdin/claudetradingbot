-- Server-side garage: every purchase is validated here, never trusted from the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local Shop = {}

local lastRequest = {}

local upgradesById = {}
for _, upgrade in Config.Upgrades do
	upgradesById[upgrade.Id] = upgrade
end

local actions = {}

function actions.BuyCar(data, id)
	local car = Config.CarsById[id]
	if not car then
		return false, "Unknown car"
	end
	if data.OwnedCars[id] then
		return false, "You already own that"
	end
	if data.Cash < car.Price then
		return false, "Not enough cash"
	end
	data.Cash -= car.Price
	data.OwnedCars[id] = true
	data.Equipped = id
	return true, "Bought the " .. car.Name .. "!"
end

function actions.Equip(data, id)
	local car = Config.CarsById[id]
	if not (car and data.OwnedCars[id]) then
		return false, "You don't own that car"
	end
	data.Equipped = id
	return true, car.Name .. " equipped (next race)"
end

function actions.Upgrade(data, id)
	local upgrade = upgradesById[id]
	if not upgrade then
		return false, "Unknown upgrade"
	end
	local level = data.Upgrades[id] or 0
	if level >= upgrade.MaxLevel then
		return false, "Already maxed"
	end
	local cost = Config.upgradeCost(upgrade, level)
	if data.Cash < cost then
		return false, "Not enough cash"
	end
	data.Cash -= cost
	data.Upgrades[id] = level + 1
	return true, string.format("%s upgraded to level %d", upgrade.Name, level + 1)
end

function Shop.init()
	Remotes.Shop.OnServerInvoke = function(player, action, id)
		if typeof(action) ~= "string" or typeof(id) ~= "string" or not actions[action] then
			return false, "Bad request"
		end
		if os.clock() - (lastRequest[player] or 0) < 0.2 then
			return false, "Slow down"
		end
		lastRequest[player] = os.clock()

		local ok, message = false, "Data not loaded yet"
		PlayerData.update(player, function(data)
			ok, message = actions[action](data, id)
		end)
		return ok, message
	end

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return Shop
