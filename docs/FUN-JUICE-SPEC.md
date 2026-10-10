# Wave Catch — Fun + Juice Spec (step-ramp build)
Builds on DESIGN-TUNING.md; step rules (5 steps/ramp, 0.60→0.18 s/step) unchanged.

## Priority (cut from the bottom)
P0 catch feel · P0 sky/water/surfer art pass · P0 music + core SFX · P1 combo tiers + callouts · P1 Big Wave rush · P1 golden shell · P2 near-miss slow-mo · P2 parallax clouds

## 1. Catch feedback (P0)
- Hit-stop: 50 ms freeze on catch (scene.speed = 0), 90 ms on miss, 120 ms on sting. Input still buffers.
- Surfer: squash 1.15x/0.85y for 60 ms then spring back (easeOut 120 ms) on every catch; lean toward the corner.
- Splash: 10–14 particle droplets (cream #FFF3D6 + teal #3FD0D4), 300 ms life, burst from catch point. Golden shell: 24 particles + gold #FFC93C sparkle.
- Score pop: "+1" floats up 40 pt, 450 ms. Scale = 1.0 + 0.1 × combo tier (max 1.5). Colour follows tier.
- Pitch ladder: catch chime rises 1 semitone per consecutive catch, 8 steps (C major pentatonic), resets on miss or after tier callout.
- Screen shake: only on tier-up (4 pt, 150 ms), miss (8 pt, 250 ms), sting/game over (10 pt, 300 ms). Never stacks. Off with Reduce Motion.
- Haptics: as DESIGN-TUNING.md (.light catch, .medium tier/ring, .heavy miss, .rigid+.heavy sting).

## 2. Excitement beats
- Combo tiers (P1): 5 = "Nice!" ×1.5 · 10 = "Rad!" ×2 · 20 = "Tubular!" ×3 · 35 = "Wave Master!" ×4. Callout: Bungee 64 pt, pops 0→1.2→1.0 in 250 ms, holds 600 ms, centre-top, tier colour (cream → teal → pink #FF5D8F → gold). Combo pill glows in tier colour.
- Big Wave rush (P1): after phases 4, 7, 10, then every 3. 1.5 s warning (horizon wave rises, "BIG WAVE!" callout, whoosh), 6 s rush: step clock −20%, no jellyfish, every catch +2, music layer swells in (drums + lead), sky shifts hotter. Ends with crash-splash and 3 s breather.
- Golden shell (P1): 3% of catchable spawns from phase 3, max one on screen, never during a mercy window. Worth ×5 base points, gold glint every step, unique 3-note chime + .medium haptic.
- Near-miss slow-mo (P2): if a catch lands in the last 80 ms window, 0.5× time for 150 ms + "CLOSE!" small callout. Max once per 5 s.
- New best (P0): mid-run "NEW BEST!" ribbon only when the previous best is at least 10 and this run passes it, once per run. A first run or a best under 10 skips the ribbon. Game over card still shows NEW BEST whenever this run sets a new best, plus confetti (30 pieces, 1.2 s) and fanfare.
- Fast restart (P0): game over card appears after 600 ms; Play again active at 600 ms; tap → back in play in < 1 s (no menu). Card ≤ 55% width, centred.

## 3. Graphics art pass (P0 unless noted) — "Sunset Surf-Zine", original
- Sky: vertical gradient #2B1052 → #8C2F7A → #FF7A59 → #FFC46B (horizon). Sun: #FFD27A disc with soft radial glow (alpha 0.35, 1.6× radius) and 3 horizontal halftone cut-bands. Sky tints hotter each phase.
- Clouds (P2): 2 parallax layers of flat cream #FFE9C9 clouds, drift 6 and 12 pt/s.
- Water: 3 layered wave bands (#1B8FA6, #22B3C4, #47D6D9) with cream foam crests, sine bob (amp 3/5/8 pt, period 3.2/2.6/2.0 s).
- Ramps: 4 crescent wave tubes, gradient #1B8FA6 → #47D6D9, cream #FFF3D6 foam lip curling the top edge, 7 droplets at the bottom end, 2 s bob, faint halftone. Five foam step rings stay. Bottom 18% is sand #F6D7A7 (halftone, foam line, starfish, striped towel, palm shadow). Sun-glint streaks on the water. Play fills the water above that shore.
- Surfer: original — sun-bleached hair, teal rash guard, pink board with lightning stripe, drawn about 40% larger. 4 corner poses + catch squash + miss wobble (board flips, 300 ms). Plum #3B1F4A 3 pt outline, no black.
- Items: about 30% larger. Shell (pink #FF9BB3, ridged), board (teal/pink striped mini board), life ring (red/cream), golden shell (glow about 30% tighter), jellyfish (purple #9B5CF6, spiky, the only spiky silhouette). Each: plum outline, 1 highlight spec, soft drop shadow (alpha 0.25, offset 0,4). Tumble/flip each step + 40 ms squash.
- UI: Bungee for numbers/callouts, Rubik for body (OFL). Buttons: rounded 20 pt, sand #F6D7A7 at 45% with a cream arrow and soft shadow (corner controls), solid pink #FF5D8F when pressed or for Play again, 3 pt plum border, 4 pt press-down.
- Vector shapes in SpriteKit or self-drawn atlases. No LCD look, no chicken/egg/wolf.

## 4. Sound (P0) — self-made or CC0, docs/AUDIO-LICENSES.md
- Music: original synth-surf loop ~120 BPM, 16–32 bars (reverb-guitar-style lead, bass, light drums). Two stems: base + Big Wave layer (500 ms crossfade). Ducks 30% under callouts.
- Tick: soft wood block, alternating tick/tock pitches, 40 ms, low volume.
- Catch: marimba/steel-drum chime, 8-step pentatonic ladder. Golden: 3-note arpeggio.
- Ring: bubbly pop. Sting: electric zap + low thud. Miss: splash. Tier-up: rising whoosh + blip. Big Wave: whoosh + crash. New best: 2-note sting; game over: 4-note fanfare.
- Pan SFX L/R by corner. AVAudioSession .ambient (respect silent switch).

## 5. Fun sign-off test
1. Within 10 s every catch is heard and seen (chime + splash + pop).
2. Combo reaches "Nice!" and the pitch ladder audibly rises.
3. A Big Wave or golden shell appears (debug flag OK).
4. Miss clearly felt (splash, shake, cracked board icon).
5. Game over → back in play < 1 s.
6. Nothing looks like a placeholder; nothing reads as LCD/classic handheld.
