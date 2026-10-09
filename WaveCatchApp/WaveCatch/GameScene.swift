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
    private var ringNodes: [Lane: SKShapeNode] = [:]
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
        super.init(size: CGSize(width: 390, height: 844))
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
        syncRings(session)
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
        let center = sk(LaneGeometry.Point(x: 0.72, y: 0.30))
        let sun = SKShapeNode(circleOfRadius: 58)
        sun.fillColor = Palette.uiSun
        sun.strokeColor = Palette.uiInk
        sun.lineWidth = 4
        sun.position = center
        sun.zPosition = 1
        world.addChild(sun)
        for index in 0..<3 {
            let band = SKShapeNode(rectOf: CGSize(width: 120, height: 8), cornerRadius: 2)
            band.fillColor = Palette.uiTangerine.withAlphaComponent(0.85)
            band.strokeColor = .clear
            band.position = CGPoint(x: center.x, y: center.y + 24 - CGFloat(index) * 22)
            band.zPosition = 1.1
            world.addChild(band)
        }
    }

    private func addWave() {
        let path = CGMutablePath()
        let left = sk(LaneGeometry.Point(x: 0, y: 0.20))
        let lip = sk(LaneGeometry.Point(x: 0.55, y: 0.12))
        let right = sk(LaneGeometry.Point(x: 1, y: 0.24))
        let foot = sk(LaneGeometry.Point(x: 1, y: 0.40))
        let footLeft = sk(LaneGeometry.Point(x: 0, y: 0.36))
        path.move(to: left)
        path.addQuadCurve(to: right, control: lip)
        path.addLine(to: foot)
        path.addLine(to: footLeft)
        path.closeSubpath()
        let wave = SKShapeNode(path: path)
        wave.fillColor = Palette.uiSea
        wave.strokeColor = Palette.uiFoam
        wave.lineWidth = 5
        wave.zPosition = 2
        world.addChild(wave)

        let curl = CGMutablePath()
        let curlStart = sk(LaneGeometry.Point(x: 0.42, y: 0.16))
        let curlEnd = sk(LaneGeometry.Point(x: 0.78, y: 0.18))
        let curlControl = sk(LaneGeometry.Point(x: 0.62, y: 0.08))
        curl.move(to: curlStart)
        curl.addQuadCurve(to: curlEnd, control: curlControl)
        let lipNode = SKShapeNode(path: curl)
        lipNode.strokeColor = Palette.uiFoam
        lipNode.lineWidth = 8
        lipNode.lineCap = .round
        lipNode.zPosition = 2.2
        world.addChild(lipNode)
    }

    private func addShore() {
        let shore = SKShapeNode(rectOf: CGSize(width: size.width + 4, height: size.height * 0.5))
        shore.fillColor = Palette.uiDeepSea
        shore.strokeColor = .clear
        shore.position = CGPoint(x: size.width / 2, y: size.height * 0.22)
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
            node.setScale(object.wobbling ? 1.08 : 1)
        }
        for (id, node) in objectNodes where !alive.contains(id) {
            node.run(.sequence([
                .group([.scale(to: 1.3, duration: 0.08), .fadeOut(withDuration: 0.14)]),
                .removeFromParent(),
            ]))
            objectNodes[id] = nil
        }
    }

    private func syncRings(_ session: GameSession) {
        var shown: [Lane: ObjectKind] = [:]
        for object in session.liveObjects where object.telegraph {
            if shown[object.lane] == nil || object.kind == .jellyfish {
                shown[object.lane] = object.kind
            }
        }
        for lane in Lane.allCases {
            guard let kind = shown[lane] else {
                ringNodes[lane]?.removeFromParent()
                ringNodes[lane] = nil
                continue
            }
            let node = ringNodes[lane] ?? SKShapeNode()
            if ringNodes[lane] == nil {
                ringNodes[lane] = node
                world.addChild(node)
            }
            let spot = sk(LaneGeometry.catchSpot(lane))
            node.position = spot
            node.zPosition = 4
            node.path = ringPath(kind: kind)
            if kind == .jellyfish {
                node.strokeColor = Palette.uiJelly
                node.fillColor = Palette.uiJelly.withAlphaComponent(0.15)
                node.lineWidth = 4
            } else {
                node.strokeColor = Palette.uiFoam
                node.fillColor = Palette.uiFoam.withAlphaComponent(0.12)
                node.lineWidth = 4
            }
        }
    }

    private func ringPath(kind: ObjectKind) -> CGPath {
        if kind == .jellyfish {
            let path = CGMutablePath()
            let spikes = 10
            let outer: CGFloat = 34
            let inner: CGFloat = 22
            for index in 0..<(spikes * 2) {
                let radius = index % 2 == 0 ? outer : inner
                let angle = CGFloat(index) * .pi / CGFloat(spikes) - .pi / 2
                let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
        return CGPath(ellipseIn: CGRect(x: -30, y: -30, width: 60, height: 60), transform: nil)
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
        label.position = sk(LaneGeometry.catchSpot(lane))
        label.zPosition = 8
        world.addChild(label)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 24, duration: 0.45),
                .fadeOut(withDuration: 0.45),
            ]),
            .removeFromParent(),
        ]))
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
