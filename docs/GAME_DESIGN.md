# Game Design — SURVIVE THE NIGHT: THE SMILING STRANGER

## 1. Pitch
A group of 1–6 campers is stuck in an old forest park. The only exit is a broken bridge. The park's floating guide robot, **SUNNY**, is friendly by day. At night SUNNY decides the tour is not over. Players gather, build, keep the campfire burning, solve the park's mystery, and survive until the bridge is fixed.

- Genre: co-op forest survival + light horror + mystery + comedy.
- Session: 10–15 minutes (3 nights by default; up to 5).
- Audience: broad Roblox audience including younger players. Suspense, jump-free scares, no gore, no injuries. "Capture" = SUNNY puts you in a giggle cage until a teammate frees you.

## 2. SUNNY (original character)
- Silhouette: yellow ball body, ring of 8 orange petals (sun rays), thin antenna with a blinking tip, two tall oval eyes, wide crescent smile, small name plate "SUN-E v2.3 FOREST GUIDE".
- Day: hovers near camp, gives useful hints, bad jokes.
- Night: eyes glow cyan, smile widens, voice lines turn polite-creepy ("Stay a while. Stay forever. Stay hydrated.").
- Never enters the campfire light while the fire burns. Barricades hold SUNNY back while they have hit points.
- No AI API. Behavior is a deterministic state machine (`Lib/SunnyBrain.lua`) + perception (`Services/SunnyService.lua`).

### SUNNY state machine
| State | Enter when | Behavior | Exit |
|---|---|---|---|
| Dormant | Phase is Intermission/Dawn/Results | Parked at shrine | Phase change |
| Observing | Day/Sunset; first `Sunny.ObserveDuration` s of night | Day: follows camp, hints. Night: watches from treeline | Night timer → Investigating; target detected → Stalking |
| Investigating | Default at night | Walks to noises (gathering at night, lures) or patrol points | Suspicion ≥ threshold → Stalking |
| Stalking | Target seen long enough | Follows at `StalkDistance`, target gets "WATCHED" warning + giggle | After `StalkDuration` → Chasing; target in light → Retreating; lost sight → Searching |
| Chasing | Stalk complete | Moves at night speed (always slower than player walk speed 16) | Capture; target in light → Retreating; lost sight `LoseSightTime` / `ChaseMaxDuration` → Searching |
| Searching | Lost target | Wanders near last known position | `SearchDuration` → Retreating; re-detect → Stalking |
| Retreating | Light, capture, search end | Moves away to a far patrol point | `RetreatDuration` → Investigating |

### Fairness rules
1. A chase always follows a telegraphed stalk (HUD warning, giggle, glowing eyes) of at least `Sunny.StalkDuration` seconds.
2. SUNNY's chase speed is below default player walk speed (16).
3. Light from the fire is a hard safe zone (visible ring). Hidden players are never captured.
4. `Sunny.PostCaptureCooldown` seconds of calm after every capture. Released players get `Capture.ReleaseImmunity` seconds of immunity.
5. Only one chase at a time.

## 3. Core loop
1. **Intermission** (waits for ≥1 player).
2. **Day**: gather Wood/Stone/Food/Tokens, deposit to the camp crate, feed the fire, build upgrades, fix radio/bridge, find clues. SUNNY gives hints.
3. **Sunset**: warning; SUNNY says goodbye in a slightly wrong way.
4. **Night**: fire burns faster, SUNNY hunts, 2–4 night events. Captures cost team Courage.
5. **Dawn**: captured players freed, survivors earn Glow, victory check.
6. Repeat, harder each night. **Results** after victory/defeat with recap, awards, and a "Play Again" vote.

## 4. First 30 seconds
- Spawn at a warm campfire. SUNNY floats in: "Hi hi! I'm SUNNY, your forest guide! Grab some wood before it gets dark. Dark is... not my favorite!"
- Objectives panel already shows "Gather wood" with a counter; a tree is within 15 studs of spawn.
- First gather gives a toast "+1 Wood" and a hint to deposit at the crate.

## 5. Objectives (ObjectiveService)
| Id | Title | Goal |
|---|---|---|
| `gather_wood` | Gather wood | Team gathers `Objectives.GatherWoodGoal` wood |
| `feed_fire` | Feed the campfire | Add fuel `Objectives.FeedFireGoal` times |
| `fix_radio` | Fix the old radio | Spend `Objectives.RadioCost` from stockpile at the radio |
| `find_clues` | Find clues | Find `Objectives.CluesGoal` of 6 clues |
| `repair_bridge` | Repair the bridge | 3 stages, each `Objectives.BridgeStageCost`; unlocked by radio |
| `survive` | Survive the nights | Reach dawn of night `Nights.VictoryNight` |

## 6. Night events (NightEventService, one module each)
| Event | Telegraph | Payoff |
|---|---|---|
| FalseLantern | Warm lantern appears in the dark | Fades when reached; SUNNY is lured to it |
| StrangeRadio | Radio blinks and talks | Broken: funny static. Fixed: tells which landmark SUNNY is near |
| ShiftingNodes | "Did that tree just move?" | Some resource nodes relocate |
| SunnyAtEdge | SUNNY appears at the edge of the light, staring | Pure scare + line; no capture |
| Silhouette | A dark figure with a teammate's name | Vanishes when approached |
| StrangeCrate | "FREE STUFF :)" crate in the dark | 50%: tokens + receipt clue; 50%: confetti "Gotcha!", 5 s slow |
| FootstepsCabin | Footsteps near cabin | Reveals the cabin clue |
| FakeSign | "SAFE ZONE THIS WAY →" sign pointing into the dark | Reading reveals "(trust me) — definitely not SUNNY"; lure at pointed spot |

Night 1 always includes **SunnyAtEdge** in its first third (memorable first night).

## 7. Clues and lore
Six clues: shrine carving, tour-bus sign, cabin note (night), mushroom ring (night, secret), radio log (fixing radio), crate receipt (StrangeCrate). Story: SUNNY was a tour guide robot ("Smiling Unit for Nature Experiences") whose tour never ended.

## 8. Endings
| Ending | Condition |
|---|---|
| **Over the Bridge** (victory) | Bridge repaired and dawn of night ≥ `VictoryNight` reached |
| **SUNNY's Goodbye** (secret victory) | As above + all 6 clues found; SUNNY powers down politely |
| **Lights Out** (defeat) | Team Courage reaches 0, or (with 2+ players) every player captured at once |
| **Forever Campers** (soft defeat) | Dawn of `MaxNights` reached without the bridge |

## 9. Comedy beats
Silhouette with a teammate's name, fake signs, Gotcha crates, SUNNY asking for five-star reviews, recap awards ("Professional Log Hugger", "SUNNY's Favorite").

## 10. Out of scope (MVP)
Monetization, DataStore persistence, voice lines, custom meshes/animations, combat.
