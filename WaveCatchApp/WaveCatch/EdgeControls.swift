import SwiftUI
import UIKit
import WaveCatchCore

enum EdgeMetrics {
    static let side: CGFloat = 96

    /// North sits under the score pill. The other three sit on the middle or the near edge.
    static func frame(for side: Side, size: CGSize, insets: UIEdgeInsets) -> CGRect {
        let length = EdgeMetrics.side
        switch side {
        case .north:
            return CGRect(
                x: (size.width - length) / 2,
                y: insets.top + 96,
                width: length,
                height: length
            )
        case .south:
            return CGRect(
                x: (size.width - length) / 2,
                y: size.height - insets.bottom - 8 - length,
                width: length,
                height: length
            )
        case .west:
            return CGRect(
                x: insets.left + 8,
                y: (size.height - length) / 2,
                width: length,
                height: length
            )
        case .east:
            return CGRect(
                x: size.width - insets.right - 8 - length,
                y: (size.height - length) / 2,
                width: length,
                height: length
            )
        }
    }
}

struct EdgeControls: View {
    var enabled: Bool
    var pressed: Side?
    var insets: UIEdgeInsets
    var onSide: (Side) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                EdgeTouchCatcher(enabled: enabled, insets: insets, onSide: onSide)
                ForEach(Side.allCases, id: \.self) { side in
                    let frame = EdgeMetrics.frame(for: side, size: size, insets: insets)
                    edgeFace(side)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier("edge.\(side.rawValue)")
                        .accessibilityLabel(side.rawValue)
                }
            }
        }
    }

    /// Solid sand under a 45% sand coat, so the sky and water do not tint the button.
    private func edgeFace(_ side: Side) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.buttonSand)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.buttonSand.opacity(0.45))
            if pressed == side {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(hex: 0xFF5D8F))
            }
            CardinalArrow(side: side)
                .stroke(Palette.cream, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .shadow(color: Palette.ink.opacity(0.45), radius: 1.5, x: 0, y: 1.5)
                .frame(width: 28, height: 28)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Palette.buttonPlum, lineWidth: 3)
        )
        .offset(y: pressed == side ? 4 : 0)
    }
}

private struct CardinalArrow: Shape {
    var side: Side

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx: CGFloat
        let dy: CGFloat
        switch side {
        case .north: dx = 0; dy = -1
        case .south: dx = 0; dy = 1
        case .east: dx = 1; dy = 0
        case .west: dx = -1; dy = 0
        }
        let tip = CGPoint(x: center.x + dx * 10, y: center.y + dy * 10)
        let tail = CGPoint(x: center.x - dx * 10, y: center.y - dy * 10)
        let px = -dy
        let py = dx
        var path = Path()
        path.move(to: tail)
        path.addLine(to: tip)
        path.move(to: CGPoint(x: tip.x + px * 8 - dx * 8, y: tip.y + py * 8 - dy * 8))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x - px * 8 - dx * 8, y: tip.y - py * 8 - dy * 8))
        return path
    }
}

struct EdgeTouchCatcher: UIViewRepresentable {
    var enabled: Bool
    var insets: UIEdgeInsets
    var onSide: (Side) -> Void

    func makeUIView(context: Context) -> EdgePadView {
        let view = EdgePadView()
        view.onSide = onSide
        return view
    }

    func updateUIView(_ uiView: EdgePadView, context: Context) {
        uiView.onSide = onSide
        uiView.isUserInteractionEnabled = enabled
        uiView.edgeInsets = insets
        uiView.setNeedsLayout()
    }
}

final class EdgePadView: UIView {
    var onSide: ((Side) -> Void)?
    var edgeInsets = UIEdgeInsets.zero
    private var lastStamp = -1.0
    private let zones: [Side: EdgeZoneView]

    override init(frame: CGRect) {
        var built: [Side: EdgeZoneView] = [:]
        for side in Side.allCases {
            let zone = EdgeZoneView(side: side)
            zone.accessibilityIdentifier = "edge.\(side.rawValue)"
            zone.accessibilityLabel = side.rawValue
            zone.isAccessibilityElement = true
            built[side] = zone
        }
        zones = built
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        for zone in zones.values {
            zone.isUserInteractionEnabled = true
            zone.backgroundColor = .clear
            addSubview(zone)
            zone.onTouch = { [weak self] side, stamp in
                self?.accept(side, stamp: stamp)
            }
        }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for zone in zones.values {
            let local = zone.convert(point, from: self)
            if zone.point(inside: local, with: event) {
                return zone.hitTest(local, with: event)
            }
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insets = UIEdgeInsets(
            top: max(edgeInsets.top, safeAreaInsets.top),
            left: max(edgeInsets.left, safeAreaInsets.left),
            bottom: max(edgeInsets.bottom, safeAreaInsets.bottom),
            right: max(edgeInsets.right, safeAreaInsets.right)
        )
        for side in Side.allCases {
            zones[side]?.frame = EdgeMetrics.frame(for: side, size: bounds.size, insets: insets)
        }
    }

    private func accept(_ side: Side, stamp: TimeInterval) {
        guard stamp + 0.00001 >= lastStamp else { return }
        lastStamp = stamp
        onSide?(side)
    }
}

final class EdgeZoneView: UIView {
    let side: Side
    var onTouch: ((Side, TimeInterval) -> Void)?

    init(side: Side) {
        self.side = side
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.max(by: { $0.timestamp < $1.timestamp }) else { return }
        onTouch?(side, touch.timestamp)
    }
}
