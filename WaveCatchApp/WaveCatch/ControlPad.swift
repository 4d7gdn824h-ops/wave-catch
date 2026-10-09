import SwiftUI
import UIKit
import WaveCatchCore

struct ControlPad: View {
    var enabled: Bool
    var showTiles: Bool
    var swipeEnabled: Bool
    var pressed: Lane?
    var verticalSplit: CGFloat = 0.5
    var onLane: (Lane) -> Void

    var body: some View {
        ZStack {
            if showTiles {
                tileGrid
            }
            TouchCatcher(
                enabled: enabled,
                swipeEnabled: swipeEnabled,
                verticalSplit: verticalSplit,
                onLane: onLane
            )
        }
    }

    private var tileGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tile(.upperLeft)
                tile(.upperRight)
            }
            HStack(spacing: 0) {
                tile(.lowerLeft)
                tile(.lowerRight)
            }
        }
    }

    private func tile(_ lane: Lane) -> some View {
        ZStack {
            Palette.sand
            StripeFill()
                .opacity(0.35)
            ArrowMark(lane: lane)
                .stroke(Palette.ink, lineWidth: 3)
                .frame(width: 28, height: 28)
            if pressed == lane {
                Palette.foam.opacity(0.45)
            }
        }
        .overlay(Rectangle().stroke(Palette.ink.opacity(0.35), lineWidth: 1))
    }
}

private struct StripeFill: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                var x: CGFloat = -geo.size.height
                while x < geo.size.width {
                    path.move(to: CGPoint(x: x, y: geo.size.height))
                    path.addLine(to: CGPoint(x: x + geo.size.height, y: 0))
                    x += 18
                }
            }
            .stroke(Palette.hotPink.opacity(0.45), lineWidth: 4)
        }
    }
}

private struct ArrowMark: Shape {
    var lane: Lane

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx: CGFloat = lane.isRight ? 1 : -1
        let dy: CGFloat = lane.isUpper ? -1 : 1
        var path = Path()
        path.move(to: CGPoint(x: center.x - dx * 10, y: center.y - dy * 10))
        path.addLine(to: CGPoint(x: center.x + dx * 8, y: center.y + dy * 8))
        path.move(to: CGPoint(x: center.x + dx * 8, y: center.y + dy * 8))
        path.addLine(to: CGPoint(x: center.x + dx * 8 - dx * 10, y: center.y + dy * 8))
        path.move(to: CGPoint(x: center.x + dx * 8, y: center.y + dy * 8))
        path.addLine(to: CGPoint(x: center.x + dx * 8, y: center.y + dy * 8 - dy * 10))
        return path
    }
}

struct TouchCatcher: UIViewRepresentable {
    var enabled: Bool
    var swipeEnabled: Bool
    var verticalSplit: CGFloat
    var onLane: (Lane) -> Void

    func makeUIView(context: Context) -> PadView {
        let view = PadView()
        view.onLane = onLane
        return view
    }

    func updateUIView(_ uiView: PadView, context: Context) {
        uiView.onLane = onLane
        uiView.isUserInteractionEnabled = enabled
        uiView.swipeEnabled = swipeEnabled
        uiView.verticalSplit = verticalSplit
        uiView.setNeedsLayout()
    }
}

final class PadView: UIView {
    var onLane: ((Lane) -> Void)?
    var swipeEnabled = false
    var verticalSplit: CGFloat = 0.5
    private var lastStamp = -1.0
    private var touchStart: [ObjectIdentifier: CGPoint] = [:]
    private let zones: [Lane: ZoneView]

    override init(frame: CGRect) {
        var built: [Lane: ZoneView] = [:]
        for lane in Lane.allCases {
            let zone = ZoneView(lane: lane)
            zone.accessibilityIdentifier = "zone.\(lane.rawValue)"
            zone.accessibilityLabel = lane.rawValue
            zone.isAccessibilityElement = true
            built[lane] = zone
        }
        zones = built
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        for zone in zones.values {
            zone.isUserInteractionEnabled = true
            zone.backgroundColor = .clear
            addSubview(zone)
            zone.onTouch = { [weak self] lane, stamp in
                self?.accept(lane, stamp: stamp)
            }
            zone.onBegan = { [weak self] touch in
                self?.touchStart[ObjectIdentifier(touch)] = touch.location(in: self)
            }
            zone.onEnded = { [weak self] touch in
                guard let self, self.swipeEnabled else { return }
                let end = touch.location(in: self)
                let start = self.touchStart[ObjectIdentifier(touch)] ?? end
                self.touchStart[ObjectIdentifier(touch)] = nil
                self.resolveSwipe(from: start, to: end, stamp: touch.timestamp)
            }
        }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let midX = bounds.midX
        let midY = bounds.height * min(0.9, max(0.1, verticalSplit))
        zones[.upperLeft]?.frame = CGRect(x: 0, y: 0, width: midX, height: midY)
        zones[.upperRight]?.frame = CGRect(x: midX, y: 0, width: bounds.width - midX, height: midY)
        zones[.lowerLeft]?.frame = CGRect(x: 0, y: midY, width: midX, height: bounds.height - midY)
        zones[.lowerRight]?.frame = CGRect(x: midX, y: midY, width: bounds.width - midX, height: bounds.height - midY)
    }

    private func accept(_ lane: Lane, stamp: TimeInterval) {
        guard stamp + 0.00001 >= lastStamp else { return }
        lastStamp = stamp
        onLane?(lane)
    }

    private func resolveSwipe(from start: CGPoint, to end: CGPoint, stamp: TimeInterval) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard hypot(dx, dy) >= 30 else { return }
        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let sector = Int((degrees + 22.5) / 45) % 8
        let lane: Lane?
        switch sector {
        case 1: lane = .lowerRight
        case 3: lane = .lowerLeft
        case 5: lane = .upperLeft
        case 7: lane = .upperRight
        default: lane = nil
        }
        if let lane {
            accept(lane, stamp: stamp)
        }
    }
}

final class ZoneView: UIView {
    let lane: Lane
    var onTouch: ((Lane, TimeInterval) -> Void)?
    var onBegan: ((UITouch) -> Void)?
    var onEnded: ((UITouch) -> Void)?

    init(lane: Lane) {
        self.lane = lane
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.max(by: { $0.timestamp < $1.timestamp }) else { return }
        onBegan?(touch)
        onTouch?(lane, touch.timestamp)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.max(by: { $0.timestamp < $1.timestamp }) else { return }
        onEnded?(touch)
    }
}
