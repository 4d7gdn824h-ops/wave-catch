import SpriteKit
import UIKit
import WaveCatchCore

/// Original "Sunset Pool Club" view. A rectangular pool, not a copy of any real venue.
final class PoolArt {
    var seenSpin = 0
    private let root = SKNode()
    private var poolRect = CGRect.zero
    private var vents: [Side: SKShapeNode] = [:]
    private var caustics: [SKShapeNode] = []
    private var palms: [SKNode] = []
    private let chevron = SKShapeNode()
    private let warm = SKSpriteNode(color: Palette.uiSkyWarm, size: .zero)
    private var waveNodes: [Int: SKNode] = [:]
    private var waveSteps: [Int: Int] = [:]
    private let scales: [CGFloat] = [0.55, 0.65, 0.75, 0.88, 1.0]

    func install(in world: SKNode, size: CGSize) {
        root.removeAllChildren()
        root.removeFromParent()
        vents.removeAll()
        caustics.removeAll()
        palms.removeAll()
        waveNodes.removeAll()
        waveSteps.removeAll()
        world.addChild(root)

        let skyH = size.height * 0.10
        let deck = SKSpriteNode(texture: SKTexture(image: deckImage(size: size, skyH: skyH)), size: size)
        deck.position = CGPoint(x: size.width / 2, y: size.height / 2)
        deck.zPosition = 0
        root.addChild(deck)

        let poolH = size.height * 0.78
        let poolW = min(size.width * 0.62, poolH * 1.15)
        poolRect = CGRect(
            x: (size.width - poolW) / 2,
            y: size.height * 0.08,
            width: poolW,
            height: poolH
        )
        let water = SKSpriteNode(texture: SKTexture(image: waterImage(size: poolRect.size)), size: poolRect.size)
        water.position = CGPoint(x: poolRect.midX, y: poolRect.midY)
        water.zPosition = 1
        root.addChild(water)

        let tiles = SKShapeNode(path: tilePath(around: poolRect))
        tiles.fillColor = .clear
        tiles.strokeColor = .clear
        tiles.zPosition = 1.2
        root.addChild(tiles)
        root.addChild(checkerBorder())

        let outline = SKShapeNode(rect: poolRect.insetBy(dx: -3, dy: -3), cornerRadius: 8)
        outline.fillColor = .clear
        outline.strokeColor = Palette.uiPlum
        outline.lineWidth = 4
        outline.zPosition = 1.5
        root.addChild(outline)

        for index in 0..<5 {
            let line = SKShapeNode()
            line.strokeColor = UIColor.white.withAlphaComponent(0.25)
            line.lineWidth = 2
            line.zPosition = 1.3
            root.addChild(line)
            caustics.append(line)
            _ = index
        }
        addRipples()
        addVents()
        addProps(size: size)
        warm.size = size
        warm.position = CGPoint(x: size.width / 2, y: size.height / 2)
        warm.alpha = 0
        warm.zPosition = 1.6
        root.addChild(warm)

        chevron.path = chevronPath()
        chevron.fillColor = Palette.uiCream
        chevron.strokeColor = Palette.uiPlum
        chevron.lineWidth = 2
        chevron.zPosition = 5.5
        root.addChild(chevron)
    }

    func point(side: Side, step: Int) -> CGPoint {
        let clamped = min(5, max(1, step))
        let u = CGFloat(clamped - 1) / 4
        let center = CGPoint(x: poolRect.midX, y: poolRect.midY)
        let gap: CGFloat = 34
        switch side {
        case .north:
            let wall = poolRect.maxY - 22
            return CGPoint(x: center.x, y: wall + (center.y + gap - wall) * u)
        case .south:
            let wall = poolRect.minY + 22
            return CGPoint(x: center.x, y: wall + (center.y - gap - wall) * u)
        case .east:
            let wall = poolRect.maxX - 22
            return CGPoint(x: wall + (center.x + gap - wall) * u, y: center.y)
        case .west:
            let wall = poolRect.minX + 22
            return CGPoint(x: wall + (center.x - gap - wall) * u, y: center.y)
        }
    }

    func update(session: WavePoolSession?, surfer: SKNode, size: CGSize, now: TimeInterval, bodyScale: inout CGFloat) {
        let drawn: CGFloat = 102
        let scale = max(0.45, size.height * 0.18 / drawn)
        bodyScale = scale
        if surfer.action(forKey: "squash") == nil && surfer.action(forKey: "turn") == nil {
            surfer.setScale(scale)
        }
        let center = CGPoint(x: poolRect.midX, y: poolRect.midY)
        let facing = session?.facing ?? .south
        surfer.position = center
        if surfer.action(forKey: "spin") == nil {
            surfer.zRotation = rotation(facing)
        }
        if let session, session.time < session.rideUntil {
            let nudge = offset(facing, distance: 14)
            surfer.position = CGPoint(x: center.x + nudge.x, y: center.y + nudge.y)
        }
        if let session, session.time < session.wipeUntil {
            surfer.zRotation += sin(CGFloat(now) * 28) * 0.25
        }
        let ahead = offset(facing, distance: 28 * scale)
        chevron.position = CGPoint(x: center.x + ahead.x, y: center.y + ahead.y)
        chevron.zRotation = rotation(facing)
        animateCaustics(now: now)
        let sway = sin(CGFloat(now) * 0.7) * 0.08
        for palm in palms { palm.zRotation = sway }
        let blinking = session?.blinkingVents ?? []
        for (side, vent) in vents {
            let on = blinking.contains(side)
            vent.fillColor = on ? Palette.uiHotPink : Palette.uiPlum.withAlphaComponent(0.35)
            vent.alpha = on ? 0.55 + 0.45 * abs(sin(CGFloat(now) * 10)) : 1
        }
        warm.alpha = (session?.goldenHourRemaining ?? 0) > 0 ? 0.22 : 0
        syncWaves(session)
    }

    private func syncWaves(_ session: WavePoolSession?) {
        let live = session?.liveWaves ?? []
        var alive = Set<Int>()
        for wave in live {
            alive.insert(wave.id)
            let node = waveNodes[wave.id] ?? makeWave(wave.kind)
            if waveNodes[wave.id] == nil {
                waveNodes[wave.id] = node
                root.addChild(node)
            }
            let stepIndex = max(0, min(4, wave.step - 1))
            var crest = scales[stepIndex]
            if wave.kind == .setWave { crest *= 1.28 }
            node.setScale(crest)
            node.position = point(side: wave.side, step: wave.step)
            node.zRotation = rotation(wave.side)
            node.zPosition = 4
            if waveSteps[wave.id] != wave.step {
                waveSteps[wave.id] = wave.step
                node.removeAction(forKey: "hop")
                let squish = SKAction.scale(to: crest * 1.12, duration: 0.02)
                let back = SKAction.scale(to: crest, duration: 0.02)
                node.run(.sequence([squish, back]), withKey: "hop")
            }
        }
        for (id, node) in waveNodes where !alive.contains(id) {
            node.removeFromParent()
            waveNodes[id] = nil
            waveSteps[id] = nil
        }
    }

    private func makeWave(_ kind: WaveKind) -> SKNode {
        let group = SKNode()
        let path = kind == .chop ? spikePath() : crestPath()
        let shadow = SKShapeNode(path: path)
        shadow.fillColor = Palette.uiPlum.withAlphaComponent(0.25)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2, y: -6)
        group.addChild(shadow)
        let body = SKShapeNode(path: path)
        body.strokeColor = Palette.uiPlum
        body.lineWidth = 3
        switch kind {
        case .goldenWave:
            body.fillColor = Palette.uiGold
        case .chop:
            body.fillColor = UIColor(hex: 0x6B3FA0)
        default:
            body.fillColor = Palette.uiWaveFront
        }
        group.addChild(body)
        if kind != .chop {
            let lip = SKShapeNode(path: lipPath())
            lip.strokeColor = Palette.uiCream
            lip.lineWidth = kind == .setWave ? 7 : 4
            lip.fillColor = .clear
            lip.lineCap = .round
            group.addChild(lip)
            if kind == .setWave {
                let second = SKShapeNode(path: lipPath())
                second.strokeColor = Palette.uiCream.withAlphaComponent(0.7)
                second.lineWidth = 3
                second.position = CGPoint(x: 0, y: -6)
                group.addChild(second)
            }
        }
        if kind == .goldenWave {
            let spark = SKShapeNode(circleOfRadius: 4)
            spark.fillColor = Palette.uiCream
            spark.strokeColor = .clear
            spark.position = CGPoint(x: 10, y: 12)
            group.addChild(spark)
        }
        return group
    }

    private func crestPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -46, y: 0))
        path.addQuadCurve(to: CGPoint(x: 46, y: 0), control: CGPoint(x: 0, y: 22))
        path.addQuadCurve(to: CGPoint(x: -46, y: -8), control: CGPoint(x: 0, y: 6))
        path.closeSubpath()
        return path
    }

    private func lipPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -40, y: 4))
        path.addQuadCurve(to: CGPoint(x: 40, y: 4), control: CGPoint(x: 0, y: 26))
        return path
    }

    private func spikePath() -> CGPath {
        let path = CGMutablePath()
        let spikes = 7
        for index in 0..<(spikes * 2) {
            let radius: CGFloat = index % 2 == 0 ? 22 : 10
            let angle = CGFloat(index) * .pi / CGFloat(spikes)
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius * 0.7)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func chevronPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 10))
        path.addLine(to: CGPoint(x: 8, y: -6))
        path.addLine(to: CGPoint(x: 0, y: -1))
        path.addLine(to: CGPoint(x: -8, y: -6))
        path.closeSubpath()
        return path
    }

    func rotation(for side: Side) -> CGFloat {
        rotation(side)
    }

    private func rotation(_ side: Side) -> CGFloat {
        switch side {
        case .north: return 0
        case .east: return -.pi / 2
        case .south: return .pi
        case .west: return .pi / 2
        }
    }

    private func offset(_ side: Side, distance: CGFloat) -> CGPoint {
        switch side {
        case .north: return CGPoint(x: 0, y: distance)
        case .south: return CGPoint(x: 0, y: -distance)
        case .east: return CGPoint(x: distance, y: 0)
        case .west: return CGPoint(x: -distance, y: 0)
        }
    }

    private func addRipples() {
        for side in Side.allCases {
            for step in 1...5 {
                let ring = SKShapeNode(circleOfRadius: 12)
                ring.strokeColor = Palette.uiCream.withAlphaComponent(0.28)
                ring.fillColor = .clear
                ring.lineWidth = 1.5
                ring.position = point(side: side, step: step)
                ring.zPosition = 1.4
                root.addChild(ring)
            }
        }
    }

    private func addVents() {
        for side in Side.allCases {
            let vent = SKShapeNode(rectOf: CGSize(width: 28, height: 14), cornerRadius: 4)
            vent.fillColor = Palette.uiPlum.withAlphaComponent(0.35)
            vent.strokeColor = Palette.uiPlum
            vent.lineWidth = 2
            vent.zPosition = 1.7
            switch side {
            case .north: vent.position = CGPoint(x: poolRect.midX, y: poolRect.maxY - 8)
            case .south: vent.position = CGPoint(x: poolRect.midX, y: poolRect.minY + 8)
            case .east:
                vent.position = CGPoint(x: poolRect.maxX - 8, y: poolRect.midY)
                vent.zRotation = .pi / 2
            case .west:
                vent.position = CGPoint(x: poolRect.minX + 8, y: poolRect.midY)
                vent.zRotation = .pi / 2
            }
            root.addChild(vent)
            vents[side] = vent
        }
    }

    private func addProps(size: CGSize) {
        addUmbrella(at: CGPoint(x: poolRect.minX - 54, y: poolRect.maxY - 20))
        addUmbrella(at: CGPoint(x: poolRect.maxX + 58, y: poolRect.minY + 36))
        addLounge(at: CGPoint(x: poolRect.minX + 36, y: poolRect.minY - 28))
        addPalm(at: CGPoint(x: 46, y: size.height * 0.22))
        addPalm(at: CGPoint(x: size.width - 52, y: size.height * 0.72))
    }

    private func addUmbrella(at point: CGPoint) {
        let pole = SKShapeNode(rectOf: CGSize(width: 4, height: 28))
        pole.fillColor = Palette.uiPlum
        pole.strokeColor = .clear
        pole.position = point
        pole.zPosition = 1.8
        root.addChild(pole)
        let cap = SKShapeNode(path: umbrellaPath())
        cap.fillColor = Palette.uiHotPink
        cap.strokeColor = Palette.uiPlum
        cap.lineWidth = 2
        cap.position = CGPoint(x: point.x, y: point.y + 16)
        cap.zPosition = 1.85
        root.addChild(cap)
        let stripe = SKShapeNode(rectOf: CGSize(width: 6, height: 16))
        stripe.fillColor = Palette.uiCream
        stripe.strokeColor = .clear
        stripe.position = CGPoint(x: 0, y: 4)
        cap.addChild(stripe)
    }

    private func umbrellaPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -22, y: 0))
        path.addQuadCurve(to: CGPoint(x: 22, y: 0), control: CGPoint(x: 0, y: 18))
        path.closeSubpath()
        return path
    }

    private func addLounge(at point: CGPoint) {
        let chair = SKShapeNode(rectOf: CGSize(width: 46, height: 16), cornerRadius: 4)
        chair.fillColor = Palette.uiSea
        chair.strokeColor = Palette.uiPlum
        chair.lineWidth = 2
        chair.position = point
        chair.zRotation = -0.2
        chair.zPosition = 1.8
        root.addChild(chair)
    }

    private func addPalm(at point: CGPoint) {
        let shade = SKNode()
        shade.position = point
        shade.zPosition = 0.4
        shade.alpha = 0.35
        for index in 0..<5 {
            let frond = SKShapeNode(ellipseOf: CGSize(width: 26, height: 8))
            frond.fillColor = Palette.uiPlum
            frond.strokeColor = .clear
            frond.zRotation = CGFloat(index) * 0.55 - 1.1
            shade.addChild(frond)
        }
        root.addChild(shade)
        palms.append(shade)
    }

    private func checkerBorder() -> SKNode {
        let group = SKNode()
        group.zPosition = 1.45
        let tile: CGFloat = 14
        func place(_ origin: CGPoint, horizontal: Bool, count: Int) {
            for index in 0..<count {
                let node = SKShapeNode(rectOf: CGSize(width: tile - 1, height: tile - 1))
                node.fillColor = index % 2 == 0 ? Palette.uiCloud : Palette.uiShell
                node.strokeColor = Palette.uiPlum.withAlphaComponent(0.35)
                node.lineWidth = 1
                if horizontal {
                    node.position = CGPoint(x: origin.x + CGFloat(index) * tile, y: origin.y)
                } else {
                    node.position = CGPoint(x: origin.x, y: origin.y + CGFloat(index) * tile)
                }
                group.addChild(node)
            }
        }
        let across = Int(poolRect.width / tile)
        let up = Int(poolRect.height / tile)
        place(CGPoint(x: poolRect.minX + tile / 2, y: poolRect.maxY + 8), horizontal: true, count: across)
        place(CGPoint(x: poolRect.minX + tile / 2, y: poolRect.minY - 8), horizontal: true, count: across)
        place(CGPoint(x: poolRect.minX - 8, y: poolRect.minY + tile / 2), horizontal: false, count: up)
        place(CGPoint(x: poolRect.maxX + 8, y: poolRect.minY + tile / 2), horizontal: false, count: up)
        return group
    }

    private func tilePath(around rect: CGRect) -> CGPath {
        CGPath(rect: rect, transform: nil)
    }

    private func animateCaustics(now: TimeInterval) {
        for (index, line) in caustics.enumerated() {
            let path = CGMutablePath()
            let y = poolRect.minY + 24 + CGFloat(index) * (poolRect.height - 48) / 4
            path.move(to: CGPoint(x: poolRect.minX + 16, y: y))
            var x = poolRect.minX + 16
            while x < poolRect.maxX - 16 {
                let next = min(poolRect.maxX - 16, x + 36)
                let lift = sin(CGFloat(now) * 1.4 + x * 0.02 + CGFloat(index)) * 7
                path.addQuadCurve(
                    to: CGPoint(x: next, y: y),
                    control: CGPoint(x: (x + next) / 2, y: y + lift)
                )
                x = next
            }
            line.path = path
        }
    }

    private func deckImage(size: CGSize, skyH: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [Palette.uiSkyTop, Palette.uiSkyMid, Palette.uiSkyWarm, Palette.uiSkyHorizon].map(\.cgColor) as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.38, 0.7, 1]) {
                cg.saveGState()
                cg.clip(to: CGRect(x: 0, y: 0, width: size.width, height: skyH))
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: skyH), options: [])
                cg.restoreGState()
            }
            let sun = CGRect(x: size.width * 0.78, y: skyH * 0.25, width: 28, height: 28)
            cg.setFillColor(Palette.uiSunDisc.cgColor)
            cg.fillEllipse(in: sun)
            cg.setFillColor(UIColor(hex: 0xF6D7A7).cgColor)
            cg.fill(CGRect(x: 0, y: skyH, width: size.width, height: size.height - skyH))
            cg.setFillColor(Palette.uiPlum.withAlphaComponent(0.14).cgColor)
            var y = skyH + 16
            var row = 0
            while y < size.height - 8 {
                var x: CGFloat = row % 2 == 0 ? 12 : 20
                while x < size.width - 8 {
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
                    x += 16
                }
                y += 14
                row += 1
            }
        }
    }

    private func waterImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let colors = [UIColor(hex: 0x2BC6D4).cgColor, Palette.uiWaveFront.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }
}
