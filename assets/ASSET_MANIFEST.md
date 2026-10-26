# Asset Manifest

## Geometry and characters
All geometry, including SUNNY, is generated at runtime from Roblox primitive parts (Block, Ball, Cylinder), `SpecialMesh` spheres, built-in materials, `Fire`, `Sparkles`, `ParticleEmitter` (default texture), `PointLight`, `SurfaceGui` and `BillboardGui`. No meshes, decals, images or free models are used.

| Asset | Source | License |
|---|---|---|
| SUNNY model | `World/SunnyModel.lua`, original design | Project-owned |
| Forest, camp, POIs | `World/WorldBootstrap.lua`, original | Project-owned |
| Fonts | Roblox built-in `FredokaOne`, `GothamMedium`, `GothamBold` | Roblox platform fonts |

## Audio (placeholders)
Configured in `GameConfig.Audio.Sounds`. Empty id = silent.

| Key | Current id | Status |
|---|---|---|
| Gather | `rbxasset://sounds/clickfast.wav` | Studio built-in content path. **Unverified** in this environment; confirm it plays in Studio. |
| Deposit, Upgrade, Alert, Clue | `rbxasset://sounds/electronicpingshort.wav` | Studio built-in content path. **Unverified**. |
| Fuel, Capture | `rbxasset://sounds/swoosh.wav` | Studio built-in content path. **Unverified**. |
| Footsteps | `rbxasset://sounds/action_footsteps_plastic.mp3` | Studio built-in content path. **Unverified**. |
| Giggle, RadioStatic, DayAmbience, NightAmbience | empty | Needs original or properly licensed audio uploaded by the owner. |

Rules for new audio: upload original recordings, or use Roblox Creator Store audio whose license permits use in experiences; record the asset id, source and license in this table. Do not use copyrighted music or audio ripped from other games or videos.

## Text
All dialogue and on-screen text is original and lives in `GameConfig.Dialogue`, `GameConfig.Clues`, `Types.EndingInfo` and night event modules.
