-- Arcade driving. Runs on the driver's machine because the server gives them network
-- ownership of their car. Reads VehicleSeat input (WASD / arrows / gamepad / mobile
-- thumbstick all work) and the stats the server wrote onto the car's attributes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer

local REVERSE_FACTOR = 0.4
local BRAKE_FACTOR = 2.5
local COAST_FACTOR = 0.5
local LAUNCH_AIR_TIME = 0.6 -- seconds the drive constraint lets go after being launched
local SPINOUT_RATE = 10

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local airborneUntil = 0

local function getCar(): (Model?, VehicleSeat?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") and seat.Parent and seat.Parent:GetAttribute("IsRaceCar") then
		return seat.Parent :: Model, seat
	end
	return nil, nil
end

local function moveTowards(current: number, target: number, step: number): number
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

RunService.Heartbeat:Connect(function(dt)
	local car, seat = getCar()
	if not car then
		return
	end
	local chassis = car.PrimaryPart
	local drive = chassis and chassis:FindFirstChild("Drive")
	local steer = chassis and chassis:FindFirstChild("Steer")
	if not (drive and steer) or chassis.Anchored then
		return
	end

	local now = workspace:GetServerTimeNow()
	local locked = car:GetAttribute("Locked")
	local stunned = now < (car:GetAttribute("StunnedUntil") or 0)
	local boosting = now < (car:GetAttribute("BoostUntil") or 0)
	local topSpeed = car:GetAttribute("MaxSpeed") * car:GetAttribute("SpeedFactor")
	local accel = car:GetAttribute("Accel")
	local handling = car:GetAttribute("Handling")
	local grip = car:GetAttribute("Grip")

	rayParams.FilterDescendantsInstances = { car, player.Character }
	local hit = workspace:Raycast(chassis.Position, Vector3.new(0, -(chassis.Size.Y / 2 + 1.5), 0), rayParams)
	local grounded = hit ~= nil and os.clock() > airborneUntil
	local onRoad = hit ~= nil and hit.Instance:GetAttribute("Road") == true

	local look = chassis.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then
		return
	end
	forward = forward.Unit
	local right = Vector3.new(-forward.Z, 0, forward.X)

	local velocity = chassis.AssemblyLinearVelocity
	local forwardSpeed = velocity:Dot(forward)
	local sideSpeed = velocity:Dot(right)

	local throttle, steerInput = seat.ThrottleFloat, seat.SteerFloat
	if locked then
		throttle, steerInput = 0, 0
	end
	if stunned then
		throttle = 0
	end

	if boosting then
		topSpeed *= Config.PowerUps.Nitro.SpeedBoost
		accel *= 2.5
	end
	if hit and not onRoad then
		topSpeed *= Config.Track.OffroadSpeedFactor
	end

	local targetSpeed = if throttle >= 0 then throttle * topSpeed else throttle * topSpeed * REVERSE_FACTOR
	local rate = accel
	if throttle == 0 then
		rate = accel * COAST_FACTOR
	elseif (forwardSpeed > 1 and throttle < 0) or (forwardSpeed < -1 and throttle > 0) then
		rate = accel * BRAKE_FACTOR
	end

	local newForward = moveTowards(forwardSpeed, targetSpeed, rate * dt)
	-- Grip bleeds off sideways speed; lower grip = longer drifts.
	local newSide = if stunned then sideSpeed else sideSpeed * math.max(0, 1 - grip * dt)

	if grounded then
		drive.Enabled = true
		local planar = forward * newForward + right * newSide
		drive.PlaneVelocity = Vector2.new(planar.X, planar.Z)
	else
		drive.Enabled = false -- airborne: let physics fly the car
	end

	local yawRate
	if stunned then
		yawRate = SPINOUT_RATE
	else
		local speedScale = math.clamp(math.abs(forwardSpeed) / 25, 0, 1)
		local direction = if forwardSpeed >= 0 then 1 else -1
		-- Positive Y spins left, and SteerFloat is +1 for right, hence the minus.
		yawRate = -steerInput * handling * speedScale * direction
	end
	steer.AngularVelocity = Vector3.new(0, yawRate, 0)
end)

Remotes.Effect.OnClientEvent:Connect(function(kind, value)
	local car = getCar()
	local chassis = car and car.PrimaryPart
	if not chassis then
		return
	end
	if kind == "Launch" then
		airborneUntil = os.clock() + LAUNCH_AIR_TIME
		chassis.AssemblyLinearVelocity += value
	elseif kind == "Stop" then
		chassis.AssemblyLinearVelocity = Vector3.zero
	end
end)
