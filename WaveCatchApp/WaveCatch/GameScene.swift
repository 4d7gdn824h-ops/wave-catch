import SpriteKit
import UIKit
import WaveCatchCore

final class GameScene: SKScene {
    weak var model: GameModel?
    private let world = SKNode()
    private var backdrop: SKSpriteNode?
    private var backdropSize = CGSize.zero
    private let surfer = SKNode()
    private var objectNodes: [Int: SKNode] = [:]
    private var objectSteps: [Int: Int] = [:]
    private var waveNodes: [SKShapeNode] = []
    private let cloudFar = SKNode()
    private let cloudNear = SKNode()
    private var heatNode: SKSpriteNode?
    private var ringNodes: [Lane: SKNode] = [:]
    private var ringKind: [Lane: ObjectKind] = [:]
    private var ringUntil: [Lane: TimeInterval] = [:]
    private var chuteGroups: [SKNode] = []
    private var glints: [SKNode] = []
    private var foamLine: SKShapeNode?
    /// Items are 30% larger than the previous pass. The surfer is 40% larger.
    private let itemScale: CGFloat = 1.3 * 1.3
    private let surferScale: CGFloat = 1.4
    var bodyScale: CGFloat = 1.4
    private var backdropIsPool: Bool?
    private let poolArt = PoolArt()
    private var lastFacing: Side?
    private var poseFrom = CGPoint.zero
    private var poseTo = CGPoint.zero
    private var poseStart: TimeInterval = 0
    private var logicalLane: Lane = .lowerLeft
    private var lastTime: TimeInterval?
    private var shakeStart: TimeInterval = 0
    private var shakeDuration = 0.0
    private var shakeAmplitude: CGFloat = 0
    private var shaking = false

    override init() {
        super.init(size: CGSize(width: 932, height: 430))
        scaleMode = .resizeFill
        backgroundColor = Palette.uiIndigo
        addChild(world)
        world.addChild(surfer)
        drawSurfer()
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    func attach(_ session: GameSession) {
        objectNodes.values.forEach { $0.removeFromParent() }
        objectNodes.removeAll()
        objectSteps.removeAll()
        ringNodes.values.forEach { $0.removeFromParent() }
        ringNodes.removeAll()
        logicalLane = session.position
        poseFrom = poseTarget(session.position)
        poseTo = poseFrom
        lastTime = nil
        ringKind.removeAll()
        ringUntil.removeAll()
    }

    override func update(_ currentTime: TimeInterval) {
        let elapsed: Double
        if let lastTime {
            elapsed = min(1, max(0, currentTime - lastTime))
        } else {
            elapsed = 0
        }
        lastTime = currentTime
        // A stalled frame, including XCTest sleeps on the main thread, still has to
        // play every tick that came due. One 50 ms cap dropped that time on the floor
        // and the next swell never arrived during the proof.
        var left = elapsed
        while left > 0.0001 {
            let slice = min(1.0 / 60.0, left)
            model?.advance(dt: slice)
            left -= slice
        }
        speed = model?.timeScale ?? 1
        layout(now: currentTime)
    }

    func present(_ events: [GameEvent], session: GameSession) {
        let reduce = UIAccessibility.isReduceMotionEnabled
        _ = session
        for event in events {
            switch event {
            case .caught(_, let lane, let kind, let points, let combo, let close):
                popScore(points, combo: combo, lane: lane)
                if close {
                    float(text: "CLOSE!", lane: lane, color: Palette.uiSun)
                }
                splash(at: sk(LaneGeometry.catchSpot(lane)), golden: kind == .goldenShell)
                playCatchSquash()
            case .dodged(_, let lane):
                float(text: "DODGE!", lane: lane, color: Palette.uiSea)
            case .missed(_, let lane, _, let lifeLost):
                float(text: lifeLost ? "MISS" : "SAFE", lane: lane, color: Palette.uiHotPink)
                if lifeLost {
                    splash(at: sk(LaneGeometry.catchSpot(lane)), golden: false)
                    playMissWobble()
                    beginShake(amplitude: 8, duration: 0.25, now: lastTime ?? 0, reduce: reduce)
                }
            case .stung(_, let lane, _):
                float(text: "STING", lane: lane, color: Palette.uiJelly)
                beginShake(amplitude: 10, duration: 0.30, now: lastTime ?? 0, reduce: reduce)
                flashSurfer()
            case .tierReached(_, _):
                beginShake(amplitude: 4, duration: 0.15, now: lastTime ?? 0, reduce: reduce)
            case .bigWaveEnd:
                splash(at: CGPoint(x: size.width / 2, y: size.height * 0.42), golden: false)
            case .gameOver:
                beginShake(amplitude: 10, duration: 0.30, now: lastTime ?? 0, reduce: reduce)
            default:
                break
            }
        }
    }

    private func layout(now: TimeInterval) {
        let wantPool = model?.legacyRamps == false
        if backdrop == nil || abs(backdropSize.width - size.width) > 2 || abs(backdropSize.height - size.height) > 2 || backdropIsPool != wantPool {
            backdropIsPool = wantPool
            rebuildBackdrop()
        }
        if wantPool {
            layoutPool(now: now)
            return
        }
        world.position = shakeOffset(now: now)
        animateDressing(now: now)
        guard let session = model?.session, model?.mode != .menu else {
            placeSurfer(at: poseTo, now: now)
            return
        }
        if session.position != logicalLane {
            poseFrom = currentPose(now: now)
            poseTo = poseTarget(session.position)
            poseStart = now
            logicalLane = session.position
        }
        placeSurfer(at: currentPose(now: now), now: now)
        animateSea(now: now, session: session)
        syncObjects(session)
        syncRings(session, now: now)
    }

    private func rebuildBackdrop() {
        if backdropIsPool == true {
            rebuildPool()
            return
        }
        chuteGroups.removeAll()
        glints.removeAll()
        foamLine = nil
        for child in world.children where child !== surfer {
            child.removeFromParent()
        }
        objectNodes.removeAll()
        objectSteps.removeAll()
        ringNodes.removeAll()
        waveNodes.removeAll()
        let image = skyImage(size: size)
        let sprite = SKSpriteNode(texture: SKTexture(image: image), size: size)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.zPosition = 0
        world.addChild(sprite)
        backdrop = sprite
        backdropSize = size
        addSun()
        addClouds()
        addSea()
        addShore()
        addGlints()
        addChutes()
        addHeat()
    }

    private func skyImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let colors = [Palette.uiSkyTop, Palette.uiSkyMid, Palette.uiSkyWarm, Palette.uiSkyHorizon].map(\.cgColor) as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            let stops: [CGFloat] = [0, 0.38, 0.68, 1]
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: stops) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }

    private func addSun() {
        let center = sk(LaneGeometry.Point(x: 0.50, y: 0.06))
        let glow = SKShapeNode(circleOfRadius: 42 * 1.6)
        glow.fillColor = Palette.uiSunDisc.withAlphaComponent(0.35)
        glow.strokeColor = .clear
        glow.position = center
        glow.zPosition = 1
        world.addChild(glow)
        let sun = SKShapeNode(circleOfRadius: 42)
        sun.fillColor = Palette.uiSunDisc
        sun.strokeColor = Palette.uiPlum
        sun.lineWidth = 3
        sun.position = center
        sun.zPosition = 1.05
        world.addChild(sun)
        for index in 0..<3 {
            let band = SKShapeNode(rectOf: CGSize(width: 92, height: 7), cornerRadius: 2)
            band.fillColor = Palette.uiSkyWarm.withAlphaComponent(0.9)
            band.strokeColor = .clear
            band.position = CGPoint(x: center.x, y: center.y + 22 - CGFloat(index) * 20)
            band.zPosition = 1.1
            world.addChild(band)
        }
    }

    private func addClouds() {
        cloudFar.removeAllChildren()
        cloudNear.removeAllChildren()
        cloudFar.zPosition = 1.3
        cloudNear.zPosition = 1.45
        world.addChild(cloudFar)
        world.addChild(cloudNear)
        addCloudBlobs(into: cloudFar, y: size.height * 0.78, scale: 1)
        addCloudBlobs(into: cloudNear, y: size.height * 0.66, scale: 1.25)
    }

    private func addCloudBlobs(into parent: SKNode, y: CGFloat, scale: CGFloat) {
        for index in 0..<3 {
            let cloud = SKShapeNode(ellipseOf: CGSize(width: 120 * scale, height: 36 * scale))
            cloud.fillColor = Palette.uiCloud
            cloud.strokeColor = Palette.uiPlum.withAlphaComponent(0.35)
            cloud.lineWidth = 2
            cloud.position = CGPoint(x: CGFloat(index) * size.width * 0.42, y: y)
            parent.addChild(cloud)
        }
    }

    private func addSea() {
        waveNodes = (0..<3).map { _ in
            let node = SKShapeNode()
            node.strokeColor = .clear
            node.zPosition = 2
            world.addChild(node)
            return node
        }
    }

    private func addChutes() {
        for lane in Lane.allCases {
            let group = SKNode()
            group.zPosition = 3
            let samples = (0...28).map { index -> CGPoint in
                let point = LaneGeometry.point(lane: lane, progress: Double(index) / 28)
                return CGPoint(x: point.x * size.width, y: point.y * size.height)
            }
            let image = chuteImage(samples: samples, size: size)
            let sprite = SKSpriteNode(texture: SKTexture(image: image), size: size)
            sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
            group.addChild(sprite)
            for step in 1...LaneGeometry.stepCount {
                let ring = SKShapeNode(circleOfRadius: 14)
                ring.strokeColor = Palette.uiCream.withAlphaComponent(0.16)
                ring.fillColor = .clear
                ring.lineWidth = 1.5
                ring.position = sk(LaneGeometry.point(lane: lane, step: step))
                ring.zPosition = 1
                group.addChild(ring)
            }
            world.addChild(group)
            chuteGroups.append(group)
        }
    }

    /// Crescent tube in UIKit coordinates: deep teal at the lip, light teal at the drop.
    private func chuteImage(samples: [CGPoint], size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.addPath(ribbonPath(samples, width: 62))
            cg.clip()
            drawTubeGradient(in: cg, samples: samples, from: Palette.uiWaveBack, to: Palette.uiWaveFront)
            cg.setFillColor(Palette.uiPlum.withAlphaComponent(0.16).cgColor)
            for (index, point) in samples.enumerated() where index % 2 == 0 {
                cg.fillEllipse(in: CGRect(x: point.x - 1.6, y: point.y - 1.6, width: 3.2, height: 3.2))
            }
            cg.restoreGState()
            cg.saveGState()
            cg.addPath(ribbonPath(samples, width: 28))
            cg.clip()
            drawTubeGradient(in: cg, samples: samples, from: Palette.uiWaveMid, to: Palette.uiWaveFront)
            cg.restoreGState()
            cg.setStrokeColor(Palette.uiCream.cgColor)
            cg.setLineWidth(8)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.addPath(lipPath(samples))
            cg.strokePath()
            guard let end = samples.last else { return }
            for index in 0..<7 {
                let spread = CGFloat(index) - 3
                let radius: CGFloat = index % 2 == 0 ? 3.4 : 2.5
                let rect = CGRect(
                    x: end.x + spread * 8 - radius,
                    y: end.y + 12 + CGFloat(index % 3) * 5 - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                let color = index % 2 == 0 ? Palette.uiCream : Palette.uiWaveFront
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: rect)
            }
        }
    }

    private func drawTubeGradient(in cg: CGContext, samples: [CGPoint], from: UIColor, to: UIColor) {
        let colors = [from.cgColor, to.cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        let start = samples.first ?? .zero
        let end = samples.last ?? start
        cg.drawLinearGradient(gradient, start: start, end: end, options: [])
    }

    /// Cream lip along the skyward edge, curled with a quad so it reads as foam folding over.
    private func lipPath(_ centers: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        var points: [CGPoint] = []
        for index in centers.indices {
            let previous = centers[max(0, index - 1)]
            let next = centers[min(centers.count - 1, index + 1)]
            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let length = max(1, hypot(dx, dy))
            var nx = -dy / length
            var ny = dx / length
            if ny > 0 {
                nx = -nx
                ny = -ny
            }
            let curl: CGFloat = index % 5 == 2 ? 16 : 6
            points.append(CGPoint(x: centers[index].x + nx * (30 + curl), y: centers[index].y + ny * 26))
        }
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let point = points[index]
            let control = CGPoint(
                x: (previous.x + point.x) / 2,
                y: (previous.y + point.y) / 2 - 10
            )
            path.addQuadCurve(to: point, control: control)
        }
        return path
    }

    private func addShore() {
        let shoreHeight = size.height * 0.18
        let image = shoreImage(width: size.width, height: shoreHeight)
        let sprite = SKSpriteNode(texture: SKTexture(image: image), size: CGSize(width: size.width, height: shoreHeight))
        sprite.position = CGPoint(x: size.width / 2, y: shoreHeight / 2)
        sprite.zPosition = 2.75
        world.addChild(sprite)
        let line = SKShapeNode()
        line.strokeColor = Palette.uiCream
        line.lineWidth = 4
        line.lineCap = .round
        line.zPosition = 2.9
        world.addChild(line)
        foamLine = line
        addBeachProps(band: shoreHeight)
    }

    private func shoreImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor(hex: 0xF6D7A7).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            cg.setFillColor(UIColor(hex: 0xE7C48A).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: width, height: 8))
            cg.setFillColor(Palette.uiPlum.withAlphaComponent(0.16).cgColor)
            var y: CGFloat = 18
            var row = 0
            while y < height - 8 {
                var x: CGFloat = row % 2 == 0 ? 10 : 18
                while x < width - 8 {
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
                    x += 16
                }
                y += 14
                row += 1
            }
        }
    }

    private func addBeachProps(band: CGFloat) {
        addStarfish(at: CGPoint(x: size.width * 0.34, y: band * 0.42))
        addTowel(at: CGPoint(x: size.width * 0.52, y: band * 0.36))
        addPalmShadow(at: CGPoint(x: size.width * 0.68, y: band * 0.48))
    }

    private func addStarfish(at point: CGPoint) {
        let path = CGMutablePath()
        let spikes = 5
        for index in 0..<(spikes * 2) {
            let radius: CGFloat = index % 2 == 0 ? 16 : 6
            let angle = CGFloat(index) * .pi / CGFloat(spikes) - .pi / 2
            let vertex = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if index == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
        }
        path.closeSubpath()
        let star = SKShapeNode(path: path)
        star.fillColor = Palette.uiTangerine
        star.strokeColor = Palette.uiPlum
        star.lineWidth = 2
        star.position = point
        star.zPosition = 2.95
        world.addChild(star)
    }

    private func addTowel(at point: CGPoint) {
        let towel = SKShapeNode(rectOf: CGSize(width: 54, height: 28), cornerRadius: 4)
        towel.fillColor = Palette.uiHotPink
        towel.strokeColor = Palette.uiPlum
        towel.lineWidth = 2
        towel.position = point
        towel.zRotation = -0.18
        towel.zPosition = 2.95
        world.addChild(towel)
        for index in 0..<3 {
            let stripe = SKShapeNode(rectOf: CGSize(width: 8, height: 24), cornerRadius: 2)
            stripe.fillColor = index == 1 ? Palette.uiSun : Palette.uiCream
            stripe.strokeColor = .clear
            stripe.position = CGPoint(x: CGFloat(index - 1) * 14, y: 0)
            stripe.zPosition = 0.1
            towel.addChild(stripe)
        }
    }

    private func addPalmShadow(at point: CGPoint) {
        let shade = SKNode()
        shade.position = point
        shade.zPosition = 2.92
        shade.alpha = 0.38
        let trunk = SKShapeNode(ellipseOf: CGSize(width: 10, height: 22))
        trunk.fillColor = Palette.uiPlum
        trunk.strokeColor = .clear
        trunk.position = CGPoint(x: 8, y: -6)
        trunk.zRotation = 0.5
        shade.addChild(trunk)
        for index in 0..<5 {
            let frond = SKShapeNode(ellipseOf: CGSize(width: 28, height: 8))
            frond.fillColor = Palette.uiPlum
            frond.strokeColor = .clear
            frond.zRotation = CGFloat(index) * 0.55 - 1.2
            frond.position = CGPoint(x: CGFloat(index - 2) * 6, y: 4)
            shade.addChild(frond)
        }
        world.addChild(shade)
    }

    private func addGlints() {
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (0.34, 0.68, 0.4),
            (0.48, 0.74, -0.25),
            (0.63, 0.66, 0.55),
            (0.55, 0.80, -0.15),
        ]
        for (x, y, rotation) in spots {
            let streak = SKShapeNode(rectOf: CGSize(width: 46, height: 3), cornerRadius: 1.5)
            streak.fillColor = UIColor.white.withAlphaComponent(0.75)
            streak.strokeColor = .clear
            streak.position = sk(LaneGeometry.Point(x: x, y: y))
            streak.zRotation = rotation
            streak.zPosition = 2.65
            world.addChild(streak)
            glints.append(streak)
        }
    }

    private func animateDressing(now: TimeInterval) {
        let bob = sin(CGFloat(now) * .pi) * 6
        for group in chuteGroups {
            group.position = CGPoint(x: 0, y: bob)
        }
        if let foamLine {
            let base = size.height * 0.18
            let path = CGMutablePath()
            let steps = 28
            for index in 0...steps {
                let x = -8 + (size.width + 16) * CGFloat(index) / CGFloat(steps)
                let wave = sin(CGFloat(now) * 2.4 + x * 0.018) * 5
                let y = base + wave
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            foamLine.path = path
        }
        for (index, glint) in glints.enumerated() {
            let phase = CGFloat(now) * 1.7 + CGFloat(index) * 0.9
            glint.alpha = 0.2 + 0.65 * (0.5 + 0.5 * sin(phase))
        }
    }

    private func ribbonPath(_ centers: [CGPoint], width: CGFloat) -> CGPath {
        guard centers.count > 1 else { return CGMutablePath() }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for index in centers.indices {
            let previous = centers[max(0, index - 1)]
            let next = centers[min(centers.count - 1, index + 1)]
            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let length = max(1, hypot(dx, dy))
            let nx = -dy / length * width / 2
            let ny = dx / length * width / 2
            left.append(CGPoint(x: centers[index].x + nx, y: centers[index].y + ny))
            right.append(CGPoint(x: centers[index].x - nx, y: centers[index].y - ny))
        }
        let path = CGMutablePath()
        path.move(to: left[0])
        for point in left.dropFirst() { path.addLine(to: point) }
        for point in right.reversed() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private func addHeat() {
        let heat = SKSpriteNode(color: Palette.uiSkyWarm, size: size)
        heat.position = CGPoint(x: size.width / 2, y: size.height / 2)
        heat.alpha = 0
        heat.zPosition = 1.6
        world.addChild(heat)
        heatNode = heat
    }

    private func animateSea(now: TimeInterval, session: GameSession) {
        let bands: [(UIColor, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (Palette.uiWaveBack, 0.58, 3, 3.2, 2.1),
            (Palette.uiWaveMid, 0.48, 5, 2.6, 2.3),
            (Palette.uiWaveFront, 0.36, 8, 2.0, 2.5),
        ]
        let rise: CGFloat
        switch session.bigWavePhase {
        case .warning: rise = 28
        case .active: rise = 18
        default: rise = 0
        }
        for (index, node) in waveNodes.enumerated() where index < bands.count {
            let band = bands[index]
            node.fillColor = band.0
            node.path = seaPath(base: band.1, amplitude: band.2, period: band.3, now: now, rise: rise)
            node.zPosition = band.4
        }
        let phase = CGFloat(max(0, session.phaseIndex))
        let hotter: CGFloat = session.bigWavePhase == .active ? 0.16 : 0
        heatNode?.alpha = min(0.34, phase * 0.035 + hotter)
        let far = CGFloat(now) * 6
        let near = CGFloat(now) * 12
        cloudFar.position = CGPoint(x: -far.truncatingRemainder(dividingBy: size.width * 0.42), y: 0)
        cloudNear.position = CGPoint(x: -near.truncatingRemainder(dividingBy: size.width * 0.42), y: 0)
    }

    private func seaPath(base: CGFloat, amplitude: CGFloat, period: CGFloat, now: TimeInterval, rise: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let crest = size.height * base + rise
        path.move(to: CGPoint(x: -20, y: 0))
        path.addLine(to: CGPoint(x: -20, y: crest))
        let steps = 24
        for index in 0...steps {
            let x = -20 + (size.width + 40) * CGFloat(index) / CGFloat(steps)
            let bob = sin((CGFloat(now) / period) * .pi * 2 + x * 0.01) * amplitude
            path.addLine(to: CGPoint(x: x, y: crest + bob))
        }
        path.addLine(to: CGPoint(x: size.width + 20, y: 0))
        path.closeSubpath()
        return path
    }

    private func syncObjects(_ session: GameSession) {
        var alive = Set<Int>()
        for object in session.liveObjects {
            alive.insert(object.id)
            let node = objectNodes[object.id] ?? makeObject(object.kind)
            if objectNodes[object.id] == nil {
                objectNodes[object.id] = node
                node.setScale(baseScale(object.kind))
                world.addChild(node)
            }
            let spot = LaneGeometry.point(lane: object.lane, step: object.step)
            var point = sk(spot)
            if object.wobbling {
                point.x += sin(CGFloat(session.time) * 46) * 7
            }
            node.position = point
            node.zPosition = 5
            poseItem(node, object: object)
        }
        for (id, node) in objectNodes where !alive.contains(id) {
            node.run(.sequence([
                .group([.scale(to: node.xScale * 1.15, duration: 0.08), .fadeOut(withDuration: 0.14)]),
                .removeFromParent(),
            ]))
            objectNodes[id] = nil
        }
    }

    private func syncRings(_ session: GameSession, now: TimeInterval) {
        var shown: [Lane: ObjectKind] = [:]
        for object in session.liveObjects where object.telegraph {
            if shown[object.lane] == nil || object.kind == .jellyfish {
                shown[object.lane] = object.kind
            }
        }
        for (lane, kind) in shown {
            ringKind[lane] = kind
            ringUntil[lane] = now + 0.35
        }
        for lane in Lane.allCases {
            let until = ringUntil[lane] ?? 0
            guard until > now, let kind = ringKind[lane] else {
                ringNodes[lane]?.removeFromParent()
                ringNodes[lane] = nil
                ringKind[lane] = nil
                ringUntil[lane] = nil
                continue
            }
            let node = ringNodes[lane]
            if node == nil || node?.name != kind.rawValue {
                node?.removeFromParent()
                let made = makeRing(kind)
                ringNodes[lane] = made
                world.addChild(made)
            }
            guard let ring = ringNodes[lane] else { continue }
            ring.position = sk(LaneGeometry.catchSpot(lane))
            ring.zPosition = 8
            ring.alpha = shown[lane] == nil ? CGFloat(max(0, (until - now) / 0.35)) : 1
        }
    }

    private func makeRing(_ kind: ObjectKind) -> SKNode {
        let path = ringPath(kind: kind)
        let group = SKNode()
        group.name = kind.rawValue
        let outline = SKShapeNode(path: path)
        outline.strokeColor = Palette.uiPlum
        outline.fillColor = .clear
        outline.lineWidth = kind == .jellyfish ? 18 : 20
        outline.lineJoin = .round
        let front = SKShapeNode(path: path)
        front.lineJoin = .round
        front.lineWidth = 10
        if kind == .jellyfish {
            front.strokeColor = Palette.uiJelly
            front.fillColor = Palette.uiJelly.withAlphaComponent(0.33)
        } else {
            front.strokeColor = Palette.uiFoam
            front.fillColor = Palette.uiFoam.withAlphaComponent(0.28)
        }
        group.addChild(outline)
        group.addChild(front)
        return group
    }

    private func ringPath(kind: ObjectKind) -> CGPath {
        if kind == .jellyfish {
            let path = CGMutablePath()
            let spikes = 10
            let outer: CGFloat = 68
            let inner: CGFloat = 44
            for index in 0..<(spikes * 2) {
                let radius = index % 2 == 0 ? outer : inner
                let angle = CGFloat(index) * .pi / CGFloat(spikes) - .pi / 2
                let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
        return CGPath(ellipseIn: CGRect(x: -58, y: -58, width: 116, height: 116), transform: nil)
    }

    private func makeObject(_ kind: ObjectKind) -> SKNode {
        let root = SKNode()
        root.name = kind.rawValue
        let shadow = SKShapeNode(path: objectPath(kind))
        shadow.fillColor = Palette.uiPlum.withAlphaComponent(0.25)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -4)
        shadow.zPosition = -1
        let body = SKShapeNode(path: objectPath(kind))
        body.name = "body"
        body.lineWidth = 3
        body.strokeColor = Palette.uiPlum
        body.lineJoin = .round
        body.fillColor = fillColor(kind)
        let spec = SKShapeNode(circleOfRadius: 4)
        spec.name = "spec"
        spec.fillColor = UIColor.white.withAlphaComponent(0.9)
        spec.strokeColor = .clear
        spec.position = CGPoint(x: -6, y: 10)
        root.addChild(shadow)
        root.addChild(body)
        root.addChild(spec)
        if kind == .goldenShell {
            let glow = SKShapeNode(circleOfRadius: 25)
            glow.fillColor = Palette.uiGold.withAlphaComponent(0.45)
            glow.strokeColor = Palette.uiGold
            glow.lineWidth = 2
            glow.zPosition = -0.5
            root.addChild(glow)
            let spark = SKShapeNode(path: sparklePath())
            spark.fillColor = Palette.uiGold
            spark.strokeColor = Palette.uiCream
            spark.lineWidth = 1.5
            spark.position = CGPoint(x: 22, y: 18)
            spark.zPosition = 2
            spark.name = "spark"
            root.addChild(spark)
            spark.run(.repeatForever(.sequence([
                .group([.scale(to: 1.35, duration: 0.16), .fadeAlpha(to: 1, duration: 0.16)]),
                .group([.scale(to: 0.55, duration: 0.2), .fadeAlpha(to: 0.3, duration: 0.2)]),
            ])))
        }
        if kind == .board {
            let stripe = SKShapeNode(rectOf: CGSize(width: 22, height: 8), cornerRadius: 2)
            stripe.fillColor = Palette.uiHotPink
            stripe.strokeColor = .clear
            stripe.position = CGPoint(x: 0, y: 6)
            stripe.zRotation = 0.2
            body.addChild(stripe)
        }
        return root
    }

    private func fillColor(_ kind: ObjectKind) -> UIColor {
        switch kind {
        case .shell: return Palette.uiShell
        case .board: return Palette.uiBoard
        case .lifeRing: return Palette.uiRing
        case .goldenShell: return Palette.uiGold
        case .jellyfish: return Palette.uiJelly
        }
    }

    private func poseItem(_ node: SKNode, object: LiveObject) {
        guard let body = node.childNode(withName: "body") else { return }
        switch object.kind {
        case .board:
            body.xScale = object.step % 2 == 0 ? -1 : 1
            body.zRotation = 0.15
        case .shell, .goldenShell:
            body.zRotation = CGFloat(object.step - 1) * .pi / 2
        case .jellyfish:
            body.zRotation = CGFloat(object.step - 1) * .pi / 3
        case .lifeRing:
            body.zRotation = CGFloat(object.step - 1) * 0.4
        }
        if object.kind == .goldenShell {
            node.childNode(withName: "spec")?.alpha = object.step % 2 == 0 ? 1 : 0.25
            node.childNode(withName: "spark")?.zRotation = CGFloat(object.step) * .pi / 3
        }
        if objectSteps[object.id] != object.step {
            objectSteps[object.id] = object.step
            node.removeAction(forKey: "squash")
            let scale = baseScale(object.kind)
            let squish = SKAction.scaleX(to: scale * 1.15, y: scale * 0.85, duration: 0.04)
            let back = SKAction.scale(to: scale, duration: 0.05)
            node.run(.sequence([squish, back]), withKey: "squash")
        }
    }

    private func objectPath(_ kind: ObjectKind) -> CGPath {
        switch kind {
        case .shell, .goldenShell:
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: 26, startAngle: .pi, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: 22, y: -8))
            path.addQuadCurve(to: CGPoint(x: -22, y: -8), control: CGPoint(x: 0, y: -18))
            path.closeSubpath()
            path.move(to: CGPoint(x: 0, y: -6))
            path.addLine(to: CGPoint(x: 0, y: 24))
            path.move(to: CGPoint(x: -12, y: -4))
            path.addLine(to: CGPoint(x: -10, y: 18))
            path.move(to: CGPoint(x: 12, y: -4))
            path.addLine(to: CGPoint(x: 10, y: 18))
            return path
        case .board:
            let path = CGMutablePath()
            let rect = CGRect(x: -12, y: -36, width: 24, height: 72)
            path.addRoundedRect(in: rect, cornerWidth: 12, cornerHeight: 12)
            path.move(to: CGPoint(x: -12, y: 6))
            path.addLine(to: CGPoint(x: 12, y: 6))
            return path
        case .lifeRing:
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: -26, y: -26, width: 52, height: 52))
            path.addEllipse(in: CGRect(x: -12, y: -12, width: 24, height: 24))
            path.move(to: CGPoint(x: -8, y: 22))
            path.addLine(to: CGPoint(x: 8, y: 22))
            path.move(to: CGPoint(x: -8, y: -22))
            path.addLine(to: CGPoint(x: 8, y: -22))
            return path
        case .jellyfish:
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: 0, y: 8), radius: 22, startAngle: .pi, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: 18, y: 4))
            path.addLine(to: CGPoint(x: -18, y: 4))
            path.closeSubpath()
            for index in -1...1 {
                let x = CGFloat(index) * 12
                path.move(to: CGPoint(x: x, y: 2))
                path.addQuadCurve(to: CGPoint(x: x + 8, y: -28), control: CGPoint(x: x - 10, y: -12))
            }
            return path
        }
    }

    private func drawSurfer() {
        surfer.removeAllChildren()
        let hair = SKShapeNode(ellipseOf: CGSize(width: 46, height: 36))
        hair.fillColor = Palette.uiHair
        hair.strokeColor = Palette.uiPlum
        hair.lineWidth = 3
        hair.position = CGPoint(x: 0, y: 58)
        surfer.addChild(hair)

        let head = SKShapeNode(circleOfRadius: 16)
        head.fillColor = Palette.uiSkin
        head.strokeColor = Palette.uiPlum
        head.lineWidth = 3
        head.position = CGPoint(x: 0, y: 48)
        surfer.addChild(head)

        let torso = SKShapeNode(rectOf: CGSize(width: 28, height: 36), cornerRadius: 10)
        torso.fillColor = Palette.uiTeal
        torso.strokeColor = Palette.uiPlum
        torso.lineWidth = 3
        torso.position = CGPoint(x: 0, y: 16)
        surfer.addChild(torso)

        let board = SKShapeNode(rectOf: CGSize(width: 78, height: 16), cornerRadius: 8)
        board.fillColor = Palette.uiHotPink
        board.strokeColor = Palette.uiPlum
        board.lineWidth = 3
        board.position = CGPoint(x: 0, y: -18)
        board.zRotation = -0.08
        board.name = "board"
        surfer.addChild(board)
        let bolt = SKShapeNode(path: lightningPath())
        bolt.strokeColor = Palette.uiGold
        bolt.lineWidth = 2
        bolt.fillColor = .clear
        bolt.position = CGPoint(x: 0, y: -18)
        bolt.zRotation = -0.08
        bolt.name = "bolt"
        surfer.addChild(bolt)

        let arm = SKShapeNode(rectOf: CGSize(width: 10, height: 28), cornerRadius: 5)
        arm.fillColor = Palette.uiSkin
        arm.strokeColor = Palette.uiPlum
        arm.lineWidth = 3
        arm.position = CGPoint(x: 18, y: 28)
        arm.name = "arm"
        surfer.addChild(arm)
        surfer.setScale(surferScale)
        surfer.zPosition = 6
    }

    private func placeSurfer(at offset: CGPoint, now: TimeInterval) {
        let anchor = sk(LaneGeometry.surferAnchor)
        surfer.position = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
        surfer.zRotation = poseRotation(logicalLane)
        if let arm = surfer.childNode(withName: "arm") as? SKShapeNode {
            switch logicalLane {
            case .upperLeft:
                arm.position = CGPoint(x: -20, y: 42)
                arm.zRotation = 0.9
            case .upperRight:
                arm.position = CGPoint(x: 20, y: 42)
                arm.zRotation = -0.9
            case .lowerLeft:
                arm.position = CGPoint(x: -22, y: 8)
                arm.zRotation = 1.4
            case .lowerRight:
                arm.position = CGPoint(x: 22, y: 8)
                arm.zRotation = -1.4
            }
        }
    }

    private func poseTarget(_ lane: Lane) -> CGPoint {
        switch lane {
        case .upperLeft: return CGPoint(x: -74, y: 50)
        case .upperRight: return CGPoint(x: 74, y: 50)
        case .lowerLeft: return CGPoint(x: -86, y: -48)
        case .lowerRight: return CGPoint(x: 86, y: -48)
        }
    }

    private func poseRotation(_ lane: Lane) -> CGFloat {
        switch lane {
        case .upperLeft: return 0.38
        case .upperRight: return -0.38
        case .lowerLeft: return -0.22
        case .lowerRight: return 0.22
        }
    }

    private func lightningPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 8, y: 6))
        path.addLine(to: CGPoint(x: -2, y: 1))
        path.addLine(to: CGPoint(x: 4, y: 0))
        path.addLine(to: CGPoint(x: -8, y: -6))
        return path
    }

    func playCatchSquash() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        surfer.removeAction(forKey: "squash")
        let down = SKAction.scaleX(to: bodyScale * 1.15, y: bodyScale * 0.85, duration: 0.06)
        let back = SKAction.scale(to: bodyScale, duration: 0.12)
        back.timingMode = .easeOut
        surfer.run(.sequence([down, back]), withKey: "squash")
    }

    func playMissWobble() {
        guard let board = surfer.childNode(withName: "board") else { return }
        board.run(.rotate(byAngle: .pi, duration: 0.30))
        surfer.childNode(withName: "bolt")?.run(.rotate(byAngle: .pi, duration: 0.30))
        let crack = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -8, y: -12))
        path.addLine(to: CGPoint(x: 2, y: -18))
        path.addLine(to: CGPoint(x: -4, y: -24))
        crack.path = path
        crack.strokeColor = Palette.uiPlum
        crack.lineWidth = 2
        crack.zPosition = 2
        surfer.addChild(crack)
        crack.run(.sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.15), .removeFromParent()]))
    }

    private func baseScale(_ kind: ObjectKind) -> CGFloat {
        kind == .goldenShell ? itemScale * 1.45 : itemScale
    }

    private func sparklePath() -> CGPath {
        let path = CGMutablePath()
        let points = [
            CGPoint(x: 0, y: 16), CGPoint(x: 3, y: 3),
            CGPoint(x: 16, y: 0), CGPoint(x: 3, y: -3),
            CGPoint(x: 0, y: -16), CGPoint(x: -3, y: -3),
            CGPoint(x: -16, y: 0), CGPoint(x: -3, y: 3),
        ]
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    func splash(at point: CGPoint, golden: Bool, strong: Bool = false) {
        let count = golden ? 24 : (strong ? 18 : 12)
        let ring = SKShapeNode(circleOfRadius: strong ? 18 : 10)
        ring.strokeColor = golden ? Palette.uiGold : Palette.uiCream
        ring.fillColor = .clear
        ring.lineWidth = strong ? 4 : 2
        ring.position = point
        ring.zPosition = 11
        world.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: strong ? 3.2 : 2.2, duration: 0.40), .fadeOut(withDuration: 0.40)]),
            .removeFromParent(),
        ]))
        for index in 0..<count {
            let drop = SKShapeNode(circleOfRadius: golden && index % 3 == 0 ? 6 : (strong ? 5 : 3))
            if golden {
                drop.fillColor = index % 3 == 0 ? Palette.uiCream : Palette.uiGold
            } else {
                drop.fillColor = index % 2 == 0 ? Palette.uiCream : Palette.uiTeal
            }
            drop.strokeColor = .clear
            drop.position = point
            drop.zPosition = 11
            world.addChild(drop)
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2
            let dist = CGFloat((strong ? 46 : 28) + (index % 5) * (strong ? 12 : 8))
            drop.run(.sequence([
                .group([
                    .moveBy(x: cos(angle) * dist, y: sin(angle) * dist, duration: strong ? 0.50 : 0.30),
                    .fadeOut(withDuration: strong ? 0.50 : 0.30),
                    .scale(to: 0.2, duration: strong ? 0.50 : 0.30),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    func popScore(_ points: Int, combo: Int, lane: Lane) {
        let label = SKLabelNode(fontNamed: "Bungee-Regular")
        label.text = "+\(points)"
        label.fontSize = 28
        label.fontColor = scoreColor(combo)
        label.verticalAlignmentMode = .center
        label.position = popupPoint(lane)
        label.zPosition = 12
        let tier = CGFloat(ScoreMath.tierIndex(for: combo))
        let scale = min(1.5, 1.0 + 0.1 * tier)
        label.setScale(scale)
        world.addChild(label)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 40, duration: 0.45),
                .fadeOut(withDuration: 0.45),
            ]),
            .removeFromParent(),
        ]))
    }

    private func scoreColor(_ combo: Int) -> UIColor {
        switch ScoreMath.tierIndex(for: combo) {
        case 1: return Palette.uiCream
        case 2: return Palette.uiTeal
        case 3: return Palette.uiHotPink
        case 4: return Palette.uiGold
        default: return Palette.uiCream
        }
    }

    private func currentPose(now: TimeInterval) -> CGPoint {
        let t = min(1, max(0, (now - poseStart) / Feel.poseTween))
        let eased = 1 - (1 - t) * (1 - t)
        return CGPoint(
            x: poseFrom.x + (poseTo.x - poseFrom.x) * eased,
            y: poseFrom.y + (poseTo.y - poseFrom.y) * eased
        )
    }

    private func sk(_ point: LaneGeometry.Point) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }

    func float(text: String, lane: Lane, color: UIColor) {
        let label = SKLabelNode(fontNamed: "Bungee-Regular")
        label.text = text
        label.fontSize = text == "CLOSE!" ? 22 : 20
        label.fontColor = color
        label.verticalAlignmentMode = .bottom
        label.horizontalAlignmentMode = .center
        label.position = popupPoint(lane)
        label.zPosition = 12
        world.addChild(label)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 32, duration: 0.40),
                .fadeOut(withDuration: 0.40),
            ]),
            .removeFromParent(),
        ]))
    }

    /// Above the hair, shifted toward the lane that was just resolved.
    private func popupPoint(_ lane: Lane) -> CGPoint {
        let anchor = sk(LaneGeometry.surferAnchor)
        let pose = poseTarget(lane)
        let side: CGFloat = lane.isRight ? 1 : -1
        return CGPoint(
            x: anchor.x + pose.x + side * 26,
            y: anchor.y + pose.y + 100
        )
    }

    func beginShake(amplitude: CGFloat, duration: Double, now: TimeInterval, reduce: Bool) {
        guard !reduce else { return }
        if shaking && now < shakeStart + shakeDuration { return }
        shaking = true
        shakeStart = now
        shakeDuration = min(Feel.shakeMaxDuration, duration)
        shakeAmplitude = min(CGFloat(Feel.shakeMaxPoints), amplitude)
    }

    private func shakeOffset(now: TimeInterval) -> CGPoint {
        guard shaking else { return .zero }
        let elapsed = now - shakeStart
        if elapsed >= shakeDuration {
            shaking = false
            return .zero
        }
        let decay = 1 - CGFloat(elapsed / shakeDuration)
        let amp = shakeAmplitude * decay
        return CGPoint(x: sin(elapsed * 48) * amp, y: cos(elapsed * 41) * amp)
    }

    private func flashSurfer() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        surfer.run(.sequence([
            .repeat(.sequence([
                .colorize(with: Palette.uiJelly, colorBlendFactor: 0.7, duration: 0.05),
                .colorize(withColorBlendFactor: 0, duration: 0.05),
            ]), count: 3),
        ]))
    }

    private func rebuildPool() {
        chuteGroups.removeAll()
        glints.removeAll()
        foamLine = nil
        for child in world.children where child !== surfer {
            child.removeFromParent()
        }
        objectNodes.removeAll()
        objectSteps.removeAll()
        ringNodes.removeAll()
        waveNodes.removeAll()
        backdrop = nil
        backdropSize = size
        poolArt.install(in: world, size: size)
        if surfer.parent == nil { world.addChild(surfer) }
        surfer.zPosition = 6
    }

    private func layoutPool(now: TimeInterval) {
        world.position = shakeOffset(now: now)
        let session = model?.mode == .menu ? nil : model?.pool
        if let session, session.facing != lastFacing {
            lastFacing = session.facing
            if !UIAccessibility.isReduceMotionEnabled {
                surfer.removeAction(forKey: "turn")
                let down = SKAction.scaleX(to: bodyScale * 1.12, y: bodyScale * 0.88, duration: 0.03)
                let back = SKAction.scale(to: bodyScale, duration: 0.03)
                surfer.run(.sequence([down, back]), withKey: "turn")
            }
        }
        if session == nil { lastFacing = .south }
        poolArt.pressedSide = model?.pressedSide
        poolArt.update(session: session, surfer: surfer, size: size, now: now, bodyScale: &bodyScale)
        let serial = session?.spinSerial ?? 0
        if serial != poolArt.seenSpin {
            poolArt.seenSpin = serial
            if serial > 0, !UIAccessibility.isReduceMotionEnabled {
                surfer.zRotation = poolArt.rotation(for: session?.facing ?? .south)
                surfer.run(.rotate(byAngle: .pi * 2, duration: 0.55), withKey: "spin")
            }
        }
    }

    func presentPool(_ events: [PoolEvent], session: WavePoolSession) {
        let reduce = UIAccessibility.isReduceMotionEnabled
        for event in events {
            switch event {
            case .caught(_, let side, let kind, let points, let combo, let close):
                let spot = poolArt.point(side: side, step: 5)
                popScore(points, at: CGPoint(x: spot.x, y: spot.y + 70), combo: combo)
                if close { float(text: "CLOSE!", at: spot, color: Palette.uiSun) }
                splash(at: spot, golden: kind == .goldenWave, strong: true)
                playCatchSquash()
            case .missed(_, let side, _, let lifeLost):
                let spot = poolArt.point(side: side, step: 5)
                float(text: lifeLost ? "WIPEOUT" : "SAFE", at: spot, color: Palette.uiHotPink)
                if lifeLost {
                    splash(at: spot, golden: false, strong: true)
                    playMissWobble()
                    beginShake(amplitude: 14, duration: 0.40, now: lastTime ?? 0, reduce: reduce)
                }
            case .wiped(_, let side, _, let lifeLost):
                let spot = poolArt.point(side: side, step: 5)
                float(text: "WIPEOUT", at: spot, color: Palette.uiJelly)
                splash(at: spot, golden: false, strong: true)
                if lifeLost {
                    playMissWobble()
                    beginShake(amplitude: 16, duration: 0.45, now: lastTime ?? 0, reduce: reduce)
                }
            case .dodged(_, let side):
                float(text: "DODGE!", at: poolArt.point(side: side, step: 5), color: Palette.uiSea)
            case .surgeEnd:
                splash(at: CGPoint(x: size.width / 2, y: size.height * 0.5), golden: false)
            default:
                break
            }
        }
    }

    func popScore(_ points: Int, at point: CGPoint, combo: Int) {
        let shadow = SKLabelNode(fontNamed: "Bungee-Regular")
        shadow.text = "+\(points)"
        shadow.fontSize = 48
        shadow.fontColor = Palette.uiPlum
        shadow.verticalAlignmentMode = .center
        shadow.position = CGPoint(x: point.x + 3, y: point.y - 3)
        shadow.zPosition = 19
        let label = SKLabelNode(fontNamed: "Bungee-Regular")
        label.text = "+\(points)"
        label.fontSize = 48
        label.fontColor = scoreColor(combo)
        label.verticalAlignmentMode = .center
        label.position = point
        label.zPosition = 20
        let tier = CGFloat(ScoreMath.tierIndex(for: combo))
        let scale = min(1.4, 1.0 + 0.08 * tier)
        label.setScale(scale)
        shadow.setScale(scale)
        world.addChild(shadow)
        world.addChild(label)
        func rise() -> SKAction {
            .sequence([
                .group([.moveBy(x: 0, y: 64, duration: 0.70), .fadeOut(withDuration: 0.70)]),
                .removeFromParent(),
            ])
        }
        label.run(rise())
        shadow.run(rise())
    }

    func float(text: String, at point: CGPoint, color: UIColor) {
        let label = SKLabelNode(fontNamed: "Bungee-Regular")
        label.text = text
        label.fontSize = text == "WIPEOUT" ? 32 : (text == "CLOSE!" ? 22 : 20)
        label.fontColor = color
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: point.x, y: point.y + 36)
        label.zPosition = 12
        world.addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 32, duration: 0.40), .fadeOut(withDuration: 0.40)]),
            .removeFromParent(),
        ]))
    }
}
