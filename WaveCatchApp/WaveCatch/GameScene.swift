import SpriteKit
import UIKit
import WaveCatchCore

final class GameScene: SKScene {
    weak var model: GameModel?
    private let world = SKNode()
    private var backdrop: SKSpriteNode?
    private var backdropSize = CGSize.zero
    private let surfer = SKNode()
    private var objectNodes: [Int: SKShapeNode] = [:]
    private var ringNodes: [Lane: SKNode] = [:]
    private var ringKind: [Lane: ObjectKind] = [:]
    private var ringUntil: [Lane: TimeInterval] = [:]
    private let itemScale: CGFloat = 1.3
    private var banner: SKLabelNode?
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
        ringNodes.values.forEach { $0.removeFromParent() }
        ringNodes.removeAll()
        banner?.removeFromParent()
        banner = nil
        logicalLane = session.position
        poseFrom = poseTarget(session.position)
        poseTo = poseFrom
        lastTime = nil
        ringKind.removeAll()
        ringUntil.removeAll()
    }

    override func update(_ currentTime: TimeInterval) {
        let dt: Double
        if let lastTime {
            dt = min(0.05, max(0, currentTime - lastTime))
        } else {
            dt = 0
        }
        lastTime = currentTime
        if dt > 0 {
            model?.advance(dt: dt)
        }
        layout(now: currentTime)
    }

    func present(_ events: [GameEvent], session: GameSession) {
        let reduce = UIAccessibility.isReduceMotionEnabled
        let wave = session.bigWavePhase == .active || session.bigWavePhase == .warning
        for event in events {
            switch event {
            case .caught(_, let lane, _, let points, _, let close):
                float(text: close ? "CLOSE!" : "+\(points)", lane: lane, color: close ? Palette.uiSun : Palette.uiFoam)
            case .dodged(_, let lane):
                float(text: "DODGE!", lane: lane, color: Palette.uiSea)
            case .missed(_, let lane, _, let lifeLost):
                float(text: lifeLost ? "MISS" : "SAFE", lane: lane, color: Palette.uiHotPink)
                if lifeLost && !wave {
                    beginShake(amplitude: 6, duration: 0.18, now: lastTime ?? 0, reduce: reduce)
                }
            case .stung(_, let lane, _):
                float(text: "STING", lane: lane, color: Palette.uiJelly)
                if !wave {
                    beginShake(amplitude: 8, duration: 0.22, now: lastTime ?? 0, reduce: reduce)
                }
                flashSurfer()
            case .gameOver:
                if !wave {
                    beginShake(amplitude: 10, duration: 0.30, now: lastTime ?? 0, reduce: reduce)
                }
            default:
                break
            }
        }
    }

    private func layout(now: TimeInterval) {
        if backdrop == nil || abs(backdropSize.width - size.width) > 2 || abs(backdropSize.height - size.height) > 2 {
            rebuildBackdrop()
        }
        world.position = shakeOffset(now: now)
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
        syncObjects(session)
        syncRings(session, now: now)
        syncBanner(session)
    }

    private func rebuildBackdrop() {
        for child in world.children where child !== surfer {
            child.removeFromParent()
        }
        objectNodes.removeAll()
        ringNodes.removeAll()
        banner = nil
        let image = skyImage(size: size)
        let sprite = SKSpriteNode(texture: SKTexture(image: image), size: size)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite.zPosition = 0
        world.addChild(sprite)
        backdrop = sprite
        backdropSize = size
        addSun()
        addWave()
        addShore()
    }

    private func skyImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let colors = [Palette.uiIndigo, Palette.uiViolet, Palette.uiHotPink, Palette.uiTangerine].map(\.cgColor) as CFArray
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
        let center = sk(LaneGeometry.Point(x: 0.70, y: 0.18))
        let sun = SKShapeNode(circleOfRadius: 42)
        sun.fillColor = Palette.uiSun
        sun.strokeColor = Palette.uiInk
        sun.lineWidth = 4
        sun.position = center
        sun.zPosition = 1
        world.addChild(sun)
        for index in 0..<3 {
            let band = SKShapeNode(rectOf: CGSize(width: 88, height: 6), cornerRadius: 2)
            band.fillColor = Palette.uiTangerine.withAlphaComponent(0.85)
            band.strokeColor = .clear
            band.position = CGPoint(x: center.x, y: center.y + 24 - CGFloat(index) * 22)
            band.zPosition = 1.1
            world.addChild(band)
        }
    }

    private func addWave() {
        let face = CGMutablePath()
        face.move(to: sk(LaneGeometry.Point(x: -0.12, y: 0.50)))
        face.addQuadCurve(to: sk(LaneGeometry.point(lane: .upperLeft, progress: 0)), control: sk(LaneGeometry.Point(x: 0.08, y: 0.44)))
        face.addQuadCurve(to: sk(LaneGeometry.Point(x: 0.74, y: 0.16)), control: sk(LaneGeometry.Point(x: 0.56, y: 0.18)))
        face.addQuadCurve(to: sk(LaneGeometry.Point(x: 1.14, y: 0.36)), control: sk(LaneGeometry.Point(x: 1.02, y: 0.06)))
        face.addLine(to: sk(LaneGeometry.Point(x: 1.14, y: 0.78)))
        face.addQuadCurve(to: sk(LaneGeometry.Point(x: -0.12, y: 0.74)), control: sk(LaneGeometry.Point(x: 0.50, y: 0.62)))
        face.closeSubpath()
        let wave = SKShapeNode(path: face)
        wave.fillColor = Palette.uiSea
        wave.strokeColor = .clear
        wave.lineWidth = 0
        wave.zPosition = 2
        world.addChild(wave)

        let lip = CGMutablePath()
        lip.move(to: sk(LaneGeometry.Point(x: -0.12, y: 0.50)))
        lip.addQuadCurve(to: sk(LaneGeometry.point(lane: .upperLeft, progress: 0)), control: sk(LaneGeometry.Point(x: 0.08, y: 0.44)))
        lip.addQuadCurve(to: sk(LaneGeometry.Point(x: 0.74, y: 0.16)), control: sk(LaneGeometry.Point(x: 0.56, y: 0.18)))
        lip.addQuadCurve(to: sk(LaneGeometry.Point(x: 1.08, y: 0.32)), control: sk(LaneGeometry.Point(x: 0.98, y: 0.05)))
        let lipNode = SKShapeNode(path: lip)
        lipNode.strokeColor = Palette.uiFoamLip
        lipNode.fillColor = .clear
        lipNode.lineWidth = 11
        lipNode.lineCap = .round
        lipNode.zPosition = 2.3
        world.addChild(lipNode)

        let curl = CGMutablePath()
        curl.move(to: sk(LaneGeometry.Point(x: 0.70, y: 0.17)))
        curl.addQuadCurve(to: sk(LaneGeometry.Point(x: 1.10, y: 0.30)), control: sk(LaneGeometry.Point(x: 0.96, y: 0.02)))
        let curlNode = SKShapeNode(path: curl)
        curlNode.strokeColor = Palette.uiFoamLip
        curlNode.lineWidth = 18
        curlNode.lineCap = .round
        curlNode.zPosition = 2.35
        world.addChild(curlNode)

        let foam = [
            LaneGeometry.Point(x: 0.08, y: 0.45),
            LaneGeometry.Point(x: 0.24, y: 0.34),
            LaneGeometry.Point(x: 0.40, y: 0.24),
            LaneGeometry.Point(x: 0.56, y: 0.19),
            LaneGeometry.Point(x: 0.70, y: 0.15),
            LaneGeometry.Point(x: 0.82, y: 0.13),
            LaneGeometry.Point(x: 0.92, y: 0.16),
            LaneGeometry.Point(x: 1.00, y: 0.24),
        ]
        for (index, spot) in foam.enumerated() {
            let radius: CGFloat = index >= 5 ? 8 : 5
            let dot = SKShapeNode(circleOfRadius: radius)
            dot.fillColor = Palette.uiFoamLip
            dot.strokeColor = .clear
            dot.position = sk(spot)
            dot.zPosition = 2.4
            world.addChild(dot)
            if index >= 4 {
                let scallop = SKShapeNode(circleOfRadius: radius + 3)
                scallop.fillColor = Palette.uiFoamLip.withAlphaComponent(0.85)
                scallop.strokeColor = .clear
                let dropped = LaneGeometry.Point(x: spot.x - 0.015, y: spot.y + 0.035)
                scallop.position = sk(dropped)
                scallop.zPosition = 2.25
                world.addChild(scallop)
            }
        }
    }

    private func addShore() {
        let shoreHeight = size.height * 0.62
        let shore = SKShapeNode(rectOf: CGSize(width: size.width + 80, height: shoreHeight))
        shore.fillColor = Palette.uiDeepSea
        shore.strokeColor = .clear
        shore.lineWidth = 0
        shore.position = CGPoint(x: size.width / 2, y: shoreHeight / 2 - size.height * 0.08)
        shore.zPosition = 1.5
        world.addChild(shore)
    }

    private func syncObjects(_ session: GameSession) {
        var alive = Set<Int>()
        for object in session.liveObjects {
            alive.insert(object.id)
            let node = objectNodes[object.id] ?? makeObject(object.kind)
            if objectNodes[object.id] == nil {
                objectNodes[object.id] = node
                world.addChild(node)
            }
            let spot = LaneGeometry.point(lane: object.lane, progress: object.progress)
            var point = sk(spot)
            if object.wobbling {
                point.x += sin(CGFloat(session.time) * 46) * 7
            }
            node.position = point
            node.zPosition = 5
            node.setScale(itemScale * (object.wobbling ? 1.08 : 1))
        }
        for (id, node) in objectNodes where !alive.contains(id) {
            node.run(.sequence([
                .group([.scale(to: itemScale * 1.15, duration: 0.08), .fadeOut(withDuration: 0.14)]),
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
        outline.strokeColor = Palette.uiInk
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

    private func syncBanner(_ session: GameSession) {
        let show = session.bigWavePhase == .warning || session.bigWavePhase == .active
        if show {
            let label = banner ?? SKLabelNode(fontNamed: "Avenir-Black")
            if banner == nil {
                label.fontSize = 36
                label.fontColor = Palette.uiSun
                label.zPosition = 9
                world.addChild(label)
                banner = label
            }
            label.text = session.bigWavePhase == .warning ? "BIG WAVE!" : "RIDE IT"
            label.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        } else {
            banner?.removeFromParent()
            banner = nil
        }
    }

    private func makeObject(_ kind: ObjectKind) -> SKShapeNode {
        let node = SKShapeNode(path: objectPath(kind))
        node.lineWidth = 4
        node.strokeColor = Palette.uiInk
        node.lineJoin = .round
        switch kind {
        case .shell:
            node.fillColor = Palette.uiShell
        case .board:
            node.fillColor = Palette.uiBoard
        case .lifeRing:
            node.fillColor = Palette.uiRing
        case .jellyfish:
            node.fillColor = Palette.uiJelly
        }
        return node
    }

    private func objectPath(_ kind: ObjectKind) -> CGPath {
        switch kind {
        case .shell:
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
        hair.strokeColor = Palette.uiInk
        hair.lineWidth = 4
        hair.position = CGPoint(x: 0, y: 58)
        surfer.addChild(hair)

        let head = SKShapeNode(circleOfRadius: 16)
        head.fillColor = Palette.uiSkin
        head.strokeColor = Palette.uiInk
        head.lineWidth = 4
        head.position = CGPoint(x: 0, y: 48)
        surfer.addChild(head)

        let torso = SKShapeNode(rectOf: CGSize(width: 28, height: 36), cornerRadius: 10)
        torso.fillColor = Palette.uiHotPink
        torso.strokeColor = Palette.uiInk
        torso.lineWidth = 4
        torso.position = CGPoint(x: 0, y: 16)
        surfer.addChild(torso)

        let board = SKShapeNode(rectOf: CGSize(width: 78, height: 16), cornerRadius: 8)
        board.fillColor = Palette.uiBoard
        board.strokeColor = Palette.uiInk
        board.lineWidth = 4
        board.position = CGPoint(x: 0, y: -18)
        board.zRotation = -0.08
        surfer.addChild(board)

        let arm = SKShapeNode(rectOf: CGSize(width: 10, height: 28), cornerRadius: 5)
        arm.fillColor = Palette.uiSkin
        arm.strokeColor = Palette.uiInk
        arm.lineWidth = 3
        arm.position = CGPoint(x: 18, y: 28)
        arm.name = "arm"
        surfer.addChild(arm)
        surfer.zPosition = 6
    }

    private func placeSurfer(at offset: CGPoint, now: TimeInterval) {
        let anchor = sk(LaneGeometry.surferAnchor)
        surfer.position = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
        if let arm = surfer.childNode(withName: "arm") as? SKShapeNode {
            let raised = logicalLane.isUpper
            arm.position = CGPoint(x: logicalLane.isRight ? 18 : -18, y: raised ? 36 : 22)
            arm.zRotation = logicalLane.isRight ? -0.6 : 0.6
        }
    }

    private func poseTarget(_ lane: Lane) -> CGPoint {
        switch lane {
        case .upperLeft: return CGPoint(x: -36, y: 18)
        case .upperRight: return CGPoint(x: 36, y: 18)
        case .lowerLeft: return CGPoint(x: -42, y: -12)
        case .lowerRight: return CGPoint(x: 42, y: -12)
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

    private func float(text: String, lane: Lane, color: UIColor) {
        let label = SKLabelNode(fontNamed: "Avenir-Black")
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

    private func beginShake(amplitude: CGFloat, duration: Double, now: TimeInterval, reduce: Bool) {
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
}
