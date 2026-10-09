# Wave Catch

Original portrait arcade game for iPhone. You ride one board and catch what the wave throws, across four spots: upper-left, upper-right, lower-left, and lower-right.

The design lives in [docs/Wave_Catch_GDD.md](docs/Wave_Catch_GDD.md). Numbers in the prototype follow [docs/DESIGN-TUNING.md](docs/DESIGN-TUNING.md). Lane paths are isolated in `WaveCatchCore/Sources/WaveCatchCore/LaneGeometry.swift` so they can change in one place. That layout (arcs off the wave lip, side skims along the waterline) is open question 1 in the tuning doc and still needs Marcin's approval.

Out of scope for this prototype: power-ups, extra modes, Game Center, ads, purchases, cosmetics, final art, and music. The life-ring restore meter, phase sky tint, and "SET" banners are deferred to a later change. Life rings still score 3 points.

## Layout

- `WaveCatchCore` is a pure Swift package. It has the rules, the seeded spawner, and `tick(dt)` / `setPosition()`. No UIKit or SpriteKit.
- `WaveCatchApp` is the iOS 16 app. SwiftUI draws the menu, the game-over card, and the debug sliders. SpriteKit draws the beach.

## Core tests

From the repo root, with Swift 5.9 or newer:

```bash
swift test --package-path WaveCatchCore
```

## Run it on an iPhone

1. Install Xcode 15 or newer.
2. Generate the project if `WaveCatch.xcodeproj` is not already in the tree:

   ```bash
   brew install xcodegen
   cd WaveCatchApp
   xcodegen generate
   ```

3. Open `WaveCatchApp/WaveCatch.xcodeproj`.
4. Select the WaveCatch scheme and your iPhone.
5. Under Signing & Capabilities, set your Team.
6. Build and run.

The phone must be in portrait. The bundle id in the project is the placeholder `com.example.wavecatch` (TBD).

## Controls

The touch pad is the bottom 45% of the safe area, split into four quarters with no dead gaps. A touch down moves the surfer immediately. The pose eases over 60 ms and never blocks the next touch. The newest touch wins.

A catchable that arrives while you are elsewhere still counts if you reach its spot within 80 ms, and the game shows CLOSE!. A jellyfish stings only if you are still on its spot 40 ms after it lands. Standing somewhere else lets it pass and keeps the combo.

The game-over button ignores taps for 600 ms, then Play again restarts in one tap.

The tuning gear stays hidden unless the app is launched with `-showTuning`, or after a 3-finger long-press. The sliders start at speed 1.00× (0.50–2.00), spawn rate 1.00× (0.50–2.00), jellyfish 1.00× the phase table (0–2.00), and Big Wave 6.0 s (3–10). The same panel can turn on a larger pad, whole-screen quadrants, and diagonal swipes. The proof run does not pass `-showTuning`.

## Feel, as tuned

Travel time is `max(0.90, 2.60 × 0.92^L)` seconds. Spawn gap is `max(0.40, 1.60 × 0.88^L)` seconds. At most `min(5, 2 + floor(L / 3))` objects are in flight. Boards are 10% faster and jellyfish are 10% slower. `L` is 0 in phase 1.

Phase clears are 8, 10, 10, 10, 12, 12, 12, 15, 15, 15 catches, then 15 forever. Boards join in phase 2, life rings in phase 3, jellyfish in phase 4.

Catchables in different lanes land at least 300 ms apart, or 450 ms on opposite diagonals. Nothing lands within 400 ms of a jellyfish in the same lane. At most two jellyfish are on screen.

After a life is lost, spawns pause for 1.0 s, speed drops one phase for the next 8 catches, and the next 3 spawns are not jellyfish.

Combo is ×1.5 at 10, ×2 at 25, and ×3 at 50. Points are `ceil(base × multiplier)`. A Big Wave adds 2 to that multiplier. It starts after phases 4, 7, and 10, then every third phase: 1.5 s warning, then 6 s with no jellyfish. Misses in the wave do not cost lives. They drop the wave bonus and keep the combo. A 3 s breather follows, two phases slower and with no jellyfish.

Three lives. The fourth is not granted. Game over is at 0.

Haptics: light on a catch, medium on a life ring, heavy on a miss, rigid then heavy 60 ms later on a sting. At most one haptic per 50 ms. A miss freezes for 90 ms and a sting for 120 ms. Shake stays at or under 10 pt and 300 ms, does not stack, and stays off when Reduce Motion is on.

Sound is synthesized in the app. The audio session is ambient, so the mute switch is respected. Nothing here is a copied melody.

The best score is stored in UserDefaults on the device.

## Proof run

The UI test launches with `-uitest` and seed 7. That launch clears the saved best and steers the surfer inside the app: it catches until the combo reaches 10, lets one jellyfish pass, then misses until the Game over card. The test taps Play, waits for that card (including NEW BEST), taps Play again, and leaves a couple of seconds of the next run on screen. Recording starts when the menu is up and stops before the app quits. Accessibility identifiers: `score`, `lives`, `newBest`, `longestCombo`, `zone.upperLeft`, `zone.upperRight`, `zone.lowerLeft`, `zone.lowerRight`, `playAgainButton`.

GitHub Actions on `macos-latest` runs `swift test`, `xcodegen`, an iOS Simulator build with signing off, and that UI test. The clip is the gameplay window, scaled to about 590×1280 and kept under 15 MB. Screenshots and the video are uploaded as the `proof` artifact.

## Still needed for TestFlight

- An Apple Developer Program account
- A real bundle id (the current `com.example.wavecatch` is TBD)
- An app icon

No ads, analytics, or third-party SDKs are included.
