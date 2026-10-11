-- Creates the remotes on the server and waits for them on the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DEFINITIONS = {
	UsePowerUp = "RemoteEvent", -- client -> server
	ResetCar = "RemoteEvent", -- client -> server
	Notify = "RemoteEvent", -- server -> client (text, duration, big)
	Effect = "RemoteEvent", -- server -> client (kind, value)
	Shop = "RemoteFunction", -- client -> server (action, id) -> ok, message
}

local folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for name, className in DEFINITIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local Remotes = {}
for name in DEFINITIONS do
	Remotes[name] = folder:WaitForChild(name)
end

return Remotes
