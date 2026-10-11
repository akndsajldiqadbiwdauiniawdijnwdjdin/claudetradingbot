-- Pick-up boxes and the "illegal" weapons. All effects are decided on the server; clients
-- only read car attributes (BoostUntil, StunnedUntil, SpeedFactor) and Effect events.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CarBuilder = require(script.Parent.CarBuilder)

local PowerUps = {}

local oils = {}
local effectsFolder: Folder
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

local function notify(player: Player, text: string)
	Remotes.Notify:FireClient(player, text, 2.5)
end

local function stun(racer, duration: number)
	local current = racer.Car:GetAttribute("StunnedUntil") or 0
	racer.Car:SetAttribute("StunnedUntil", math.max(current, now() + duration))
end

local function launch(racer, velocity: Vector3)
	Remotes.Effect:FireClient(racer.Player, "Launch", velocity)
end

local function isStunned(racer): boolean
	return now() < (racer.Car:GetAttribute("StunnedUntil") or 0)
end

local function explosion(position: Vector3)
	local blast = Instance.new("Explosion")
	blast.Position = position
	blast.BlastPressure = 0 -- visual only; knockback is handled by launch()
	blast.DestroyJointRadiusPercent = 0
	blast.Parent = workspace
end

-- Racer directly ahead, else the next one behind.
local function adjacentTarget(race, racer)
	for _, place in { racer.Place - 1, racer.Place + 1 } do
		local other = race.Ordered[place]
		if other and other ~= racer and other.Active then
			return other
		end
	end
	return nil
end

function PowerUps.init(carsFolder: Folder)
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "Effects"
	effectsFolder.Parent = workspace
	rayParams.FilterDescendantsInstances = { carsFolder, effectsFolder }
end

function PowerUps.give(racer, id: string?)
	racer.PowerUp = id
	if racer.Player.Parent then
		racer.Player:SetAttribute("PowerUp", id)
	end
end

function PowerUps.roll(race, racer): string
	local behind = race.Count > 1 and racer.Place > race.Count / 2
	local weights, total = {}, 0
	for _, id in Config.PowerUpOrder do
		local weight = Config.PowerUps[id].Weight
		if behind and Config.CatchUpPowerUps[id] then
			weight *= Config.CatchUpPowerUps[id]
		end
		weights[id] = weight
		total += weight
	end
	local roll = math.random() * total
	for _, id in Config.PowerUpOrder do
		roll -= weights[id]
		if roll <= 0 then
			return id
		end
	end
	return Config.PowerUpOrder[1]
end

local handlers = {}

function handlers.Nitro(_race, racer)
	racer.Car:SetAttribute("BoostUntil", now() + Config.PowerUps.Nitro.Duration)
end

function handlers.Oil(_race, racer)
	local cfg = Config.PowerUps.Oil
	local cf = racer.Chassis.CFrame
	local back = flat(cf.LookVector)
	back = if back.Magnitude > 0.01 then back.Unit else Vector3.zAxis
	local position = cf.Position - back * 10
	local hit = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -30, 0), rayParams)
	local y = if hit then hit.Position.Y else position.Y - 1.2

	local puddle = Instance.new("Part")
	puddle.Name = "OilSlick"
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Size = Vector3.new(0.2, 12, 12)
	puddle.CFrame = CFrame.new(position.X, y + 0.1, position.Z) * CFrame.Angles(0, 0, math.rad(90))
	puddle.Anchored = true
	puddle.CanCollide = false
	puddle.CanQuery = false
	puddle.Color = Color3.fromRGB(15, 15, 20)
	puddle.Reflectance = 0.4
	puddle.Parent = effectsFolder

	table.insert(oils, {
		Part = puddle,
		Owner = racer,
		SafeUntil = now() + 1.5, -- don't instantly spin out the person who dropped it
		Expires = now() + cfg.Lifetime,
	})
end

function handlers.Rocket(_race, racer)
	local cfg = Config.PowerUps.Rocket
	local target = adjacentTarget(_race, racer)
	if not target then
		notify(racer.Player, "No target for your rocket!")
		return
	end

	local rocket = Instance.new("Part")
	rocket.Name = "Rocket"
	rocket.Size = Vector3.new(1, 1, 3)
	rocket.Material = Enum.Material.Neon
	rocket.Color = Color3.fromRGB(255, 60, 30)
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanQuery = false
	rocket.CFrame = racer.Chassis.CFrame * CFrame.new(0, 3, 0)
	rocket.Parent = effectsFolder
	notify(target.Player, "🚀 Incoming rocket from " .. racer.Player.DisplayName .. "!")

	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < 3 and target.Active do
			local dt = RunService.Heartbeat:Wait()
			local goal = target.Chassis.Position + Vector3.new(0, 2, 0)
			local delta = goal - rocket.Position
			if delta.Magnitude < 6 then
				break
			end
			local step = math.min(delta.Magnitude, cfg.Speed * dt)
			rocket.CFrame = CFrame.lookAt(rocket.Position + delta.Unit * step, goal)
		end
		local hitPosition = rocket.Position
		rocket:Destroy()
		if target.Active then
			explosion(hitPosition)
			stun(target, cfg.StunTime)
			launch(target, Vector3.new(math.random(-25, 25), 70, math.random(-25, 25)))
		end
	end)
end

function handlers.EMP(race, racer)
	local cfg = Config.PowerUps.EMP
	local origin = racer.Chassis.Position

	local wave = Instance.new("Part")
	wave.Shape = Enum.PartType.Ball
	wave.Size = Vector3.one * 4
	wave.CFrame = CFrame.new(origin)
	wave.Anchored = true
	wave.CanCollide = false
	wave.CanQuery = false
	wave.Material = Enum.Material.ForceField
	wave.Color = Color3.fromRGB(80, 180, 255)
	wave.Parent = effectsFolder
	local tween = TweenService:Create(wave, TweenInfo.new(0.5), { Size = Vector3.one * cfg.Radius * 2, Transparency = 1 })
	tween.Completed:Connect(function()
		wave:Destroy()
	end)
	tween:Play()

	local hits = 0
	for _, other in race.Ordered do
		if other ~= racer and other.Active and flatDistance(other.Chassis.Position, origin) <= cfg.Radius then
			local away = flat(other.Chassis.Position - origin)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.zAxis
			stun(other, cfg.StunTime)
			launch(other, away * 45 + Vector3.new(0, 30, 0))
			notify(other.Player, "⚡ EMP'd by " .. racer.Player.DisplayName .. "!")
			hits += 1
		end
	end
	notify(racer.Player, if hits > 0 then string.format("⚡ EMP hit %d racer(s)!", hits) else "⚡ EMP hit nobody...")
end

-- Rips a random stealable part off `from` and stacks it on `to`'s roof as a trophy.
local function moveStealablePart(from, to): string?
	local source = from.Car:FindFirstChild("Stealable")
	local destination = to.Car:FindFirstChild("Stealable")
	if not (source and destination) then
		return nil
	end
	local candidates = {}
	for _, child in source:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(candidates, child)
		end
	end
	if #candidates == 0 then
		return nil
	end

	local part = candidates[math.random(#candidates)]
	for _, child in part:GetChildren() do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end
	local trophies = to.Car:GetAttribute("Trophies") or 0
	to.Car:SetAttribute("Trophies", trophies + 1)
	part.CFrame = to.Chassis.CFrame * CFrame.new(0, 2.6 + trophies * 0.7, 1) * CFrame.Angles(0, math.rad(trophies * 35), 0)
	CarBuilder.weld(part, to.Chassis)
	part.Parent = destination
	return part.Name
end

function handlers.Steal(race, racer)
	local cfg = Config.PowerUps.Steal
	local position = racer.Chassis.Position

	local target = race.Ordered[racer.Place - 1]
	if not (target and target.Active and flatDistance(target.Chassis.Position, position) <= cfg.Range) then
		target = nil
		local best = cfg.Range
		for _, other in race.Ordered do
			if other ~= racer and other.Active then
				local distance = flatDistance(other.Chassis.Position, position)
				if distance <= best then
					best = distance
					target = other
				end
			end
		end
	end
	if not target then
		notify(racer.Player, "Nobody close enough to rob!")
		return
	end

	target.Car:SetAttribute("SpeedFactor", math.max(cfg.MinFactor, target.Car:GetAttribute("SpeedFactor") * cfg.VictimFactor))
	racer.Car:SetAttribute("SpeedFactor", math.min(cfg.MaxFactor, racer.Car:GetAttribute("SpeedFactor") * cfg.ThiefFactor))
	racer.Steals += 1

	local stolen = moveStealablePart(target, racer) or "horsepower"
	notify(racer.Player, "💰 You stole " .. target.Player.DisplayName .. "'s " .. stolen .. "!")
	notify(target.Player, "😡 " .. racer.Player.DisplayName .. " stole your " .. stolen .. "!")
end

function PowerUps.use(race, racer)
	local id = racer.PowerUp
	if not id then
		return
	end
	PowerUps.give(racer, nil)
	handlers[id](race, racer)
end

-- Called ~10x per second by the race loop.
function PowerUps.update(race)
	local t = now()

	for _, pickup in race.Track.Pickups do
		if t >= pickup.ReadyAt then
			pickup.Part.Transparency = 0.15
			for _, racer in race.Ordered do
				if racer.Active and not racer.PowerUp and flatDistance(racer.Chassis.Position, pickup.Position) < 9 then
					local id = PowerUps.roll(race, racer)
					PowerUps.give(racer, id)
					local info = Config.PowerUps[id]
					notify(racer.Player, info.Icon .. " Got " .. info.Name .. "! Press E to use")
					pickup.ReadyAt = t + Config.PickupRespawn
					pickup.Part.Transparency = 1
					break
				end
			end
		end
	end

	for i = #oils, 1, -1 do
		local oil = oils[i]
		if t > oil.Expires then
			oil.Part:Destroy()
			table.remove(oils, i)
		else
			for _, racer in race.Ordered do
				local safe = racer == oil.Owner and t < oil.SafeUntil
				if racer.Active and not safe and not isStunned(racer) and flatDistance(racer.Chassis.Position, oil.Part.Position) < 7 then
					stun(racer, Config.PowerUps.Oil.StunTime)
					notify(racer.Player, "🛢️ You hit an oil slick!")
					oil.Part:Destroy()
					table.remove(oils, i)
					break
				end
			end
		end
	end
end

function PowerUps.reset(track)
	for _, oil in oils do
		oil.Part:Destroy()
	end
	table.clear(oils)
	effectsFolder:ClearAllChildren()
	for _, pickup in track.Pickups do
		pickup.ReadyAt = 0
		pickup.Part.Transparency = 0.15
	end
end

return PowerUps
