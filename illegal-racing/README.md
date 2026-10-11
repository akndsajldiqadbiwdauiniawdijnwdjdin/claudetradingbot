# Illegal Racing (Roblox)

Arcade kart-style racing where cheating is the point: nitro, oil slicks, homing rockets,
EMP blasts, and **Steal Part**, which rips a part off the car ahead (they get slower,
you get faster, and the part stacks on your roof as a trophy).

Everything is built from code (track, cars, UI), so it runs in an empty Baseplate place.

## What's in the box

| File | Does |
| --- | --- |
| `src/shared/Config.luau` | **All tuning**: laps, rewards, cars, upgrades, power-ups, monetization IDs |
| `src/shared/Remotes.luau` | Client/server remotes |
| `src/server/RaceManager.luau` | Intermission → countdown → race → results loop, checkpoints, laps, standings, rewards |
| `src/server/TrackBuilder.luau` | Generates the loop track, curbs, start gate, ramps, power-up boxes, lobby spawn |
| `src/server/CarBuilder.luau` | Builds the car (physics chassis + decorative body), swaps in custom models |
| `src/server/PowerUps.luau` | Pick-ups and all weapon effects |
| `src/server/PlayerData.luau` | DataStore saving (cash, wins, owned cars, upgrades) + leaderstats |
| `src/server/Shop.luau` | Garage purchases, validated on the server |
| `src/server/Monetization.luau` | 2x Cash game pass + cash developer products |
| `src/client/Drive.client.luau` | Arcade driving physics (runs on the driver's machine) |
| `src/client/Hud.client.luau` | HUD, notifications, garage UI, E/R input + mobile buttons |

**Game loop:** race → earn cash (placement + steals, 2x with pass) → buy faster cars and
upgrades in the Garage → race again. Back-of-pack racers roll Rockets/Steals more often.

**Controls:** WASD / arrows / gamepad / mobile stick to drive, **E** use power-up,
**R** reset to last checkpoint (if stuck or flipped).

## Setup (one time)

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then in this folder run `rokit install`
   (installs Rojo). Or install Rojo any other way.
2. In Roblox Studio install the **Rojo** plugin (Creator Store).
3. Create a new place from the **Baseplate** template. Delete the default `Baseplate` and
   `SpawnLocation` (the game builds its own ground and spawn).
4. In this folder run `rojo serve`, then in Studio click **Rojo → Connect**.
5. Press **Play**. With `MinPlayers = 1` a solo race starts after the 15 s intermission.
6. To save data in Studio: **Game Settings → Security → Enable Studio Access to API Services**
   (the game must be published first).

To test multiplayer: **Test → Clients and Servers → 2+ players → Start**.

Before going live, set `Config.Race.MinPlayers = 2`.

## Tuning ideas

- Car feel: `MaxSpeed`, `Accel`, `Handling` (turn rate), `Grip` (low = drifty) in `Config.Cars`.
- New track shape: change the radius formula in `TrackBuilder.build()`
  (`r = R * (1 + 0.22*sin(3t) + 0.12*cos(2t))`). Bigger multipliers = twistier track.
- New power-up: add an entry to `Config.PowerUps` + `Config.PowerUpOrder`, then a
  `handlers.YourId` function in `PowerUps.luau`.

## Monetization

Create a game pass and developer products on the Creator Dashboard, then put the IDs in
`Config.Monetization`. Add buttons that call
`MarketplaceService:PromptGamePassPurchase` / `PromptProductPurchase` wherever you like.

## Custom car models

The physics never touch the visual body, so you can swap any model in without changing
handling. Put a **Model** named exactly like a car Id (`Beater`, `Tuner`, `Muscle`,
`Supercar`, `Hypercar`) in `ReplicatedStorage.CarModels` and it replaces the blocky body.

Model requirements:
- Faces **-Z** (Roblox's "front"; the Front face of a part points that way).
- Pivot at the centre of the car, about 6 × 11 studs footprint. Set a `YOffset` number
  attribute on the model to raise or lower it.
- Optional: a `Stealable` folder of parts (spoiler, bumpers…) that Steal Part can rip off.
- Any scripts inside are deleted automatically (free models can contain backdoors).

Ways to get models:

1. **Roblox's own AI (Cube 3D):** in Studio's Assistant, ask it to generate a mesh, e.g.
   `/generate low-poly red muscle car`. Fastest path, already inside Roblox.
2. **Text/image-to-3D tools** (Meshy, Tripo, Rodin, etc.): generate, export **FBX/OBJ/GLB**,
   then **File → Import 3D** in Studio. Ask for "low poly, game-ready" and keep the triangle
   count low. Read each tool's license for commercial use.
3. **Free CC0 packs** such as Kenney's *Car Kit*: import the same way, no licensing worries.
4. **Blender:** model or clean up AI output (fix scale, centre the pivot, point it to -Z),
   then export FBX.
5. **Creator Store:** fine for props, but check every model for hidden scripts.

You can also save models as `.rbxm` files in `assets/CarModels/`; Rojo syncs that folder
into `ReplicatedStorage.CarModels`. Pick one approach: while Rojo is connected, it manages
that folder and removes models you added by hand in Studio.
