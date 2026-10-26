# CLAUDE.md — SURVIVE THE NIGHT: THE SMILING STRANGER

Roblox multiplayer forest-survival horror game (1–6 players, 10–15 minute sessions), built with Rojo and Luau.

## Layout
- `default.project.json` — Rojo mapping. Source of truth for where files land in the DataModel.
- `src/ReplicatedStorage/Shared/` — config, types, remote registry (visible to client and server).
- `src/ServerScriptService/Main.server.lua` — server entry point. Builds world, inits services, starts phase loop.
- `src/ServerScriptService/Services/` — server services (authoritative game logic).
- `src/ServerScriptService/Services/NightEvents/` — one ModuleScript per night event.
- `src/ServerScriptService/Lib/` — pure, unit-testable logic (no Instances), plus Signal/Trove helpers.
- `src/ServerScriptService/World/` — procedural world + SUNNY model builders.
- `src/StarterPlayer/StarterPlayerScripts/` — client entry (`Client.client.lua`) and controllers.
- `tests/unit`, `tests/integration` — Luau specs, mapped to `ServerStorage.Tests` and run from Studio.
- `tests/manual/STUDIO_TESTS.md` — manual Studio test procedures.
- `tools/check_project.py` — static checker (no Luau toolchain required).

## Rules
1. All tuning values live in `Shared/GameConfig.lua`. No magic numbers for gameplay in services.
2. The server is authoritative for phase, inventory, stockpile, upgrades, objectives, events, captures, rewards and SUNNY decisions. Clients only send *requests*.
3. Every client→server remote is listed in `Remotes.lua` `CLIENT_TO_SERVER`, rate limited, and validated (type, phase, distance, cost, state).
4. Do not yield between a validation check and the state mutation it guards (keeps concurrent requests safe).
5. Every temporary Instance/connection/thread created by an event or round goes into a `Trove` and is cleaned on phase/round end.
6. Loops must be bounded or tied to the server lifetime with `task.wait`; never `while true do end` without a yield.
7. No `if … then … else` *expressions* (the static checker does not support them); use statements.
8. No external HTTP, AI APIs, API keys, DataStores of production data, or paid advantages.
9. Original assets only. SUNNY is an original character; do not copy other games' characters, audio, or text.
10. Never claim Studio/runtime testing that did not happen. Static checks ≠ Studio tests.

## Commands
- Static check: `python3 tools/check_project.py`
- Serve to Studio: `rojo serve` (then connect from the Rojo Studio plugin)
- Build place file: `rojo build -o SurviveTheNight.rbxlx`
- Unit tests (Studio command bar, in Play/Run mode on server): `require(game.ServerStorage.Tests.TestRunner).run()`

## Agents
Specialist agent definitions are in `.claude/agents/`. The main session owns integration and final verification.
