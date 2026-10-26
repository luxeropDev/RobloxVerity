# Progress

Branch: `ccr-f6f8f094-h2ancf`. Last updated: 2026-10-26.

## Phase status
| Phase | Scope | Status |
|---|---|---|
| 1 | Repo/tool inspection, CLAUDE.md, 4 agent definitions, design docs, module interfaces | Done |
| 2 | Rojo mapping, spawn/camp, server day/night loop, HUD, restart, solo test mode | Code done |
| 3 | Gathering, inventory, campfire, 4 upgrades, 6 objectives, server validation | Code done |
| 4 | Procedural SUNNY, 7-state machine, pathfinding with timeout/fallback, counterplay | Code done |
| 5 | 8 night events, 6 clues, 4 endings, atmosphere, mobile controls, cleanup | Code done |
| 6 | QA review, fixes, static checks, docs | Done (static only) |

"Code done" = implemented and statically checked. **No phase has been run in Roblox Studio.**

## Verification actually performed
| Check | Result |
|---|---|
| `python3 tools/check_project.py` | `Checked 46 Luau files (7563 lines) mapped by default.project.json` / `Summary: 0 error(s), 0 warning(s)` |
| Checker self-test (7 injected faults in a scratch copy: extra `end`, missing require target, unknown remote, typo'd local, if-expression, client requiring server module, unknown config key) | All 7 detected |
| Independent static code review (subagent, qa-security brief) | 11 findings (1 high, 3 medium, 7 low); all fixed — see `docs/SECURITY_REVIEW.md` |
| Luau compile / type check (`luau-analyze`), `selene`, `rojo build` | **Not run**: tools not installed; running downloaded binaries was blocked by the environment's permission policy |
| Unit/integration specs (`tests/`) | **Not run** (need Studio) |
| Manual Studio tests M1–M25 | **Not run** |

## Agents
- Created: `game-designer`, `world-builder`, `gameplay-engineer`, `qa-security` (`.claude/agents/`).
- Ran: one general-purpose subagent with the `qa-security` brief, for the independent review. The other three definitions were not run; the main session wrote their code and docs sequentially.

## Known issues / unverified behavior
1. Roblox API usage is unverified at runtime (AlignPosition/AlignOrientation movers, `SetNetworkOwner`, `PathfindingService` waypoints for a floating agent).
2. Hiding anchors the client-owned `HumanoidRootPart` from the server; network-ownership handoff after unanchoring must be checked (M12, M22).
3. Placeholder sounds use `rbxasset://sounds/...` paths that are unverified; Giggle, RadioStatic and ambience are silent.
4. SUNNY is `CanCollide = false`; when pathfinding fails it can float through walls (e.g. into the cabin) via the direct/drift fallback.
5. Balance (resource costs vs. test-mode day length, SUNNY speeds, suspicion rates) is untuned.
6. HUD layout on small phones is unverified; panels may overlap at minimum scale.
7. Glow/titles reset per server (no DataStore).

## Next tasks (priority order)
1. Run M1 and M25 in Studio; fix any boot or API errors.
2. Verify SUNNY movement, light clamping and capture (M10–M14).
3. Verify hiding and respawn (M12, M22) and round restart (M17).
4. Two- to six-client test (M13, M19–M21).
5. Mobile emulator pass (M23); adjust `HUDController.applyScale` and layout.
6. Replace placeholder audio with original/licensed assets; update `assets/ASSET_MANIFEST.md`.
7. Balance pass on `GameConfig` (costs, timings, escalation).
8. Install `luau-analyze` + `selene` (e.g. via Rokit/Aftman) and add a CI workflow.
9. Optional: DataStore persistence for cosmetic Glow (test on a non-production place only).
