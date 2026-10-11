import SwiftUI
import SpriteKit
import UIKit
import WaveCatchCore

struct RootView: View {
    @StateObject private var model = GameModel()
    @State private var safeTop: CGFloat = 0
    @State private var safeBottom: CGFloat = 0
    @State private var safeLeft: CGFloat = 0
    @State private var safeRight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let top = max(safeTop, geo.safeAreaInsets.top)
            let bottom = max(safeBottom, geo.safeAreaInsets.bottom)
            let left = max(safeLeft, geo.safeAreaInsets.leading)
            let right = max(safeRight, geo.safeAreaInsets.trailing)
            ZStack(alignment: .topLeading) {
                SafeAreaProbe { insets in
                    let nextTop = insets.top
                    let nextBottom = insets.bottom
                    let nextLeft = insets.left
                    let nextRight = insets.right
                    if abs(nextTop - safeTop) > 0.5 || abs(nextBottom - safeBottom) > 0.5
                        || abs(nextLeft - safeLeft) > 0.5 || abs(nextRight - safeRight) > 0.5 {
                        safeTop = nextTop
                        safeBottom = nextBottom
                        safeLeft = nextLeft
                        safeRight = nextRight
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)

                SceneHost(scene: model.scene)
                    .frame(width: geo.size.width, height: geo.size.height)

                if model.mode == .playing || model.mode == .gameOver {
                    hud(top: top, left: left, right: right, width: geo.size.width)
                }
                if model.mode == .playing {
                    if model.legacyRamps {
                        CornerControls(
                            enabled: model.mode == .playing && !model.paused,
                            swipeEnabled: model.swipeEnabled,
                            pressed: model.pressedLane,
                            large: model.largePad,
                            insets: UIEdgeInsets(top: top, left: left, bottom: bottom, right: right),
                            onLane: { model.setLane($0) }
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        EdgeControls(
                            enabled: !model.paused,
                            onSide: { model.setSide($0) }
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }

                if model.mode == .menu {
                    menu(size: geo.size)
                }
                if model.mode == .gameOver {
                    gameOver(size: geo.size)
                }
                if !model.callout.isEmpty {
                    VStack {
                        CalloutBanner(text: model.callout, color: calloutColor)
                            .id(model.callout)
                            .padding(.top, top + 36)
                        Spacer()
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                }
                if model.newBestRibbon {
                    VStack {
                        Text("NEW BEST!")
                            .font(.custom("Bungee-Regular", size: 22))
                            .foregroundColor(Palette.indigo)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Palette.gold)
                            .clipShape(Capsule())
                            .padding(.top, top + 108)
                        Spacer()
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("newBestRibbon")
                }
                if model.paused && model.mode == .playing {
                    pauseCard
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .background(TuningGesture { model.showTuning = true })
        .sheet(isPresented: $model.showDebug) {
            DebugPanel(model: model)
        }
        .sheet(isPresented: $model.showLicenses) {
            LicensesView()
        }
    }

    private func hud(top: CGFloat, left: CGFloat, right: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        lifeRow
                        Text("\(model.score)")
                            .font(.custom("Bungee-Regular", size: 32))
                            .foregroundColor(Palette.foam)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.buttonPlum))
                            .shadow(color: Palette.buttonPlum.opacity(0.55), radius: 6, y: 2)
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("score")
                            .accessibilityLabel("\(model.score)")
                    }
                    if !model.legacyRamps {
                        pipRow
                    }
                    Text(multiplierText)
                        .font(.custom("Bungee-Regular", size: 16))
                        .foregroundColor(Palette.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(tierColor)
                        .clipShape(Capsule())
                }
                .allowsHitTesting(false)
                Spacer()
                    .allowsHitTesting(false)
                VStack(alignment: .trailing, spacing: 8) {
                    if model.mode == .playing {
                        Button(action: { model.togglePause() }) {
                            Image(systemName: model.paused ? "play.fill" : "pause.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Palette.ink)
                                .frame(width: 44, height: 44)
                                .background(Palette.foam)
                                .clipShape(Circle())
                        }
                        .accessibilityIdentifier("pauseButton")
                    }
                    #if DEBUG
                    if model.proofArmor {
                        Button(action: { model.disarmProof() }) {
                            Text("off")
                                .font(.system(size: 1))
                                .foregroundColor(Palette.buttonSand)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("proofArmor")
                        .accessibilityLabel("proofArmor")
                    }
                    #endif
                    if model.showTuning && model.mode == .playing {
                        Button(action: { model.showDebug = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Palette.ink)
                                .frame(width: 44, height: 44)
                                .background(Palette.sand)
                                .clipShape(Circle())
                        }
                        .accessibilityIdentifier("debugGear")
                    }
                }
            }
            proofProbes
        }
        .padding(.leading, model.legacyRamps ? left + CornerMetrics.side + CornerMetrics.margin + 8 : left + 16)
        .padding(.trailing, model.legacyRamps ? right + CornerMetrics.side + CornerMetrics.margin + 8 : right + 16)
        .padding(.top, top + 8)
        .frame(width: width, alignment: .top)
    }

    /// Kept for XCUITest. Parked offscreen so screenshots, the clip, and release builds stay clean.
    private var proofProbes: some View {
        ZStack(alignment: .topLeading) {
            probe("lives", "\(model.lives)")
            probe("safeLane", model.safeLane)
            probe("jellyfishOnScreen", model.jellyfishOnScreen ? "1" : "0")
            probe("ringLit", model.ringLit ? "1" : "0")
            probe("sawNice", model.sawNice ? "1" : "0")
            probe("sawGolden", model.sawGolden ? "1" : "0")
            probe("sawBigWave", model.sawBigWave ? "1" : "0")
            probe("maxPitch", "\(model.maxPitch)")
            probe("facing", model.facing)
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }

    private func probe(_ identifier: String, _ label: String) -> some View {
        Text(label)
            .font(.system(size: 1))
            .foregroundColor(Palette.indigo)
            .frame(width: 1, height: 1)
            .offset(x: -3000, y: -3000)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
    }

    private var lifeRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(index < model.lives ? Palette.hotPink : Palette.buttonPlum.opacity(0.35))
                    .frame(width: 22, height: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3).stroke(Palette.buttonPlum, lineWidth: 1.5)
                    )
                    .overlay {
                        if index >= model.lives {
                            Path { path in
                                path.move(to: CGPoint(x: 4, y: 2))
                                path.addLine(to: CGPoint(x: 11, y: 6))
                                path.addLine(to: CGPoint(x: 16, y: 3))
                            }
                            .stroke(Palette.buttonPlum, lineWidth: 1.5)
                        }
                    }
            }
        }
    }

    private var pipRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < model.lifePips ? Palette.gold : Palette.buttonPlum.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Palette.buttonPlum, lineWidth: 1))
            }
        }
    }

    private var tierColor: Color {
        switch ScoreMath.tierIndex(for: model.combo) {
        case 1: return Palette.cream
        case 2: return Palette.splashTeal
        case 3: return Palette.hotPink
        case 4: return Palette.gold
        default: return Palette.cream
        }
    }

    private var calloutColor: Color {
        switch model.calloutTier {
        case 1: return Palette.cream
        case 2: return Palette.splashTeal
        case 3: return Palette.hotPink
        default: return Palette.gold
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
        VStack(spacing: 10) {
            Text("WAVE CATCH")
                .font(.custom("Bungee-Regular", size: 40))
                .foregroundColor(Palette.foam)
                .shadow(color: Palette.hotPink, radius: 0, x: 3, y: 3)
            if !model.legacyRamps {
                Text("Wave Pool")
                    .font(.custom("Rubik-Regular", size: 13))
                    .foregroundColor(Palette.sun)
            }
            Text(model.legacyRamps ? "Four spots. One board. Keep the combo." : "Face the swell. Keep the combo.")
                .font(.custom("Rubik-Regular", size: 16))
                .foregroundColor(Palette.foam)
                .multilineTextAlignment(.center)
            Button(action: { model.startGame() }) {
                Text("Play")
                    .font(.custom("Bungee-Regular", size: 28))
                    .foregroundColor(Palette.foam)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(SurfButtonStyle())
            .accessibilityIdentifier("playButton")
            Toggle(isOn: Binding(get: { model.musicOn }, set: { model.setMusicOn($0) })) {
                Text("Music")
                    .font(.custom("Rubik-Regular", size: 16))
                    .foregroundColor(Palette.foam)
            }
            .tint(Palette.hotPink)
            .accessibilityIdentifier("musicToggle")
            Toggle(isOn: Binding(get: { model.effectsOn }, set: { model.setEffectsOn($0) })) {
                Text("Sound effects")
                    .font(.custom("Rubik-Regular", size: 16))
                    .foregroundColor(Palette.foam)
            }
            .tint(Palette.hotPink)
            .accessibilityIdentifier("effectsToggle")
            Button(action: { model.showLicenses = true }) {
                Text("Licenses")
                    .font(.custom("Rubik-Regular", size: 16))
                    .foregroundColor(Palette.sun)
            }
            .accessibilityIdentifier("licensesButton")
            Text("Best \(model.bestScore)")
                .font(.custom("Rubik-Regular", size: 16))
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
        let cardWidth = size.width * 0.55
        let cardHeight = size.height * 0.80
        return ZStack {
            if !model.uitest {
                ConfettiBurst()
                    .allowsHitTesting(false)
            }
            VStack(spacing: 12) {
            Text("Game over")
                .font(.custom("Bungee-Regular", size: 28))
                .foregroundColor(Palette.foam)
            Text("\(model.score)")
                .font(.custom("Bungee-Regular", size: 56))
                .foregroundColor(Palette.sun)
            if model.isNewBest {
                Text("NEW BEST")
                    .font(.custom("Bungee-Regular", size: 18))
                    .foregroundColor(Palette.lime)
                    .accessibilityIdentifier("newBest")
                    .accessibilityLabel("NEW BEST")
            }
            Text("Best \(model.bestScore)")
                .font(.custom("Rubik-Regular", size: 18))
                .foregroundColor(Palette.foam)
                .accessibilityIdentifier("bestScore")
            Text("Longest combo \(model.runBestCombo)")
                .font(.custom("Rubik-Regular", size: 18))
                .foregroundColor(Palette.foam)
                .accessibilityIdentifier("longestCombo")
            Button(action: { model.startGame() }) {
                Text("Play again")
                    .font(.custom("Bungee-Regular", size: 22))
                    .foregroundColor(Palette.foam)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(SurfButtonStyle())
            .disabled(!model.againReady)
            .frame(width: cardWidth * 0.60)
            .accessibilityIdentifier("playAgainButton")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: cardWidth, height: cardHeight)
        .background(Palette.indigo.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.foam, lineWidth: 3))
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
                Toggle("Music", isOn: Binding(get: { model.musicOn }, set: { model.setMusicOn($0) }))
                Toggle("Sound effects", isOn: Binding(get: { model.effectsOn }, set: { model.setEffectsOn($0) }))
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
        view.isUserInteractionEnabled = true
        view.allowsTransparency = false
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
        let bounds = uiView.bounds.size
        guard bounds.width > 10, bounds.height > 10 else { return }
        if abs(scene.size.width - bounds.width) > 1 || abs(scene.size.height - bounds.height) > 1 {
            scene.size = bounds
        }
    }
}

/// Reads `window.safeAreaInsets`, which stays correct when the SwiftUI root is full-bleed.
struct SafeAreaProbe: UIViewRepresentable {
    var onChange: (UIEdgeInsets) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
        uiView.notify()
    }

    final class ProbeView: UIView {
        var onChange: ((UIEdgeInsets) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            return nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            notify()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            notify()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            notify()
        }

        private var lastReported = UIEdgeInsets(top: -1, left: 0, bottom: 0, right: 0)

        func notify() {
            let fromWindow = window?.safeAreaInsets ?? .zero
            let fromSelf = safeAreaInsets
            let insets = UIEdgeInsets(
                top: max(fromWindow.top, fromSelf.top),
                left: max(fromWindow.left, fromSelf.left),
                bottom: max(fromWindow.bottom, fromSelf.bottom),
                right: max(fromWindow.right, fromSelf.right)
            )
            guard insets != .zero, insets != lastReported else { return }
            lastReported = insets
            let report = insets
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(report)
            }
        }
    }
}

/// Hidden 3-finger long-press reveals the tuning gear. It does not steal one-finger taps.
struct TuningGesture: UIViewRepresentable {
    var onReveal: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onReveal = onReveal
        guard context.coordinator.installed == nil else { return }
        DispatchQueue.main.async {
            guard let window = uiView.window, context.coordinator.installed == nil else { return }
            let gesture = UILongPressGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.fired(_:))
            )
            gesture.numberOfTouchesRequired = 3
            gesture.minimumPressDuration = 0.5
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            window.addGestureRecognizer(gesture)
            context.coordinator.installed = gesture
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var onReveal: () -> Void = {}
        var installed: UILongPressGestureRecognizer?

        @objc func fired(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                onReveal()
            }
        }
    }
}

struct SurfButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Palette.hotPink)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Palette.buttonPlum, lineWidth: 2)
            )
            .offset(y: configuration.isPressed ? 4 : 0)
    }
}

struct CalloutBanner: View {
    let text: String
    let color: Color
    @State private var scale: CGFloat = 0.01

    var body: some View {
        Text(text)
            .font(.custom("Bungee-Regular", size: 64))
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 24)
            .shadow(color: Palette.buttonPlum, radius: 0, x: 2, y: 2)
            .scaleEffect(scale)
            .accessibilityIdentifier("callout")
            .accessibilityLabel(text)
            .onAppear {
                withAnimation(.easeOut(duration: 0.18)) {
                    scale = 1.2
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.easeOut(duration: 0.07)) {
                        scale = 1.0
                    }
                }
            }
    }
}

struct ConfettiBurst: View {
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<30, id: \.self) { index in
                ConfettiPiece(index: index, size: geo.size)
            }
        }
    }
}

private struct ConfettiPiece: View {
    let index: Int
    let size: CGSize
    @State private var fall = false

    var body: some View {
        let colors = [Palette.gold, Palette.hotPink, Palette.splashTeal, Palette.cream]
        RoundedRectangle(cornerRadius: 2)
            .fill(colors[index % colors.count])
            .frame(width: 8, height: 14)
            .rotationEffect(.degrees(fall ? Double(index * 24) : 0))
            .position(
                x: size.width * CGFloat((index * 37) % 100) / 100,
                y: fall ? size.height + 20 : -20
            )
            .onAppear {
                withAnimation(.easeIn(duration: 1.2).delay(Double(index) * 0.015)) {
                    fall = true
                }
            }
    }
}

struct LicensesView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                Text(licenseBody)
                    .font(.custom("Rubik-Regular", size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Licenses")
        }
    }

    private var licenseBody: String {
        let chunks = ["OFL-Bungee", "OFL-Rubik"].compactMap { name -> String? in
            let url = Bundle.main.url(forResource: name, withExtension: "txt")
                ?? Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Licenses")
            guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return text
        }
        if chunks.isEmpty {
            return "Font licenses could not be loaded."
        }
        return chunks.joined(separator: "\n\n")
    }
}
