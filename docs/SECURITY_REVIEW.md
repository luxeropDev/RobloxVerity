# Security Review

Scope: all server entry points reachable by a client. Method: static code review only (no runtime exploit testing). Reviewers: main session, plus one independent review subagent run with the qa-security brief (see section 5).

## 1. Client-reachable entry points
| Entry | Handler | Validation |
|---|---|---|
| `RequestUpgrade(upgradeId)` | `CampService.requestUpgrade` | Rate limit 4/2 s; `type(upgradeId) == "string"`; id must exist in `GameConfig.Upgrades`; phase not Night/Intermission/Results; `canAct` (alive, not captured, not hidden); within `Camp.InteractRadius` of the fire; next level exists; `InventoryLogic.spend` all-or-nothing |
| `RequestRestart()` | `PhaseService.onRestartRequest` | Rate limit 3/5 s; Results phase only; vote stored once per Player key; votes of departed players dropped |
| `RequestUnhide()` | `PlayerStateService` | Rate limit 4/2 s; acts only on the caller; no-op if not hidden |
| Gather prompt | `ResourceService.tryGather` | Shared prompt limiter 12/2 s + per-player gather cooldown; phase; `canAct`; server distance ≤ `Gathering.MaxDistance`; node not depleted; capacity |
| Campfire / crate / pot prompts | `CampService.addFuel/deposit/cookSnack` | Prompt limiter; `canAct`; server distance to the object; resource and Courage checks |
| Hide prompt | `PlayerStateService.onHide` | Prompt limiter; not captured/hidden; spot not occupied; server distance |
| Rescue prompt | `PlayerStateService.onRescue` | Prompt limiter; rescuer `canAct`; server distance to the lock; rescuer cannot free themself |
| Clue / radio / bridge prompts | `ObjectiveService` | Prompt limiter; `canAct`; server distance; night-only clues checked against phase; costs all-or-nothing; idempotent (`cluesFound`, `radioFixed`, stage cap) |
| Event prompts (crate, sign) | Night event modules | `ctx.canInteract` (limiter + `canAct` + distance); crate opens once (`opened` flag set before any yield) |

ProximityPrompt `Triggered` is treated as untrusted: exploit tools can fire prompts from any distance, so every handler re-checks distance on the server.

## 2. Data the client cannot influence
Phase and timers, inventory and stockpile, upgrade levels, objective progress, clue state, Courage, capture/release, SUNNY's decisions and position, event selection, rewards (Glow) and recap. Clients never send positions, amounts or other players' references.

## 3. Race conditions considered
| Scenario | Handling |
|---|---|
| Two players gather the last hit of a node in the same frame | Handlers run sequentially on the server thread; check and decrement happen with no yield in between, so only one succeeds |
| Double spend on upgrades/radio/bridge | `InventoryLogic.spend` checks and deducts without yielding |
| Two rescuers at once | First rescue releases everyone; second finds nobody captured |
| Player leaves while hidden or caged | `PlayerRemoving` frees the hiding spot, destroys the record, refreshes the rescue prompt |
| Player respawns while hidden | `CharacterAdded` clears hiding and frees the spot |
| Round reset while events run | `PhaseService.resetRound` calls `NightEventService.stopAll` first; the schedule thread also checks phase + round id before each event |
| SUNNY target leaves mid-chase | Target validity checked every tick (`target.Parent == Players`, `isTargetable`) |
| Late pathfinding result after timeout or reset | Discarded by `computeId` comparison |

## 4. Other checks
- No `HttpService`, no external APIs, no API keys or secrets (checker scans for secret-like strings).
- No DataStores; no production player data touched.
- All displayed text is developer-authored. Player `DisplayName`s are shown (Roblox-filtered by the platform). No chat or free-text input exists, so `TextService` filtering is not required yet; it will be required if signs/notes with player text are added.
- Client `PlaySound` repeat count clamped to 8.
- Remote payloads from the server are type-checked on the client before use.

## 5. Findings log
See the table below. Severity: High = exploit or game-breaking; Medium = incorrect behavior; Low = minor.

| ID | Severity | Location | Finding | Status |
|---|---|---|---|---|
| (filled after the independent review) | | | | |

## 6. Residual risks (accepted for MVP)
- Speed/teleport exploits on the client's own character are not detected (no server movement validation). Impact: an exploiter can reach prompts faster; all prompt actions are still distance-checked and limited.
- Exploiters can spam ProximityPrompt triggers up to the shared limiter (12/2 s); each is cheap.
- Hiding relies on anchoring a client-owned `HumanoidRootPart` from the server; behavior must be verified in Studio (M12, M22).
