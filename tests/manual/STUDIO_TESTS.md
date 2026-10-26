# Manual Studio Tests

Status legend: `[ ]` not run. None of these have been executed yet: the project was built in a cloud environment without Roblox Studio. Record date, tester and result when run.

Setup: `docs/STUDIO_SETUP.md`. Turn on `GameConfig.Debug.LogSunnyStates` for SUNNY tests.

| # | Test | Steps | Expected |
|---|---|---|---|
| M1 | Boot | Play solo. Watch Output. | `[Main] World built …` and `[Main] … ready`. No errors. HUD shows "SOLO TEST MODE". |
| M2 | First 30 seconds | Spawn. | Spawn at camp next to the fire. SUNNY floats in and greets within ~5 s. Title card shows. A ribboned tree is within ~30 studs. Objectives panel lists 6 objectives. |
| M3 | Gathering | Hold E on a ribboned tree 4 times. | "+1 Wood" toasts, backpack updates, tree turns ghostly after 4 hits, prompt disappears, returns after `RespawnTime`. "Gather wood" progresses. |
| M4 | Capacity | Gather until 10 items. | "Backpack is full" toast; no more items added. |
| M5 | Deposit + upgrade | Deposit at crate, open CAMP (C key / button / workbench). Build Stronger Fire when affordable. | Stockpile shown; build succeeds once; safe ring grows; second click when unaffordable shows "Need …". |
| M6 | Invalid upgrades | Command bar (server): `local S=require(game.ServerScriptService.Services.Registry).Services; S.CampService.requestUpgrade(game.Players:GetPlayers()[1], "Nope")` | Nothing changes, no error. |
| M7 | Out-of-range interaction | Carry items, walk > 20 studs from the crate, then run `S.CampService.deposit(game.Players:GetPlayers()[1])` in the server command bar. | No deposit; inventory unchanged. |
| M8 | Repeated remote spam | Client command bar: `for i=1,50 do game.ReplicatedStorage.Remotes.RequestUpgrade:FireServer("FireRing") end` | At most 4 processed per 2 s; at most one upgrade bought per affordable level. |
| M9 | Phase transitions | Let the day run out. | Day → Sunset (warning) → Night (lighting turns blue-green, fog) → Dawn → Day 2. Timer counts down correctly. |
| M10 | SUNNY fairness | At night walk into the dark near SUNNY. | "SUNNY IS WATCHING YOU" + yellow vignette for ≥ 3.5 s before any chase; chase vignette pink; walking at default speed outruns SUNNY. |
| M11 | Light safety | Get chased, run into the fire ring. | SUNNY stops at the ring edge, says a light line, retreats. Never enters the ring. |
| M12 | Hiding | Get stalked, hide in a bush. | Player anchored inside, LEAVE button shown, Space/ButtonA leaves. SUNNY searches, does not capture. Auto-exit after 25 s. |
| M13 | Capture + rescue | Let SUNNY catch you (2 clients). | Caught player in Giggle Cage, carried items lost, Courage −1. Second client holds Rescue at the cage lock → freed to camp with 6 s immunity. |
| M14 | Pathfinding failure | At night let the fire burn out, get stalked, then stand inside the cabin so walls block the path. | No errors; SUNNY either paths through the door or drifts above obstacles; it never freezes > 3 s. |
| M15 | Night events | Server command bar: `for _,id in ipairs(S.NightEventService.getEventIds()) do S.NightEventService.runEvent(id) end` | Each event shows its toast/object. After `S.NightEventService.stopAll()`, `workspace.NightEventObjects` is empty. |
| M16 | Event cleanup at dawn | Let a night end while events are active. | All event objects removed at Dawn. |
| M17 | Defeat + restart | Solo: get captured until Courage 0. | Night ends early, Results shows "Lights Out", PLAY AGAIN works; new round resets fire, stockpile, nodes, objectives; player respawns at camp. |
| M18 | Victory | Fix radio, repair 3 bridge stages, survive night 3. | Dawn → Results "Over the Bridge". With all 6 clues: "SUNNY's Goodbye" and SUNNY powers down. |
| M19 | Concurrent gathering | 2 clients gather the same Token sparkle (1 hit) at the same time. | Exactly one player receives the token. |
| M20 | Join mid-round | Start 2 clients, join a third during Night. | Third player gets objectives, stockpile and HUD state immediately; spawns at camp. |
| M21 | Leave mid-capture / mid-hide | Client leaves while caged or hidden. | No errors; hiding spot becomes available; rescue prompt disables if nobody is caged. |
| M22 | Respawn | Reset character (Esc → Reset) by day, at night, while hidden, while caged. | Respawn at camp (caged players back in cage). Hidden state cleared. |
| M23 | Mobile controls | Device emulator: iPhone and iPad. | HUD scales and is readable; prompts tappable; CAMP and LEAVE buttons reachable; no overlap with the thumbstick/jump button. |
| M24 | Performance | 3 full rounds with MicroProfiler and Developer Console → Memory. | Instance count returns to baseline after each round; server heartbeat ≥ 55 Hz; no growing script memory. |
| M25 | TestRunner | `require(game.ServerStorage.Tests.TestRunner).run()` | All unit + integration specs pass. |
