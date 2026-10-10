# Wave Catch — Wave Pool Mode Spec

## 1. Core loop
The surfer stands on a board in the middle of a wave pool. Waves roll toward them from N/E/S/W in clear steps. Tap a side to face it. If the surfer faces a wave when it arrives, it's a catch (+points, short ride pose). If facing elsewhere, the wave breaks on them = miss. Three misses end the run.

## 2. View and art (original "Sunset Pool Club")
- **View:** 3/4 top-down rectangular pool, centred, filling ~80% of screen height, deck around it. Thin sunset sky strip (PR #3 gradient) behind the far deck.
- **Water:** turquoise #2BC6D4→#47D6D9 with animated caustic light lines (scrolling texture, alpha 0.25).
- **Pool edge:** cream #FFE9C9 / pink #FF9BB3 checker tile border, plum #3B1F4A outline.
- **Deck:** sand #F6D7A7 with halftone dots. Props: 2 striped umbrellas, a lounge chair, slowly swaying palm shadows. Keep props off the 4 lanes.
- **Wave machines:** one vent in the middle of each pool wall, light blinks pink before that side fires.
- **Surfer:** ~18% of screen height. 4 facing sprites (N/E/S/W), 150 ms catch "ride" pose, wipeout wobble, 60 ms squash on turn.
- **Waves:** curved crest band as wide as the lane; teal body, cream foam lip, plum outline, soft shadow. Scale per step 0.55→0.65→0.75→0.88→1.0.
- No LCD look, no ghost silhouettes. Each of the 5 step spots per lane is a faint ripple ring on the water.

## 3. Showing where a wave comes from
- Each side has a lane of 5 swell rows, wall (step 1) to surfer ring (step 5). Waves advance one row per tick on the shared clock (0.60→0.18 s/step, same curve).
- **Telegraph:** wall vent light blinks 1 tick before spawn with a soft "whump". Landing ring at the surfer lights in the wave's colour at step 4.
- **Each step:** crest scale rises, foam brightens, 40 ms squash, swell whoosh rises in pitch (steps 1–5).
- **Facing indicator:** cream chevron on the water in front of the surfer.

## 4. Controls
- **4 edge buttons:** left-middle = W, right-middle = E, top-centre = N, bottom-centre = S. Each ≥88 pt, safe-area inset; sand #F6D7A7 at 45%, plum border, cream arrow, pink #FF5D8F when pressed. They replace the corner arrows.
- **Input:** fires on touch-down, newest touch wins, instant turn (0 ms logic, 60 ms pose). Turning early is fine; facing on the arrival tick decides the outcome.
- **Late grace:** 80 ms after the arrival tick, shown as "CLOSE!".

## 5. Wave types
| Type | Look | Rule | Points |
|---|---|---|---|
| Swell | teal crest | face it | +1 |
| Set wave (from phase 3) | wider, taller, double foam | face it | +3 |
| Golden wave (3% from phase 3, max 1 on screen) | gold #FFC93C crest with sparkle | face it | ×5 base |
| Chop, the hazard (from phase 4) | spiky dark purple #6B3FA0 crest, the only spiky shape | face AWAY | facing it = wipeout (a miss) |
Chop replaces jellyfish (same logic, max 2 on screen).

## 6. Spawn fairness
- Max waves at once: min(4, 1 + floor(L/3)).
- Two catchables arrive ≥2 ticks apart until phase 5, then ≥1. Never two waves on the same side within 2 rows of each other.
- A chop never arrives on the same tick as a catchable. Facing a catchable must never force facing a chop arriving on the same tick.
- 180° turns (N then S) on consecutive arrival ticks only from phase 6.
- **Mercy after a miss:** no spawns for 2 ticks, speed back one phase for 8 catches, no chop for the next 3 spawns.

## 7. Phases
Clear targets 8, 10, 10, 10, 12, 12, 12, 15, 15, 15.
1. N and S only.
2. All 4 sides.
3. Set waves + golden.
4. Chop.
5. Double arrivals 1 tick apart.
6. 180° turns.
7–10. Patterns mixed in, ending at 55% swell, 15% set, 3% golden, 18% chop, 9% pattern bonus.
Then endless, faster each phase.

**Patterns** (from phase 5, ~20% of spawns): clockwise sweep N,E,S,W on consecutive ticks; ping-pong E,W,E; pincer N and S 1 tick apart.

## 8. Scoring and combos
- Combo tiers: 5 "Nice!" ×1.5, 10 "Rad!" ×2, 20 "Tubular!" ×3, 35 "Wave Master!" ×4.
- **Spin bonus:** catches from all 4 sides within 6 ticks → "SPIN!" +5 and a 360° spin animation.
- **Life ring:** a ring-buoy rides a swell (from phase 3). Catching it fills the 3-pip meter; a full meter restores a life.

## 9. SURGE (the new Big Wave) and golden twist
- **SURGE** after phases 4, 7, 10, then every 3. All 4 vents flash, "SURGE!" callout, music swell layer kicks in. For 6 s, waves fire clockwise one per tick, no chop, +2 per catch, misses cost no lives. Ends with a big splash and a 3 s breather.
- **Golden Hour:** catching a golden wave starts 3 s where the sky warms, all catches are worth double, and a chime arpeggio plays.

## 10. Sound (original/CC0, logged in docs/AUDIO-LICENSES.md)
Wave-machine whump on telegraph; soft wood-block tick-tock; swell whoosh rising in pitch per step; splash + pentatonic chime ladder on catch; crunchy splash + low thud on wipeout; vent-alarm blip + big whoosh on SURGE; spin whirr + stinger. Music on by default at ~60%.

## 11. Fun sign-off checks (in the clip)
1. You can tell which side every wave comes from ≥2 ticks ahead.
2. Every catch is heard and seen; a wipeout is clearly felt.
3. Combo reaches "Nice!" and one SPIN! or SURGE shows (debug flag OK).
4. The pool looks like a real place: caustics, tiles, deck props. Nothing placeholder or LCD.
5. Game over → back in play in under 1 s.
