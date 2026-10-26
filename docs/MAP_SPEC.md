# Map Specification

Source: `src/ServerScriptService/World/WorldBootstrap.lua`. Coordinates are studs, ground top at Y = 0, camp at the origin. The layout is fixed; tree, node, hiding-spot, spare and patrol positions are seeded (`GameConfig.Seed`, random when nil).

## 1. Bounds
- Playable square: ±`World.MapHalfSize` (300) on X and Z, invisible 60-stud border walls.
- Ravine: centered on Z = `World.RavineZ` (−200), width `World.RavineWidth` (26), floor at Y = −40. Invisible guard rails on both edges; the bridge gap has its own `BridgeBarrier` (removed when the bridge is repaired).

## 2. Points of interest
| Name | Position | Contents | Tags / refs |
|---|---|---|---|
| Camp | (0, 0, 0) | Clearing, campfire (`FireCore` with `Fire` + `PointLight`), safe ring, 4 log benches, spawn at (0, 0, 15), camp crate (−11, 4), cooking pot (−7, −9), upgrade bench (10, 6) | `world.FirePart`, `SafeRing`, `SupplyCrate`, `CookingPot`, `UpgradeBench`, `SpawnLocation` |
| Cabin | (30, 0, −16) | 16×12 room, door facing camp, table with ranger note, closet hiding spot | `ClueSpots.Cabin`, `CabinHidingSpot` |
| Ranger Post | (−95, 0, 70) | Table, old radio, antenna, status light, sign | `world.Radio`, `RadioLight` |
| Broken Bridge | (0, 0, −187 … −213) | Two stubs, 3 repair stages, dangling planks, "BRIDGE OUT" sign, ranger station on far side | `BridgePlanks[1..3]`, `BridgeBarrier`, `BridgeSign` |
| Strange Shrine | (140, 0, 115) | Pillars, arch, glowing orb, smiling carving | `ClueSpots.Shrine`, `ShrinePosition` (SUNNY home) |
| Giggle Cage | (152, 0, 103) | 8×8 force-field room with lock | `CageLock`, `CageCenter` |
| Old Tour Bus | (195, 0, −70) | Tilted bus, "SUNNY TOURS" sign | `ClueSpots.TourBus` |
| Mushroom Ring | (−190, 0, 170) | 8 glowing mushrooms (secret) | `ClueSpots.MushroomRing` |
| Big Rock | (−150, 0, −60) | Landmark | radio hints |
| Fallen Log | (60, 0, 160) | Landmark | radio hints |
| Old Signpost | (5, 0, −110) | "BRIDGE ->" sign on the bridge path | radio hints |

Dirt paths connect the camp to the Ranger Post, Shrine, Bridge and Tour Bus; trees are kept off them.

## 3. Generated content
| Content | Count (config) | Placement ring | Parts each |
|---|---|---|---|
| Wood nodes (orange ribbon trees) | `WoodNodes` 24, first 3 at 16–32 studs | 24–150 | 3 |
| Rock nodes | `RockNodes` 14 | 30–170 | 1 |
| Berry bushes | `BerryNodes` 12 | 26–160 | 4 |
| Token sparkles | `TokenNodes` 6 | 80–240 | 1 (+light, sparkles) |
| Hiding bushes | `HidingSpots` 8 (+ cabin closet) | 45–160 | 1 |
| Decorative trees | `TreeCount` 110 (attempts) | ≥ 40 | 2 |
| Spare node positions | 30 (no parts) | 40–170 | 0 |
| SUNNY patrol points | 14 (no parts) | 60–220 | 0 |

## 4. Stable tags and names (do not rename without updating services)
- CollectionService tags: `ResourceNode` (Model, attribute `ResourceType`), `HidingSpot` (BasePart), `ClueSpot` (BasePart).
- Prompt names: `GatherPrompt`, `HidePrompt`, `RescuePrompt`, `CluePrompt`, `UpgradeBenchPrompt` (the client listens for this name).
- Root folders: `Workspace.World`, `Workspace.NightEventObjects`, `Workspace.SUNNY`.

## 5. Budget and mobile performance
- Estimated static part count ≈ 110 (POIs) + 140 (nodes) + 8 (hiding) + ≤ 220 (trees) ≈ 480, plus SUNNY (22) and built upgrades (≤ 24). Hard warning above `World.MaxParts` (900).
- All decorative parts anchored, `CastShadow = false`; canopies, bushes, berries and signs are `CanCollide = false`.
- Lights: campfire, up to 6 lanterns, 6 token sparkles, SUNNY glow, event lanterns. `PointLight.Shadows = false`.
- Night fog end 170 studs hides distant geometry.

## 6. Lighting presets
`GameConfig.Lighting.Day/Sunset/Night/Dawn` (client-side, tweened over `TweenTime`). Day clock advances 8:00 → 17:00 across the Day phase.
