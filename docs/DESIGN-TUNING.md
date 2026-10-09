# Wave Catch – Design Tuning v1 (for Game Engineer)

Source: `Wave_Catch_GDD.md` v0.1 (Polish; the PDF is the same content). Engine: **Swift + SpriteKit** (GDD recommendation, and what the prototype already uses). All numbers are starting values. Anything marked **[slider]** should be exposed in the debug panel. Where this doc changes the GDD, it says **(changes GDD)**.

Cost rule: tune with what the prototype already has. New work is limited to items marked **MVP-add**.

---

## 1. Core loop and miss rules

**Loop:** tap one of 4 positions → items arrive at the 4 catch spots → catch for points, or let a jellyfish pass → the pace rises by phase → 3 misses → Game Over → one tap "Again". Target session: 1–3 min.

**Positions:** Upper-Left (UL), Upper-Right (UR), Lower-Left (LL), Lower-Right (LR). The surfer is always in exactly one of them. The game starts at LL.

**Resolution happens at arrival (t = 0), when an item reaches its catch spot:**

| Situation | Result |
|---|---|
| Catchable arrives, surfer in its lane at t=0 | **Catch.** Points = `ceil(base × multiplier)`, combo +1 |
| Catchable arrives, surfer taps its lane within **+80 ms** (late grace; the item wobbles on the spot) | **Catch**, counted as a "CLOSE!" near-miss |
| Catchable arrives, surfer not there by +80 ms | **Miss**: −1 life, combo = 0 |
| Jellyfish arrives, surfer in its lane at t=0 and still there at **+40 ms** | **Sting**: −1 life, combo = 0 |
| Jellyfish arrives, surfer elsewhere | Drops into the water. 0 pts, **combo kept** |
| Jellyfish passes and the surfer left that lane in the last 150 ms | "DODGE!" sparkle, 0 pts, combo kept |
| Any miss during Big Wave | **No life lost.** Big Wave bonus is lost for the rest of that wave; combo kept (GDD) |

- **Base points:** shell 1, board 2, life ring 3 (GDD).
- **Lives:** 3, never more than 3.
- **Game over:** on the 3rd lost life. Hit-stop, then the Game Over sheet. The "Again" button ignores input for the first **600 ms** so a stray gameplay tap can't restart the game.
- **Motion:** **smooth** with a telegraph, not stepped. Stepped "LCD tick" movement is the strongest link to Game & Watch, so it's out (decides the GDD's open question).
- **Telegraph:** the catch spot lights up `min(400 ms, 0.4 × T)` before arrival. A cream ring means a catchable. A spiky purple dashed ring means a jellyfish. A soft tick SFX is panned to that side.

## 2. Controls

**Tap pad (default, matches the GDD 2×2):**
- The control pad is the **bottom 45% of the safe-area height**, ending at the top of the home-indicator inset.
- It splits at exactly 50% width and 50% of the pad height. **No dead gutters**; every pixel maps to the nearest quadrant.
  - Top-left of the pad → UL · top-right → UR · bottom-left → LL · bottom-right → LR.
- Taps above the pad are ignored, except the pause button (top-right, 44×44 pt).
- **Accessibility "Large pad":** 55% of height. **Debug toggle "Whole-screen quadrants":** the screen splits around the surfer's centre, to test whether players prefer tapping where the item lands.

**Input handling:**
- Act on **touchesBegan**. Never wait for touch-up. Ignore touchesMoved.
- **Multi-touch:** the newest touch wins.
- **Snap time:** the logical position changes in **0 ms** (same frame). The visual tween to the new pose takes **60 ms** ease-out and never blocks input. A tap during a tween re-targets at once.
- **Buffering:** catch/sting checks run in the fixed update after input is applied, so a tap in the same frame as an arrival counts. During hit-stop (≤120 ms) or the Big Wave banner, taps still change position immediately; nothing is dropped. During pause or Game Over, taps are ignored. That covers buffering; no extra queue is needed.
- **Swipe (↖↗↙↘):** stays a debug toggle only in the MVP. Threshold 30 pt, direction by octant.

**One-handed play:** the pad sits in the thumb zone in portrait, and the grid is symmetric, so no left-handed mode is needed (GDD). The thumb rests at the pad centre, about 1.5 cm from every quadrant.

## 3. Speed curve

`L` = phase index (0 for phase 1 … 9 for phase 10). After phase 10, L goes up by 1 every 15 catches.

```
Travel time  T(L) = max(0.90 s, 2.60 s × 0.92^L)      // spawn → arrival, same for every lane
Spawn int.   I(L) = max(0.40 s, 1.60 s × 0.88^L)      // time between spawns
Max on screen C(L) = min(5, 2 + floor(L / 3))         // hard cap; if full, delay the spawn
Per item:    board T × 0.90 (faster), jellyfish T × 1.10, shell/ring T × 1.00
Slider:      T_eff = T / speedMul,  I_eff = I / spawnMul
```

Lanes are equalised by **time**, not by pixel speed. The two lane shapes have different lengths (see §6), so each gets its own px/s.

| L | Phase | T (s) | I (s) | Max on screen |
|---|---|---|---|---|
| 0 | 1 | 2.60 | 1.60 | 2 |
| 1 | 2 | 2.39 | 1.41 | 2 |
| 2 | 3 | 2.20 | 1.24 | 2 |
| 3 | 4 | 2.02 | 1.09 | 3 |
| 4 | 5 | 1.86 | 0.96 | 3 |
| 5 | 6 | 1.71 | 0.84 | 3 |
| 6 | 7 | 1.58 | 0.74 | 4 |
| 7 | 8 | 1.45 | 0.65 | 4 |
| 8 | 9 | 1.33 | 0.58 | 4 |
| 9 | 10 | 1.23 | 0.51 | 5 |
| 10 | endless | 1.13 | 0.45 | 5 |
| 11–12 | endless | 1.04–0.96 | 0.40 (floor) | 5 |
| 13+ | endless | 0.90 (floor) | 0.40 | 5 |

**Fairness rules for the spawner.** The spawner schedules by **arrival time**, not spawn time:
1. Two catchables in **different** lanes never arrive less than **300 ms** apart. Opposite diagonals (UL↔LR, UR↔LL) need **450 ms**.
2. Nothing arrives in a lane less than **400 ms** before or after a jellyfish in that lane, so a jelly is never forced onto the player.
3. At most **2 jellyfish** on screen at once, and never jellies in 3+ lanes inside one 600 ms window.
4. No lane gets more than 4 catchables in a row while another lane is idle (keeps the player moving).

**Mercy after a miss or sting** (MVP-add, small):
- No new spawns for **1.0 s**. Items already in flight keep going, but any jellyfish due in the next 1.0 s fades out harmlessly.
- `L_eff = max(0, L − 1)` for the next **8 catches**. It doesn't stack beyond −1.
- The next **3 spawns** can't be jellyfish.

## 4. The first 10 phases

Clearing a phase shows a small "SET n" banner for 900 ms; the game doesn't pause. Mix percentages are spawn weights: shell / board / life ring / jellyfish.

| Phase | Clear target (catches) | T / I (s) | Mix % S/B/R/J | Introduces |
|---|---|---|---|---|
| 1 | 8 | 2.60 / 1.60 | 100 / 0 / 0 / 0 | Shells only, one lane at a time (arrivals ≥ 1.2 s apart) |
| 2 | 10 | 2.39 / 1.41 | 85 / 15 / 0 / 0 | Boards (2 pts, 10% faster) |
| 3 | 10 | 2.20 / 1.24 | 75 / 20 / 5 / 0 | Life rings and the ring meter |
| 4 | 10 | 2.02 / 1.09 | 70 / 20 / 5 / 5 | First jellyfish: 1 at a time, never next to a catchable. **Big Wave #1 when cleared** |
| 5 | 12 | 1.86 / 0.96 | 62 / 20 / 6 / 12 | Irregular jellyfish hops; a combo of ×1.5 is now reachable |
| 6 | 12 | 1.71 / 0.84 | 60 / 20 / 6 / 14 | 2 jellyfish at once; jelly + catchable in adjacent lanes |
| 7 | 12 | 1.58 / 0.74 | 58 / 22 / 6 / 14 | "Doubles": 2 catchables 300–500 ms apart in different lanes. **Big Wave #2 when cleared** |
| 8 | 15 | 1.45 / 0.65 | 55 / 22 / 7 / 16 | Opposite-diagonal switches (≥450 ms); sky turns to neon night |
| 9 | 15 | 1.33 / 0.58 | 52 / 24 / 7 / 17 | A jellyfish follows a catch in the same lane (≥400 ms): catch, then leave |
| 10 | 15 | 1.23 / 0.51 | 50 / 24 / 8 / 18 | Up to 5 on screen. **Big Wave #3 when cleared**, then endless (L+1 every 15 catches, Big Wave every 3 phases) |

Expected time to the end of phase 4 is about 55 s, and about 45 s between later Big Waves. That stays close to the GDD's 30–45 s, but it's phase-based so tests are repeatable **(changes GDD)**.

**Life rings** **(changes GDD**: the GDD's "5 in a row" would take about 100 catches at 5% rings, which is too slow):
- Each ring adds 1 pip to a **3-pip ring meter** shown under the lives.
- 3 pips restore 1 life (max 3), and the meter resets.
- A miss or sting empties the meter.
- At full lives, a full meter gives +10 pts instead.

**Big Wave** (existing feature, values):
- **Warning: 1.5 s.** The sky flashes, a riser plays, the "BIG WAVE!" banner shows, and spawns stop.
- **Duration: 6.0 s** **[slider]**.
- **Mix:** shell 60 / board 30 / ring 10 / jellyfish 0. Spawn interval `max(0.30 s, 0.5 × I)`; T unchanged.
- **Multiplier:** combo multiplier **+2**, so ×1 becomes ×3 and ×2 becomes ×4. It's additive, not ×3 multiplicative, so scores don't explode **(fills GDD gap)**.
- **Afterwards:** a 3 s breather at `L − 2` with no jellyfish.

**Combo** (GDD): 10 → ×1.5, 25 → ×2, 50 → ×3. Resets on a miss or sting.

### Debug slider defaults (existing sliders)

| Slider | Default | Range / step | Meaning |
|---|---|---|---|
| Speed | **1.00×** | 0.50–2.00 / 0.05 | Divides T(L) |
| Spawn rate | **1.00×** | 0.50–2.00 / 0.05 | Divides I(L) |
| Jellyfish chance | **1.00×** of the phase table (if it's an absolute %, use **15%**, range 0–40%) | 0–2.00 / 0.05 | Scales the J weight; the others are renormalised |
| Big Wave length | **6.0 s** | 3.0–10.0 / 0.5 | Active wave time, not counting the 1.5 s warning |

Optional, only if trivial: a "Start phase" stepper (1–10) to skip ahead while tuning.

## 5. Juice and feedback

Haptics use **UIImpactFeedbackGenerator**. Create one generator per style, call `prepare()` at run start and after each fire, allow at most **1 haptic per 50 ms**, and follow the system haptics setting.

| Event | Visual (timing) | SFX | Haptic |
|---|---|---|---|
| Lane switch | 60 ms pose tween, 1-frame dust puff | soft whoosh, −18 dB | none (optional `.soft` 0.3, off by default) |
| Catch: shell | item pops 1.0→1.3→0 in 140 ms; "+n" floats 24 pt up over 450 ms; surfer squash 80 ms | blip, +1 semitone per 5 combo (cap +12) | `.light` 0.6 |
| Catch: board | same, plus a 2-frame white flash | surf-guitar pluck | `.light` 0.8 |
| Catch: ring | same, plus a meter pip fill 200 ms | bell + bubbles | `.medium` 0.7 |
| Life restored | life icon bounces 1.0→1.4→1.0 over 300 ms | rising arpeggio | `.medium` 1.0 |
| Near-miss ("CLOSE!") | yellow "CLOSE!" text, 350 ms | blip + sparkle | `.light` 1.0 |
| Jellyfish dodge | cyan bubble burst, 250 ms | bubble pop | none |
| **Miss** | **90 ms hit-stop**; item splashes; one life icon cracks and greys out (400 ms); screen shake 6 pt for 180 ms | splash + falling tone | `.heavy` 1.0 |
| **Jellyfish sting** | **120 ms hit-stop**; surfer flashes purple 3× over 300 ms; shake 8 pt for 220 ms | electric zap + low buzz | `.rigid` 1.0, then `.heavy` 0.8 at +60 ms |
| Combo tier up | the multiplier badge pulses to 1.25 over 200 ms; edges glow in the tier colour | chord stab, rising per tier | `.medium` 0.8 |
| Big Wave warning / start | sky flash, 1.5 s banner; the wave rolls in over 400 ms | riser, then a crash | `.medium` ×3 at 0 / 100 / 200 ms |
| Big Wave catch | normal catch visuals, gold "+n" | same blips | `.light` 0.4 (rate-limited) |
| Game over | 200 ms freeze, 300 ms desaturate, sheet slides up in 350 ms; shake 10 pt for 300 ms | tape-stop | `.heavy` 1.0 |
| New best | confetti; "NEW BEST" on the sheet | short fanfare | `.medium` ×2 |

**Showing the 3 lives:** three small surfboard icons at top-left. A lost life cracks and greys out, so it stays visible as an empty slot. The ring meter (3 pips) sits under them.

**Screen shake limits:** only on a miss, a sting or game over. Never on a catch or during Big Wave. Max amplitude **10 pt**, max length **300 ms**, linear decay, never stacked. **Reduce Motion** turns off shake and flashes.

## 6. Art direction: "Sunset Surf-Zine"

The look is a flat, full-colour 80s beach poster printed like a riso surf zine: bold shapes, halftone dot shading, a slight 2 px colour misregistration and pastel-neon colours. Time of day shows progress: afternoon in phases 1–3, sunset in 4–7, neon night from 8.

**Layout (portrait, about 393×852 pt):**
- **HUD band (top, inside the safe area):** lives and ring meter on the left, the score in the centre, the combo badge and pause on the right.
- **Playfield (from below the HUD down to 55% of the screen):**
  - A striped setting sun sits on the horizon, and **one big curling wave crosses the top of the playfield from left to right.**
  - The surfer rides a board in the middle of the wave face at about 42% of screen height.
  - **Upper lanes (UL/UR):** items are tossed out of the curling lip above and fall in **curved arcs** to the surfer's raised left or right hand.
  - **Lower lanes (LL/LR):** items **skim in horizontally along the waterline**, bobbing on small swells from the left or right edge, to the board's nose or tail.
  - That gives two arcs from above and two straight runs from the sides. **There are no diagonal chutes from the corners into a centre catcher** **(changes the GDD's "one chute per corner" picture)**.
- **Control pad (bottom 45%):** the shore. Four beach-towel tiles in pastel stripes, each with a small arrow icon. The tile you press glows for 120 ms.

**Palette:**

| Use | Hex |
|---|---|
| Sky (indigo → violet → hot pink → tangerine) | `#2B1055` `#7A2E8E` `#FF5E8A` `#FF9F5A` |
| Sun | `#FFD66B` |
| Sea, deep sea | `#1FB5C9` `#0E7C99` |
| Foam, UI text | `#FFF4E0` |
| Sand, pad tiles | `#F7C9A0` |
| Outline ink (plum, not black) | `#2A1A3A` |
| Shell (pink, cream ridges) | `#FFB3C7` |
| Board (mint, pink stripe) | `#3EE6B0` |
| Life ring (orange with cream bands) | `#FF6B35` |
| Jellyfish (toxic purple, lime glow) | `#B14CFF` / `#C6FF3D` |
| Night neon | `#120A2A` `#FF3EA5` `#00E5FF` |

**Shapes:**
- Every item is told apart by its **silhouette as well as its colour** (for colour blindness):
  - Shell: a rounded fan with ridges.
  - Board: a long, thin pill.
  - Ring: an O-shape with bands.
  - Jellyfish: a dome with 3 wavy tentacles and a **spiky** outline. It's the only item with sharp edges.
- Items have a 4 pt plum outline. Items are 64–72 pt; the surfer is about 110 pt tall.
- The surfer is a human character with a big 80s haircut and bold swim trunks. There are 4 pose sprites (one per position) plus catch, hurt and idle frames.

**Fonts (free, SIL OFL):**
- **Bungee** for the score, banners and buttons.
- **Monoton** for the logo only.
- **Rubik** for the menus and body text.
- **No 7-segment or LCD fonts** (DSEG and the like).

**MVP art:** coloured placeholder shapes in these hexes, plus a sky gradient tint that changes by phase. Final art comes later.

**Audio direction:**
- **Music:** synth-surf, around 120 BPM, with a twangy reverb guitar over analog-style pads and a drum machine. There's one base loop plus a Big Wave stem in the same key, crossfaded in over 300 ms. The tempo itself never changes.
- **Sources** (keep a `LICENSES.md`):
  - Self-made: **BeepBox / JummBox**, **LMMS** with **Surge XT** for music, **jsfxr / ChipTone** for SFX.
  - Royalty-free: **CC0 only**, e.g. Kenney.nl audio packs, OpenGameArt or Freesound filtered to CC0.
  - Final music: commission, with full rights assigned.
  - Never NC or ND licences, and never covers or famous melodies.
- **"Play by ear":** left lanes pan −0.5 and right lanes pan +0.5. Upper-lane sounds are pitched +5 semitones above the lower ones.
- **SFX list:** lane whoosh, telegraph tick, shell blip, board pluck, ring bell, life restored, near-miss sparkle, jellyfish hop squelch, jellyfish dodge pop, sting zap, miss splash, combo stabs ×3, Big Wave riser, Big Wave crash, Big Wave end, game over tape-stop, new best fanfare, UI tap.
- **Session:** use `AVAudioSession` `.ambient`, so the game respects the mute switch and mixes with the user's own music. Music and SFX each get a volume slider (GDD).

### Originality guardrails
1. No wolf, hare, chicken, hen or egg anywhere: art, icons, copy or store keywords.
2. No LCD look: no grey segment silhouettes, no ghosted "off" segments, no stepped tick motion, no 7-segment digits, no console bezel or button layout.
3. No four diagonal chutes into a centre catcher. Use arcs from the wave lip and skims along the waterline.
4. Full colour, gradients and halftone. Never a monochrome screen on a beige panel.
5. No "Nu, pogodi!", "Game & Watch", "Egg", "Elektronika", "IM-02" or "Nintendo" in the name, ASO, marketing or code asset names.
6. All audio is original or CC0/commercially licensed. No melodies from the cartoon or the original games.
7. Every asset and font has its source and licence recorded. An IP lawyer reviews everything before launch (GDD §9).

## 7. MVP scope

**In (mostly already built; tune with this doc):**
- 2×2 tap pad, 4 positions, smooth lanes with telegraph
- Shell, board, jellyfish; 3 lives; combo
- Phase curve with fairness rules
- One Big Wave type (cadence per §4)
- Local best score, one-tap restart
- The 4 debug sliders above
- UIImpactFeedbackGenerator haptics
- Placeholder shapes, a basic SFX set

**MVP-add (small, high value):**
- Mercy rule
- Life ring with the 3-pip meter
- Near-miss and dodge pops
- Telegraph rings
- Sky tint per phase
- "SET n" banner

**Out:**
- Power-ups (Slow Sun, Foam Shield, Tide Magnet)
- Big Wave endless mode, Daily Challenge
- Game Center, ads, IAP, cosmetics
- Final art and music, VHS/scanline filter
- Swipe controls outside debug
- Settings screen, apart from mute and the Large pad option

## 8. Open questions for Marcin
1. Do you approve the lane geometry (arcs from the wave lip plus skims along the waterline) instead of the GDD's chutes from the corners? It's the main originality decision.
2. Life ring: OK to restore a life after 3 rings since the last miss, instead of 5 in a row?
3. Big Wave: OK for it to come on phase clears (about every 45 s), with the additive +2 multiplier?
4. Should players see the phase as "SET n", or should the difficulty curve stay invisible?
5. Final art and music: self-made or commissioned? Is there a budget?
6. Is "Wave Catch" final? The App Store and trademark checks are still needed (GDD §11).
7. Is the game iOS-only for good? Swift/SpriteKit means a rewrite if Android ever comes.
