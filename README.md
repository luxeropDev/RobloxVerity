# SURVIVE THE NIGHT: THE SMILING STRANGER

A co-op Roblox forest survival game for 1–6 players. Gather wood, stone, berries and tokens by day, keep the campfire burning, build camp upgrades, solve the mystery of **SUNNY** — a cheerful floating forest-guide robot who gets a little *too* friendly after dark — and survive until the bridge is fixed.

- Session: 10–15 minutes (3 nights; up to 5 if the bridge is not fixed)
- Platforms: desktop, tablet, phone (ProximityPrompts + touch buttons)
- Tone: suspenseful, funny, non-graphic. Getting caught sends you to the Giggle Cage until a friend rescues you.

## Status
Playable-MVP code is complete and passes the project's static checker. **It has not yet been run in Roblox Studio** (the project was built in a cloud environment without Studio). See `docs/PROGRESS.md` and `tests/manual/STUDIO_TESTS.md`.

## Quick start
```
git clone https://github.com/luxeropDev/RobloxVerity.git
cd RobloxVerity
git checkout ccr-f6f8f094-h2ancf
python3 tools/check_project.py      # static checks
rojo serve                          # then connect from the Rojo Studio plugin
# or: rojo build -o SurviveTheNight.rbxlx
```
Press Play in Studio. Solo Studio sessions use short timers automatically. Details: `docs/STUDIO_SETUP.md`.

## How to play
| Action | Desktop | Touch |
|---|---|---|
| Gather, deposit, add fuel, cook, hide, rescue, inspect | Hold **E** on a prompt | Tap/hold the prompt |
| Camp upgrades | **C** or CAMP button, or the workbench | CAMP button |
| Leave hiding | **Space** or LEAVE button | LEAVE button |

Survive: stay in the firelight at night, watch for the "SUNNY IS WATCHING YOU" warning, run to the light or hide in a bush. Fix the radio, repair the bridge, survive night 3.

## Repository map
- `src/` — game code (Rojo-mapped). Tuning: `src/ReplicatedStorage/Shared/GameConfig.lua`.
- `tests/` — Studio unit/integration specs + manual test list.
- `docs/` — design, progression, architecture, map, test plan, security review, setup, release checklist, progress.
- `.claude/agents/` — specialist agent definitions (game designer, world builder, gameplay engineer, QA/security).
- `tools/check_project.py` — static checker.

## Content policy
Original characters, geometry and text only. No external APIs, no API keys, no monetization, no persistent player data in the MVP.
