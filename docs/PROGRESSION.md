# Progression

All numbers reference `src/ReplicatedStorage/Shared/GameConfig.lua`.

## 1. In-round progression (resets each round)
### Resources
| Resource | Node | Hits | Respawn | Main use |
|---|---|---|---|---|
| Wood | Tree node | `Resources.Wood.NodeHits` | `RespawnTime` | Fuel, upgrades, bridge |
| Stone | Rock | `Resources.Stone.NodeHits` | | Upgrades, radio, bridge |
| Food | Berry bush | `Resources.Food.NodeHits` | | Cook snack (+1 Courage) |
| Token | Sparkle | 1 | long | Upgrades, radio |

Players carry up to `Inventory.BaseCapacity` items (+`Upgrades.Storage` bonus). Deposit at the camp crate into the shared stockpile.

### Camp upgrades (stockpile cost)
| Upgrade | Levels | Effect |
|---|---|---|
| FireRing | 2 | +safe radius, +max fuel, slower decay |
| Storage | 2 | +carry capacity per player |
| Lanterns | 2 | +safe radius (lantern ring) |
| Barricade | 1 | Fence that holds SUNNY out (radius `Camp.BarricadeRadius`) even if the fire fails, until its HP is spent |

Upgrades can only be built outside Night, within `Camp.InteractRadius` of the fire.

### Team Courage
Starts at `Courage.Base + Courage.PerExtraPlayer × (players − 1)`, capped at `Courage.Max`. −1 per capture. Cooking a snack (`Courage.SnackCost`) restores 1. 0 Courage = defeat.

### Night escalation (`GameConfig.Escalation[n]`)
| Night | SUNNY speed | Detect radius | Suspicion rate | Events | Fuel decay × |
|---|---|---|---|---|---|
| 1 | 12 | 50 | 0.7 | 2 | 1.0 |
| 2 | 13.5 | 60 | 0.9 | 3 | 1.2 |
| 3 | 14.5 | 70 | 1.1 | 3 | 1.4 |
| 4 | 15 | 75 | 1.25 | 4 | 1.6 |
| 5 | 15.5 | 80 | 1.4 | 4 | 1.8 |

Player walk speed is 16; SUNNY is always slower.

## 2. Cosmetic progression (session only)
- **Glow** points: +`Rewards.GlowPerNightSurvived` at each dawn for non-captured players, +`Rewards.GlowPerClue` per clue found, +`Rewards.GlowVictory` on victory.
- Glow unlocks overhead titles (`Rewards.Titles`): Camp Newbie → Marshmallow Scout → Firefly Friend → Night Owl → Sun Chaser.
- No gameplay advantage. No purchases. Not saved between servers in the MVP (DataStore persistence is a next task and must be tested on a non-production place).

## 3. Pacing target (normal timings)
Intermission 12 s, Day 150 s, Sunset 20 s, Night 120 s, Dawn 12 s → ~5 min per day/night cycle. Victory needs 3 nights ≈ 14 minutes. Test mode (Studio, solo) shortens to ~2 min per cycle.
