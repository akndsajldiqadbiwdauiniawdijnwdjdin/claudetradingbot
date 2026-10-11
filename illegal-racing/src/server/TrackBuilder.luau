-- Builds the whole race track from code, so the place works with an empty baseplate.
-- The track is a wobbly closed loop; swap the shape formula in build() to make new tracks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local TrackBuilder = {}

local ROAD_TOP = 1 -- y of the driving surface
local ASPHALT = Color3.fromRGB(45, 45, 50)
local CURB_RED = Color3.fromRGB(200, 30, 30)
local CURB_WHITE = Color3.fromRGB(235, 235, 235)

local function makePart(parent: Instance, props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		part[key] = value
	end
	part.Parent = parent
	return part
end

local function addSign(part: BasePart, text: string)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = gui
		gui.Parent = part
	end
end

local function rightOf(forward: Vector3): Vector3
	return Vector3.new(-forward.Z, 0, forward.X)
end

function TrackBuilder.build()
	local cfg = Config.Track
	local existing = workspace:FindFirstChild("Track")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Track"
	folder.Parent = workspace

	local R = cfg.BaseRadius
	local W = cfg.RoadWidth
	local N = cfg.Samples

	makePart(folder, {
		Name = "Ground",
		Size = Vector3.new(R * 3.2, 2, R * 3.2),
		CFrame = CFrame.new(0, -1, 0),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(70, 130, 60),
	})

	-- Sample the loop shape.
	local points = table.create(N)
	for i = 1, N do
		local t = (i - 1) / N * math.pi * 2
		local r = R * (1 + 0.22 * math.sin(3 * t) + 0.12 * math.cos(2 * t))
		points[i] = Vector3.new(math.cos(t) * r, ROAD_TOP, math.sin(t) * r * 0.75)
	end
	local function wrap(i: number): number
		return (i - 1) % N + 1
	end
	local function direction(i: number): Vector3
		return (points[wrap(i + 1)] - points[wrap(i)]).Unit
	end

	-- Road + curbs.
	local half = Vector3.new(0, 0.5, 0)
	for i, p in points do
		local q = points[wrap(i + 1)]
		local length = (q - p).Magnitude
		local cf = CFrame.lookAt((p + q) / 2 - half, q - half)
		local road = makePart(folder, {
			Name = "Road",
			Size = Vector3.new(W, 1, length + W * 0.35), -- overlap hides gaps on bends
			CFrame = cf,
			Material = Enum.Material.Asphalt,
			Color = ASPHALT,
		})
		road:SetAttribute("Road", true)

		for _, side in { -1, 1 } do
			local curb = makePart(folder, {
				Name = "Curb",
				Size = Vector3.new(2, 1.2, length + 1),
				CFrame = cf * CFrame.new(side * (W / 2 + 1), 0.1, 0),
				Material = Enum.Material.SmoothPlastic,
				Color = if i % 2 == 0 then CURB_RED else CURB_WHITE,
			})
			curb:SetAttribute("Road", true)
		end
	end

	-- Checkpoints (checkpoint 1 is the start/finish line).
	local checkpoints = {}
	for i = 1, N, cfg.CheckpointEvery do
		table.insert(checkpoints, { Position = points[i], Forward = direction(i), Sample = i })
	end

	-- Start/finish gate.
	local startCf = CFrame.lookAt(points[1], points[1] + direction(1))
	makePart(folder, {
		Name = "StartLine",
		Size = Vector3.new(W, 0.1, 4),
		CFrame = startCf * CFrame.new(0, 0.05, 0),
		Material = Enum.Material.Neon,
		Color = CURB_WHITE,
		CanCollide = false,
	})
	for _, side in { -1, 1 } do
		makePart(folder, {
			Name = "GatePillar",
			Size = Vector3.new(3, 24, 3),
			CFrame = startCf * CFrame.new(side * (W / 2 + 4), 12, 0),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(30, 30, 30),
		})
	end
	local banner = makePart(folder, {
		Name = "GateBanner",
		Size = Vector3.new(W + 11, 6, 2),
		CFrame = startCf * CFrame.new(0, 25, 0),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 80, 0),
	})
	addSign(banner, "ILLEGAL RACING")

	-- Power-up boxes: a row of three shortly after some checkpoints.
	local pickups = {}
	for _, cpIndex in { 3, 6, 9 } do
		local cp = checkpoints[cpIndex]
		if cp then
			local i = wrap(cp.Sample + 2)
			local p, right = points[i], rightOf(direction(i))
			for _, offset in { -W * 0.3, 0, W * 0.3 } do
				local position = p + right * offset + Vector3.new(0, 3, 0)
				local box = makePart(folder, {
					Name = "PowerUpBox",
					Size = Vector3.new(4, 4, 4),
					CFrame = CFrame.new(position) * CFrame.Angles(math.rad(45), math.rad(45), 0),
					Material = Enum.Material.Neon,
					Color = Color3.fromRGB(255, 170, 0),
					Transparency = 0.15,
					CanCollide = false,
				})
				table.insert(pickups, { Part = box, Position = position, ReadyAt = 0 })
			end
		end
	end

	-- Jump ramps on the left lane (risky but fun).
	for _, fraction in { 0.3, 0.72 } do
		local i = math.floor(N * fraction)
		local forward = direction(i)
		local angle, length, thickness = math.rad(12), 26, 1
		local center = points[i]
			- rightOf(forward) * (W * 0.22)
			+ Vector3.new(0, (length / 2) * math.sin(angle) - (thickness / 2) * math.cos(angle), 0)
		local ramp = makePart(folder, {
			Name = "Ramp",
			Size = Vector3.new(W * 0.4, thickness, length),
			-- Tilts the front edge up, so the back edge sits flush with the road.
			CFrame = CFrame.lookAt(center, center + forward) * CFrame.Angles(angle, 0, 0),
			Material = Enum.Material.DiamondPlate,
			Color = Color3.fromRGB(255, 200, 0),
		})
		ramp:SetAttribute("Road", true)
	end

	-- Lobby spawn in the infield.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.CFrame = CFrame.new(0, 0.5, 0)
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(255, 80, 0)
	spawn.Parent = folder

	-- Grid slots follow the road backwards from the start line, two cars per row.
	local function gridCFrame(slot: number): CFrame
		local row = (slot - 1) // 2
		local column = (slot - 1) % 2
		local i = wrap(1 - (row + 1))
		local forward = direction(i)
		local position = points[i]
			+ rightOf(forward) * (if column == 0 then -W * 0.22 else W * 0.22)
			+ Vector3.new(0, 1.4, 0)
		return CFrame.lookAt(position, position + forward)
	end

	return {
		Folder = folder,
		Checkpoints = checkpoints,
		Pickups = pickups,
		GridCFrame = gridCFrame,
	}
end

return TrackBuilder
