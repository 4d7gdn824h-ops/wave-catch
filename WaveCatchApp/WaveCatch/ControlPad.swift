import SwiftUI
import UIKit
import WaveCatchCore

enum CornerMetrics {
    static let side: CGFloat = 104
    static let margin: CGFloat = 8

    static func frame(for lane: Lane, size: CGSize, insets: UIEdgeInsets, side: CGFloat = CornerMetrics.side) -> CGRect {
        let length = max(88, side)
        switch lane {
        case .upperLeft:
            return CGRect(x: insets.left + margin, y: insets.top + margin, width: length, height: length)
        case .upperRight:
            return CGRect(
                x: size.width - insets.right - margin - length,
                y: insets.top + margin,
                width: length,
                height: length
            )
        case .lowerLeft:
            return CGRect(
                x: insets.left + margin,
                y: size.height - insets.bottom - margin - length,
                width: length,
                height: length
            )
        case .lowerRight:
            return CGRect(
                x: size.width - insets.right - margin - length,
                y: size.height - insets.bottom - margin - length,
                width: length,
                height: length
            )
        }
    }
}

struct CornerControls: View {
    var enabled: Bool
    var swipeEnabled: Bool
    var pressed: Lane?
    var large: Bool
    var insets: UIEdgeInsets
    var onLane: (Lane) -> Void

    private var side: CGFloat { large ? 128 : CornerMetrics.side }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                TouchCatcher(
                    enabled: enabled,
                    swipeEnabled: swipeEnabled,
                    insets: insets,
                    side: side,
                    onLane: onLane
                )
                ForEach(Lane.allCases, id: \.self) { lane in
                    let frame = CornerMetrics.frame(for: lane, size: size, insets: insets, side: side)
                    cornerFace(lane)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("corner.\(lane.rawValue)")
                        .accessibilityLabel(lane.rawValue)
                }
            }
        }
    }

    private func cornerFace(_ lane: Lane) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.sand.opacity(0.5))
            StripeFill()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .opacity(0.18)
            if pressed == lane {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Palette.foam.opacity(0.55))
            }
            ArrowMark(lane: lane)
                .stroke(Palette.ink, lineWidth: 3)
                .frame(width: 28, height: 28)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Palette.violet.opacity(0.55), lineWidth: 2)
        )
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
    var insets: UIEdgeInsets
    var side: CGFloat
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
        uiView.cornerInsets = insets
        uiView.buttonSide = side
        uiView.setNeedsLayout()
    }
}

final class PadView: UIView {
    var onLane: ((Lane) -> Void)?
    var swipeEnabled = false
    var cornerInsets = UIEdgeInsets.zero
    var buttonSide = CornerMetrics.side
    private var lastStamp = -1.0
    private var touchStart: [ObjectIdentifier: CGPoint] = [:]
    private let zones: [Lane: ZoneView]

    override init(frame: CGRect) {
        var built: [Lane: ZoneView] = [:]
        for lane in Lane.allCases {
            let zone = ZoneView(lane: lane)
            zone.accessibilityIdentifier = "corner.\(lane.rawValue)"
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
        let insets = UIEdgeInsets(
            top: max(cornerInsets.top, safeAreaInsets.top),
            left: max(cornerInsets.left, safeAreaInsets.left),
            bottom: max(cornerInsets.bottom, safeAreaInsets.bottom),
            right: max(cornerInsets.right, safeAreaInsets.right)
        )
        for lane in Lane.allCases {
            zones[lane]?.frame = CornerMetrics.frame(for: lane, size: bounds.size, insets: insets, side: buttonSide)
        }
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
