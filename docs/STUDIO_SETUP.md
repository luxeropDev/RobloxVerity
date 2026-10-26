# Studio Setup

## Requirements
- Roblox Studio (current release).
- Rojo 7.x CLI and the matching Rojo Studio plugin (https://rojo.space/docs).
- Optional: `luau-analyze`, `selene`, `stylua` for type checking and linting.

## Steps
1. Clone:
   ```
   git clone https://github.com/luxeropDev/RobloxVerity.git
   cd RobloxVerity
   git checkout ccr-f6f8f094-h2ancf
   ```
2. Static check (Python 3): `python3 tools/check_project.py`
3. Option A — live sync:
   - `rojo serve`
   - Open Studio → new **Baseplate** place → Rojo plugin → **Connect** (localhost:34872).
   - Delete the template `Baseplate` part (it overlaps the generated ground and fills the ravine). Any template `SpawnLocation` is disabled automatically at boot (a warning is printed) so players spawn at camp.
4. Option B — build a place file:
   - `rojo build -o SurviveTheNight.rbxlx`
   - Open the file in Studio. (A built file starts with an empty Workspace, so nothing needs deleting.)
5. Press **Play** (solo). With `SoloTestMode = "Auto"`, Studio solo uses short timers (≈ 2 minutes per day/night cycle). The HUD shows "SOLO TEST MODE".
6. Multiplayer test: **Test → Clients and Servers → 2 players → Start**. Test mode turns off when more than one player is present.
7. Unit tests: during Play, switch the command bar to **Server** and run
   `require(game.ServerStorage.Tests.TestRunner).run({ unitOnly = true })`
   Integration tests (changes the live game state): `require(game.ServerStorage.Tests.TestRunner).run()`
8. Debug output: `GameConfig.Debug.LogPhases`, `LogEvents`, `LogSunnyStates`.

## Recommended place settings (not set by Rojo)
- Game Settings → Avatar: R15 or R6 both work; the code uses `Humanoid`, `HumanoidRootPart` and `Head` only.
- Workspace.StreamingEnabled may stay on; clients read state from attributes and remotes, not from distant parts.
- Do not enable API services / DataStores for this MVP.

## Publishing
Do not publish without the owner's approval. See `docs/RELEASE_CHECKLIST.md`.
