-- Builds a drivable car. The invisible "Chassis" box is the only physical part; everything
-- else is decoration welded to it. Driving uses two constraints on the chassis that the
-- driver's client controls (see client/Drive.client.luau):
--   Drive (LinearVelocity, horizontal plane only, so gravity and jumps still work)
--   Steer (AngularVelocity, yaw only, which also keeps the car from flipping)
--
-- Custom models: put a Model named after the car Id (e.g. "Muscle") inside
-- ReplicatedStorage.CarModels and it replaces the default blocky body. See README.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local CarBuilder = {}

local CHASSIS_SIZE = Vector3.new(6, 2.4, 11)
local GLASS = Color3.fromRGB(30, 40, 55)
local TIRE = Color3.fromRGB(20, 20, 20)

local function weld(part: BasePart, chassis: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = chassis
	constraint.Part1 = part
	constraint.Parent = part
end
CarBuilder.weld = weld

local function decor(parent: Instance, chassis: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	if shape then
		part.Shape = shape
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = chassis.CFrame * offset
	weld(part, chassis)
	part.Parent = parent
	return part
end

local function buildDefaultBody(model: Model, chassis: BasePart, def)
	local W, H, L = CHASSIS_SIZE.X, CHASSIS_SIZE.Y, CHASSIS_SIZE.Z
	local bottom = -H / 2

	local body = Instance.new("Folder")
	body.Name = "Body"
	body.Parent = model

	decor(body, chassis, "Shell", Vector3.new(W, 1.2, L), CFrame.new(0, bottom + 1.6, 0), def.Color)
	decor(body, chassis, "Cabin", Vector3.new(W - 1, 1.3, L * 0.42), CFrame.new(0, bottom + 2.85, L * 0.08), GLASS, Enum.Material.Glass)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			-- Cylinders point along X, which is already the axle direction.
			decor(body, chassis, "Wheel", Vector3.new(1.2, 2.6, 2.6), CFrame.new(x * (W / 2 - 0.2), bottom + 1.3, z * L * 0.32), TIRE, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		end
		decor(body, chassis, "Headlight", Vector3.new(1.4, 0.5, 0.2), CFrame.new(x * (W / 2 - 1), bottom + 1.7, -L / 2 - 0.05), Color3.fromRGB(255, 255, 220), Enum.Material.Neon)
		decor(body, chassis, "Taillight", Vector3.new(1.4, 0.5, 0.2), CFrame.new(x * (W / 2 - 1), bottom + 1.7, L / 2 + 0.05), Color3.fromRGB(255, 30, 30), Enum.Material.Neon)
	end

	-- Parts other racers can rip off with the Steal power-up.
	local stealable = Instance.new("Folder")
	stealable.Name = "Stealable"
	stealable.Parent = model
	decor(stealable, chassis, "Spoiler", Vector3.new(W - 0.4, 0.3, 1.4), CFrame.new(0, bottom + 3.0, L / 2 - 0.8), def.Accent)
	decor(stealable, chassis, "Hood Scoop", Vector3.new(1.6, 0.6, 2), CFrame.new(0, bottom + 2.5, -L * 0.28), def.Accent)
	decor(stealable, chassis, "Front Bumper", Vector3.new(W + 0.3, 0.7, 0.6), CFrame.new(0, bottom + 1.2, -L / 2 - 0.3), def.Accent)
	decor(stealable, chassis, "Rear Bumper", Vector3.new(W + 0.3, 0.7, 0.6), CFrame.new(0, bottom + 1.2, L / 2 + 0.3), def.Accent)
end

-- Swaps in ReplicatedStorage.CarModels[carId] if it exists. The model must face -Z
-- (Roblox "front") and its pivot should sit at the centre of the car.
local function applyCustomModel(model: Model, chassis: BasePart, carId: string)
	local folder = ReplicatedStorage:FindFirstChild("CarModels")
	local template = folder and folder:FindFirstChild(carId)
	if not (template and template:IsA("Model")) then
		return
	end

	local custom = template:Clone()
	custom.Name = "CustomBody"
	custom:PivotTo(chassis.CFrame * CFrame.new(0, template:GetAttribute("YOffset") or 0, 0))
	for _, descendant in custom:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy() -- never run scripts that ride along in imported/free models
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			weld(descendant, chassis)
		end
	end

	model.Body:Destroy()
	local customStealable = custom:FindFirstChild("Stealable")
	if customStealable then
		model.Stealable:Destroy()
		customStealable.Parent = model
	end
	custom.Parent = model
end

function CarBuilder.build(player: Player, carId: string, stats, cframe: CFrame, parent: Instance): Model
	local def = Config.CarsById[carId] or Config.Cars[1]

	local model = Instance.new("Model")
	model.Name = player.Name .. "_Car"

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = CHASSIS_SIZE
	chassis.CFrame = cframe
	chassis.Transparency = 1
	-- Zero friction: the Drive constraint does all the gripping.
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	buildDefaultBody(model, chassis, def)
	applyCustomModel(model, chassis, def.Id)

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.CFrame = chassis.CFrame * CFrame.new(0, -CHASSIS_SIZE.Y / 2 + 2.2, CHASSIS_SIZE.Z * 0.12)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false -- only the server seats players
	seat.Massless = true
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.HeadsUpDisplay = false
	weld(seat, chassis)
	seat.Parent = model

	local root = Instance.new("Attachment")
	root.Name = "Root"
	root.Parent = chassis

	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = root
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	drive.PrimaryTangentAxis = Vector3.xAxis
	drive.SecondaryTangentAxis = Vector3.zAxis
	drive.PlaneVelocity = Vector2.zero
	drive.MaxForce = 400000
	drive.Parent = chassis

	local steer = Instance.new("AngularVelocity")
	steer.Name = "Steer"
	steer.Attachment0 = root
	steer.RelativeTo = Enum.ActuatorRelativeTo.World
	steer.AngularVelocity = Vector3.zero
	steer.MaxTorque = 10000000
	steer.Parent = chassis

	model:SetAttribute("IsRaceCar", true)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("CarId", def.Id)
	model:SetAttribute("MaxSpeed", stats.MaxSpeed)
	model:SetAttribute("Accel", stats.Accel)
	model:SetAttribute("Handling", stats.Handling)
	model:SetAttribute("Grip", stats.Grip)
	model:SetAttribute("SpeedFactor", 1)
	model:SetAttribute("BoostUntil", 0)
	model:SetAttribute("StunnedUntil", 0)
	model:SetAttribute("Locked", true)

	model.Parent = parent
	return model
end

return CarBuilder
