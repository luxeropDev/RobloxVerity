# Architecture

## 1. DataModel mapping (Rojo, `default.project.json`)
| Repo path | DataModel location | Kind |
|---|---|---|
| `src/ReplicatedStorage/Shared/` | `ReplicatedStorage.Shared` | ModuleScripts (client + server) |
| `src/ServerScriptService/Main.server.lua` | `ServerScriptService.Main` | Script (server entry) |
| `src/ServerScriptService/Services/` | `ServerScriptService.Services` | ModuleScripts |
| `src/ServerScriptService/Services/NightEvents/` | `ServerScriptService.Services.NightEvents` | ModuleScripts (one per event) |
| `src/ServerScriptService/Lib/` | `ServerScriptService.Lib` | Pure ModuleScripts |
| `src/ServerScriptService/World/` | `ServerScriptService.World` | World + SUNNY builders |
| `src/StarterPlayer/StarterPlayerScripts/Client.client.lua` | `StarterPlayerScripts.Client` | LocalScript (client entry) |
| `src/StarterPlayer/StarterPlayerScripts/Controllers/` | `StarterPlayerScripts.Controllers` | ModuleScripts |
| `tests/TestRunner.lua`, `tests/unit`, `tests/integration` | `ServerStorage.Tests` | Test harness + specs |

Deviation from the original brief: the world builder is `ServerScriptService/World/WorldBootstrap.lua` (a ModuleScript called by `Main`) instead of `src/Workspace/WorldBootstrap.server.lua`. A separate Workspace Script would race with service startup; calling it from `Main` guarantees the world exists before services attach prompts.

## 2. Boot sequence (`Main.server.lua`)
1. `ConfigValidator.validate(GameConfig)` → warnings only.
2. `Remotes.init()` → creates `ReplicatedStorage.Remotes/*` and `ReplicatedStorage.GameState`.
3. `WorldBootstrap.build(seed)` → returns the `world` reference table.
4. `init(services, world)` for every service, then `start()` in order: PlayerState → Camp → Resource → Objective → Sunny → NightEvent → Phase.
5. `Services/Registry` is filled for tests. Boot is wrapped in `pcall`; failure is logged and stored in `Registry.BootError`.

## 3. Services
| Module | Owns | Key API |
|---|---|---|
| `PhaseService` | Round loop, phase timers, night counter, endings, recap, restart votes | `getPhase`, `getNight`, `getEscalation`, `getTimings`, `isTestMode`, `requestEnding`, signal `PhaseChanged(phase, night, round)` |
| `PlayerStateService` | Per-player inventory, capture/rescue, hiding, spook, stats, Glow/titles, team Courage, notifications | `getRoot`, `canAct`, `isWithin`, `allowPrompt`, `isTargetable`, `addResource`, `capture`, `release`, `unhide`, `awardGlow`, `changeCourage`, `notify[All]`, `playSound`, `makePrompt` |
| `CampService` | Fuel, light, safe/repel radius, stockpile, deposits, snacks, 4 upgrades, barricade HP | `getSafeRadius`, `getRepelRadius`, `isInSafeZone`, `addFuel`, `deposit`, `cookSnack`, `requestUpgrade`, `spendStock`, `hitBarricade` |
| `ResourceService` | Node HP, depletion, respawn, shifting | `tryGather`, `shiftNodes`, `reset` |
| `ObjectiveService` | Objectives, clues, radio, bridge | `progress`, `set`, `awardClue`, `isClueFound`, `isRadioFixed`, `isBridgeRepaired`, `getCluesFound` |
| `SunnyService` | Perception, state execution, movement, speech, capture | `say`, `reportNoise`, `lure`, `appearAtLightEdge`, `getState`, `getTarget`, `onEnding` |
| `SunnyNavigator` | Pathfinding with timeout, stuck detection, fallback | `setGoal`, `step`, `reset` |
| `NightEventService` | Schedule + run + clean events | `runEvent`, `stopAll`, `getEventIds` |

Cross-service calls go through the `services` table passed to `init`, so there are no circular `require`s.

## 4. Pure libraries (`Lib/`, unit-tested)
`SunnyBrain` (state transitions, suspicion gain, target pick), `EventScheduler` (night plan), `InventoryLogic` (capacity, all-or-nothing spend), `RateLimiter` (sliding window), `Awards` (recap titles, Glow titles), `ConfigValidator`, `Trove` (cleanup), `Signal`.

## 5. Phase state machine
```
Intermission ──(≥1 player)──► Day ─► Sunset ─► Night ─┬─(defeat)────────────► Results ─► Intermission
                               ▲                      └─► Dawn ─┬─(ending)──► Results
                               └────────────────────────────────┘ (no ending: next Day)
```
- Durations: `GameConfig.Phases.Normal` or `.Test` (solo Studio, `SoloTestMode = "Auto"`).
- Endings decided at Dawn (`pickEnding`) or by `requestEnding` during Night (Courage 0 / all captured).
- Results ends early when restart votes ≥ ceil(players / 2).
- The round body runs in `pcall`; a crash logs a warning and restarts from Intermission.

## 6. SUNNY
- Tick every `Sunny.TickInterval` (0.1 s): perception (raycast LOS to each eligible player within 1.2 × detect radius, `RespectCanCollide = true`), suspicion update, target validation, `SunnyBrain.decide`, then act.
- Movement: unanchored, server-owned assembly with `AlignPosition` (speed = `MaxVelocity`) + `AlignOrientation`. All parts are `CanCollide = false`.
- Navigation: `PathfindingService:CreatePath` per compute, `ComputeAsync` in `pcall` inside `task.spawn`; results discarded if superseded or older than `Path.Timeout`; failed computes fall back to a direct line; no progress for `Path.StuckTime` → drift over obstacles at `Path.DriftHeight`.
- Hard rule at night: every goal and step is clamped outside `CampService.getRepelRadius() + LightEdgeBuffer`.

## 7. Networking
State that changes often is replicated through **attributes**, events through **RemoteEvents**.

| Channel | Direction | Payload | Validation / limit |
|---|---|---|---|
| `GameState` attributes | S→C | Phase, PhaseEndsAt, Night, Round, TestMode, Fuel, FuelMax, SafeRadius, FireLevel, Courage, CourageMax, SunnyState, RestartVotes, RestartNeeded, BarricadeHP | — |
| Player attributes | S→C | Wood, Stone, Food, Token, Capacity, Glow, Title, Status, Hidden, Captured | — |
| `Notify` | S→C | text, kind | — |
| `SunnySpeech` | S→C | text, duration | — |
| `ObjectivesUpdated` | S→C | objective list | — |
| `StockpileUpdated` | S→C | stock, upgrade levels | — |
| `ClueFound` | S→C | title, text, finder | — |
| `SunnyAlert` | S→C (one player) | "Clear"/"Watched"/"Chased" | — |
| `PlaySound` | S→C | key, position?, repeat? | client clamps repeat ≤ 8 |
| `Recap` | S→C | recap table or nil | — |
| `RequestUpgrade` | C→S | upgradeId | 4 / 2 s; string type, known id, phase ≠ Night/Intermission/Results, alive & not captured/hidden, within `Camp.InteractRadius`, level < max, all-or-nothing cost |
| `RequestRestart` | C→S | — | 3 / 5 s; Results phase only; one vote per player |
| `RequestUnhide` | C→S | — | 4 / 2 s; only affects the caller |
| ProximityPrompts | C→S (engine) | — | shared 12 / 2 s per player + per-action distance re-check on the server, state checks |

## 8. Cleanup model
- Each night event gets a `Trove`; destroyed at its duration, at night end (`PhaseChanged`), and at round reset (`stopAll`).
- Lanterns and fences live in `CampService` troves; cleaned on `reset`.
- Per-player tables are cleared in `PlayerRemoving` handlers (records, limiters, suspicion, alerts, votes, hiding spot occupancy).
- Long-lived loops (one each): PlayerState tick 4 Hz, Camp tick 2 Hz, Resource respawn 1 Hz, SUNNY 10 Hz, Phase loop. All use `task.wait` and `pcall` their bodies.

## 9. Client
`Client.client.lua` inits/starts Audio → Atmosphere → HUD → Interaction inside `pcall`. Controllers read attributes and remotes; the only client→server traffic is the three request remotes and ProximityPrompt activations.

## 10. Known architectural limits
- No persistence (Glow resets per server).
- Night events are trusted server code; adding an event = new module + entry in `NightEventService.EVENT_MODULES` + `GameConfig.Events.Definitions`.
- `tools/check_project.py` is heuristic; Luau type checking (`luau-analyze`) and linting (`selene`) are recommended once installed.
