import SwiftUI
import SpriteKit
import WaveCatchCore

struct RootView: View {
    @StateObject private var model = GameModel()

    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            let bottom = geo.safeAreaInsets.bottom
            let safeHeight = geo.size.height - top - bottom
            let fraction = model.largePad ? 0.55 : 0.45
            let padHeight = safeHeight * fraction
            let padTop = geo.size.height - bottom - padHeight
            ZStack(alignment: .topLeading) {
                SceneHost(scene: model.scene)
                    .frame(width: geo.size.width, height: geo.size.height)

                if model.mode != .menu {
                    hud(top: top, width: geo.size.width)
                    ControlPad(
                        enabled: model.mode == .playing && !model.paused,
                        showTiles: !model.wholeScreenPad,
                        swipeEnabled: model.swipeEnabled,
                        pressed: model.pressedLane,
                        verticalSplit: model.wholeScreenPad ? CGFloat(LaneGeometry.surferAnchor.y) : CGFloat(0.5),
                        onLane: { model.setLane($0) }
                    )
                    .frame(width: geo.size.width, height: model.wholeScreenPad ? geo.size.height : padHeight)
                    .position(
                        x: geo.size.width / 2,
                        y: model.wholeScreenPad ? geo.size.height / 2 : padTop + padHeight / 2
                    )
                }

                if model.mode == .menu {
                    menu(size: geo.size)
                }
                if model.mode == .gameOver {
                    gameOver(size: geo.size)
                }
                if model.paused && model.mode == .playing {
                    pauseCard
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $model.showDebug) {
            DebugPanel(model: model)
        }
    }

    private func hud(top: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    lifeRow
                    Text("\(model.lives)")
                        .font(.system(size: 4))
                        .foregroundColor(Palette.indigo)
                        .frame(width: 24, height: 24)
                        .accessibilityIdentifier("lives")
                        .accessibilityLabel("\(model.lives)")
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("\(model.score)")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundColor(Palette.foam)
                        .accessibilityIdentifier("score")
                    Text(multiplierText)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(Palette.sun)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button(action: { model.togglePause() }) {
                        Image(systemName: model.paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Palette.ink)
                            .frame(width: 44, height: 44)
                            .background(Palette.foam)
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("pauseButton")
                    #if DEBUG
                    Button(action: { model.showDebug = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Palette.ink)
                            .frame(width: 44, height: 44)
                            .background(Palette.sand)
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("debugGear")
                    #endif
                }
            }
            HStack {
                Text(model.safeLane)
                    .font(.system(size: 4))
                    .foregroundColor(Palette.indigo)
                    .frame(width: 24, height: 24)
                    .accessibilityIdentifier("safeLane")
                    .accessibilityLabel(model.safeLane)
                Text(model.jellyfishOnScreen ? "1" : "0")
                    .font(.system(size: 4))
                    .foregroundColor(Palette.indigo)
                    .frame(width: 24, height: 24)
                    .accessibilityIdentifier("jellyfishOnScreen")
                    .accessibilityLabel(model.jellyfishOnScreen ? "1" : "0")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, top + 8)
        .frame(width: width, alignment: .top)
    }

    private var lifeRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index < model.lives ? Palette.board : Palette.ink.opacity(0.35))
                    .frame(width: 22, height: 8)
                    .overlay(
                        Capsule().stroke(Palette.ink, lineWidth: 1.5)
                    )
                    .overlay {
                        if index >= model.lives {
                            Rectangle()
                                .fill(Palette.ink.opacity(0.7))
                                .frame(width: 1.5, height: 12)
                                .rotationEffect(.degrees(35))
                        }
                    }
            }
        }
    }

    private var multiplierText: String {
        let value = model.multiplier
        if abs(value - value.rounded()) < 0.01 {
            return "x\(Int(value.rounded()))"
        }
        return String(format: "x%.1f", value)
    }

    private func menu(size: CGSize) -> some View {
        VStack(spacing: 18) {
            Text("WAVE CATCH")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundColor(Palette.foam)
                .shadow(color: Palette.hotPink, radius: 0, x: 3, y: 3)
            Text("Four spots. One board. Keep the combo.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(Palette.foam)
                .multilineTextAlignment(.center)
            Button(action: { model.startGame() }) {
                Text("Play")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.hotPink)
            .accessibilityIdentifier("playButton")
            Text("Best \(model.bestScore)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(Palette.sun)
        }
        .padding(28)
        .background(Palette.indigo.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.foam, lineWidth: 3))
        .padding(.horizontal, 28)
        .frame(width: size.width, height: size.height)
    }

    private func gameOver(size: CGSize) -> some View {
        VStack(spacing: 14) {
            Text("Game over")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(Palette.foam)
            Text("\(model.score)")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundColor(Palette.sun)
            if model.isNewBest {
                Text("NEW BEST")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Palette.lime)
            }
            Text("Best \(model.bestScore)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Palette.foam)
                .accessibilityIdentifier("bestScore")
            Text("Longest combo \(model.runBestCombo)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Palette.foam)
                .accessibilityIdentifier("longestCombo")
            Button(action: { model.startGame() }) {
                Text("Play again")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.againReady ? Palette.hotPink : Palette.ink)
            .disabled(!model.againReady)
            .accessibilityIdentifier("playAgainButton")
        }
        .padding(24)
        .background(Palette.indigo.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.foam, lineWidth: 3))
        .padding(.horizontal, 24)
        .frame(width: size.width, height: size.height)
    }

    private var pauseCard: some View {
        Text("Paused")
            .font(.system(size: 28, weight: .heavy, design: .rounded))
            .foregroundColor(Palette.ink)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Palette.foam)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

struct DebugPanel: View {
    @ObservedObject var model: GameModel

    var body: some View {
        NavigationView {
            Form {
                slider("Speed", value: $model.tuning.speedMultiplier, range: 0.5...2, step: 0.05, suffix: "x")
                slider("Spawn rate", value: $model.tuning.spawnRateMultiplier, range: 0.5...2, step: 0.05, suffix: "x")
                slider("Jellyfish", value: $model.tuning.jellyfishMultiplier, range: 0...2, step: 0.05, suffix: "x table")
                slider("Big Wave", value: $model.tuning.bigWaveDuration, range: 3...10, step: 0.5, suffix: "s")
                Stepper("Start phase \(model.startPhase)", value: $model.startPhase, in: 1...10)
                Toggle("Large pad", isOn: $model.largePad)
                Toggle("Whole-screen quadrants", isOn: $model.wholeScreenPad)
                Toggle("Diagonal swipe", isOn: $model.swipeEnabled)
                Toggle("Mute", isOn: $model.muted)
            }
            .navigationTitle("Tune")
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        VStack(alignment: .leading) {
            Text("\(title) \(value.wrappedValue, specifier: "%.2f")\(suffix)")
            Slider(value: value, in: range, step: step)
        }
    }
}

struct SceneHost: UIViewRepresentable {
    let scene: GameScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.presentScene(scene)
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        view.isUserInteractionEnabled = false
        view.allowsTransparency = false
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
    }
}
