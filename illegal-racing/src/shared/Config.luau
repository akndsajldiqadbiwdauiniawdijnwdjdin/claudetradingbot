-- All tunable game numbers live here. Speeds are in studs/second.
local Config = {}

Config.Race = {
	Laps = 3,
	MinPlayers = 1, -- set to 2+ for live servers; 1 lets you test solo
	MaxPlayers = 16,
	IntermissionTime = 15,
	CountdownTime = 3,
	MaxRaceTime = 300,
	FinishGraceTime = 30, -- everyone else gets this long after the winner crosses the line
	ResultsTime = 7,
	CheckpointRadius = 32,
	ResetCooldown = 3,
}

Config.Rewards = {
	Placement = { 600, 400, 250, 150 }, -- 1st, 2nd, 3rd, 4th
	Finish = 100, -- finished, but 5th or worse
	DNF = 25,
	PerSteal = 50,
}

Config.Track = {
	Samples = 96, -- road segments around the loop
	CheckpointEvery = 8, -- one checkpoint every N segments
	RoadWidth = 48,
	BaseRadius = 300,
	OffroadSpeedFactor = 0.55,
}

Config.Cars = {
	{
		Id = "Beater",
		Name = "Rusty Beater",
		Price = 0,
		MaxSpeed = 90,
		Accel = 40,
		Handling = 2.2,
		Grip = 5,
		Color = Color3.fromRGB(150, 110, 80),
		Accent = Color3.fromRGB(90, 70, 50),
	},
	{
		Id = "Tuner",
		Name = "Street Tuner",
		Price = 2500,
		MaxSpeed = 105,
		Accel = 50,
		Handling = 2.5,
		Grip = 5.5,
		Color = Color3.fromRGB(40, 120, 255),
		Accent = Color3.fromRGB(255, 255, 255),
	},
	{
		Id = "Muscle",
		Name = "Muscle Car",
		Price = 8000,
		MaxSpeed = 125,
		Accel = 60,
		Handling = 2.3,
		Grip = 4.5,
		Color = Color3.fromRGB(200, 30, 30),
		Accent = Color3.fromRGB(20, 20, 20),
	},
	{
		Id = "Supercar",
		Name = "Supercar",
		Price = 25000,
		MaxSpeed = 145,
		Accel = 72,
		Handling = 2.8,
		Grip = 6.5,
		Color = Color3.fromRGB(255, 200, 0),
		Accent = Color3.fromRGB(30, 30, 30),
	},
	{
		Id = "Hypercar",
		Name = "Hypercar",
		Price = 75000,
		MaxSpeed = 165,
		Accel = 85,
		Handling = 3.0,
		Grip = 7,
		Color = Color3.fromRGB(150, 0, 255),
		Accent = Color3.fromRGB(0, 255, 200),
	},
}

Config.CarsById = {}
for _, car in Config.Cars do
	Config.CarsById[car.Id] = car
end

-- Upgrades are global (they apply to whichever car is equipped).
Config.Upgrades = {
	{ Id = "Engine", Name = "Engine", Stat = "MaxSpeed", PerLevel = 0.06, MaxLevel = 5, BaseCost = 500 },
	{ Id = "Turbo", Name = "Turbo", Stat = "Accel", PerLevel = 0.1, MaxLevel = 5, BaseCost = 400 },
	{ Id = "Tires", Name = "Tires", Stat = "Handling", PerLevel = 0.06, MaxLevel = 5, BaseCost = 400 },
}

function Config.upgradeCost(upgrade, currentLevel: number): number
	return math.floor(upgrade.BaseCost * 2 ^ currentLevel)
end

function Config.getCarStats(carId: string, upgrades)
	local car = Config.CarsById[carId] or Config.Cars[1]
	local stats = {
		MaxSpeed = car.MaxSpeed,
		Accel = car.Accel,
		Handling = car.Handling,
		Grip = car.Grip,
	}
	for _, upgrade in Config.Upgrades do
		local level = (upgrades and upgrades[upgrade.Id]) or 0
		stats[upgrade.Stat] *= 1 + upgrade.PerLevel * level
	end
	return stats
end

Config.PowerUps = {
	Nitro = { Name = "Nitro", Icon = "🔥", Weight = 30, Duration = 2.5, SpeedBoost = 1.6 },
	Oil = { Name = "Oil Slick", Icon = "🛢️", Weight = 25, Lifetime = 20, StunTime = 1.5 },
	Rocket = { Name = "Rocket", Icon = "🚀", Weight = 20, StunTime = 1.5, Speed = 260 },
	EMP = { Name = "EMP Blast", Icon = "⚡", Weight = 15, Radius = 70, StunTime = 1.2 },
	Steal = {
		Name = "Steal Part",
		Icon = "💰",
		Weight = 20,
		Range = 120,
		VictimFactor = 0.88, -- victim keeps 88% of their speed for the rest of the race
		ThiefFactor = 1.08,
		MinFactor = 0.6,
		MaxFactor = 1.4,
	},
}
Config.PowerUpOrder = { "Nitro", "Oil", "Rocket", "EMP", "Steal" }
-- Racers in the back half of the pack get these weights multiplied (rubber-banding).
Config.CatchUpPowerUps = { Rocket = 2, Steal = 2 }
Config.PickupRespawn = 6

-- Fill these in after creating the passes/products on the Creator Dashboard. 0 = disabled.
Config.Monetization = {
	DoubleCashPassId = 0,
	CashProducts = {
		-- [productId] = cash amount, e.g. [123456789] = 5000,
	},
}

return Config
