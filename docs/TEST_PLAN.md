# Test Plan

## 1. Levels
| Level | Tool | Where | Status |
|---|---|---|---|
| Static | `python3 tools/check_project.py` | Any machine with Python 3 | Run in cloud session; see `docs/PROGRESS.md` for the latest output |
| Unit | `tests/unit/*.spec.lua` via `ServerStorage.Tests.TestRunner` | Roblox Studio (server command bar) | Written, **not executed** (no Studio in the cloud session) |
| Integration | `tests/integration/*.spec.lua` | Studio Play, ≥ 1 player | Written, **not executed** |
| Manual | `tests/manual/STUDIO_TESTS.md` (M1–M25) | Studio solo, local server with 2–6 clients, device emulator | **Not executed** |

## 2. What the static checker covers
Project JSON validity and `$path` existence, Rojo tree construction and duplicate sibling names, block/bracket balance, unsupported if-expressions, `require` resolution against the Rojo tree, client→server-module requires, top-level `return` in ModuleScripts, registered remote names, `GameConfig` top-level keys, client→server remotes having `OnServerEvent` handlers and rate-limit entries, heuristic undefined names, deprecated `wait/spawn/delay`, secret-like strings.

It does **not** cover: Luau types, Roblox API correctness (property/method names, enum values), runtime behavior, physics, pathfinding, or UI layout.

## 3. Unit specs
| Spec | Covers |
|---|---|
| `SunnyBrain.spec` | Every transition, reachability of all 7 states, fairness invariants (telegraphed stalk, light ends chase, hiding never captures, speed < walk speed), suspicion math, target pick |
| `EventScheduler.spec` | Guaranteed first-night event, no duplicates, MinNight, spacing, determinism, availability filter |
| `InventoryLogic.spec` | Capacity clamp, all-or-nothing spend, invalid resources, transfer, no negatives |
| `RateLimiter.spec` | Window, sliding, key independence, reset |
| `Awards.spec` | Unique awards, default award, Glow titles |
| `ConfigValidator.spec` | Shipped config valid |
| `Trove.spec` | Reverse-order cleanup, instances, connections, threads, add-after-destroy, Signal |

## 4. Integration specs
`World.spec` (boot, POIs, part budget, tags, remotes, spawn in safe zone), `Services.spec` (invalid upgrade ids, unaffordable upgrade, out-of-range gather, all 8 events run and clean up, courage clamp, idempotent release).

## 5. Risk-based focus for the first Studio session
1. Boot errors (API names, frozen tables) — M1, M25.
2. SUNNY movement with AlignPosition and network ownership — M10, M11, M14.
3. Hiding (server-anchored client-owned HumanoidRootPart) — M12, M22.
4. Round reset and respawn — M17, M20.
5. Mobile HUD scale — M23.

## 6. Exit criteria for MVP
All unit/integration specs pass; M1–M25 pass on desktop; M23 passes on phone and tablet emulators; no Output errors across 3 consecutive rounds.
