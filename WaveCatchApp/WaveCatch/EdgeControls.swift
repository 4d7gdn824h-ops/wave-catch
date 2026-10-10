import SwiftUI
import UIKit
import WaveCatchCore

/// Full-screen diagonal zones. The two diagonals cross at the surfer: top is N, right E, bottom S, left W.
struct EdgeControls: View {
    var enabled: Bool
    var onSide: (Side) -> Void

    var body: some View {
        DiagonalTouchCatcher(enabled: enabled, onSide: onSide)
    }
}

struct DiagonalTouchCatcher: UIViewRepresentable {
    var enabled: Bool
    var onSide: (Side) -> Void

    func makeUIView(context: Context) -> DiagonalPadView {
        let view = DiagonalPadView()
        view.onSide = onSide
        return view
    }

    func updateUIView(_ uiView: DiagonalPadView, context: Context) {
        uiView.onSide = onSide
        uiView.isUserInteractionEnabled = enabled
    }
}

final class DiagonalPadView: UIView {
    var onSide: ((Side) -> Void)?
    private var lastStamp = -1.0
    private let zones: [Side: UIView]

    override init(frame: CGRect) {
        var built: [Side: UIView] = [:]
        for side in Side.allCases {
            let zone = UIView()
            zone.backgroundColor = .clear
            zone.isUserInteractionEnabled = false
            zone.isAccessibilityElement = true
            zone.accessibilityIdentifier = "edge.\(side.rawValue)"
            zone.accessibilityLabel = side.rawValue
            built[side] = zone
        }
        zones = built
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        for zone in zones.values {
            addSubview(zone)
        }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Leave the top HUD strip (score, lives, pause) to the views above this pad.
        guard bounds.contains(point), point.y > 76 else { return nil }
        return self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        zones[.north]?.frame = CGRect(x: width * 0.35, y: 80, width: width * 0.30, height: height * 0.22)
        zones[.south]?.frame = CGRect(x: width * 0.35, y: height * 0.72, width: width * 0.30, height: height * 0.22)
        zones[.east]?.frame = CGRect(x: width * 0.72, y: height * 0.35, width: width * 0.22, height: height * 0.30)
        zones[.west]?.frame = CGRect(x: width * 0.04, y: height * 0.35, width: width * 0.22, height: height * 0.30)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.max(by: { $0.timestamp < $1.timestamp }) else { return }
        accept(side(at: touch.location(in: self)), stamp: touch.timestamp)
    }

    private func side(at point: CGPoint) -> Side {
        let dx = point.x - bounds.midX
        let dy = point.y - bounds.midY
        let nx = abs(dx) / max(bounds.width / 2, 1)
        let ny = abs(dy) / max(bounds.height / 2, 1)
        if ny >= nx {
            return dy < 0 ? .north : .south
        }
        return dx >= 0 ? .east : .west
    }

    private func accept(_ side: Side, stamp: TimeInterval) {
        guard stamp + 0.00001 >= lastStamp else { return }
        lastStamp = stamp
        onSide?(side)
    }
}
