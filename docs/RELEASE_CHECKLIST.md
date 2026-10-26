# Release Checklist

Publishing requires explicit approval from the repository owner.

## Build
- [ ] `python3 tools/check_project.py` → 0 errors.
- [ ] `luau-analyze` / `selene` run clean (not yet available in CI).
- [ ] `rojo build -o SurviveTheNight.rbxlx` succeeds.
- [ ] `GameConfig.SoloTestMode` is `"Auto"` or `"Off"` (never `"On"` in production).
- [ ] `GameConfig.Debug.*` logging reviewed (turn off `LogSunnyStates`).

## Studio verification (all items in `tests/manual/STUDIO_TESTS.md`)
- [ ] Unit + integration TestRunner pass in Studio.
- [ ] Solo full run to an ending (victory and defeat).
- [ ] 2-client and, if possible, 4–6 client local server run.
- [ ] Mobile emulator (phone + tablet) HUD readability and prompt usability.
- [ ] MicroProfiler: server heartbeat stable, no growing instance count across 3 rounds.

## Content and compliance
- [ ] All assets original or licensed; `assets/ASSET_MANIFEST.md` up to date.
- [ ] Every placeholder sound id verified or replaced.
- [ ] No user-generated text displayed (if added later: TextService filtering required).
- [ ] Experience questionnaire / content maturity answered honestly (mild fear, cartoon, no violence/blood).
- [ ] No paid items that affect gameplay.

## Publish
- [ ] Owner approval recorded.
- [ ] Publish to a private test place first; play-test with real devices.
- [ ] Tag the release commit.
