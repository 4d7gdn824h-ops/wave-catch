import UIKit

/// One generator per impact style. At most one fire per 50 ms, and each generator is prepared.
final class HapticPlayer {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private var lastFire = 0.0

    func prepareAll() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        rigid.prepare()
    }

    func catchFeedback(kind: String, close: Bool, wave: Bool) {
        if close {
            fire(.light, intensity: 1)
            return
        }
        if wave {
            fire(.light, intensity: 0.4)
            return
        }
        switch kind {
        case "board":
            fire(.light, intensity: 0.8)
        case "lifeRing":
            fire(.medium, intensity: 0.7)
        default:
            fire(.light, intensity: 0.6)
        }
    }

    func miss() {
        fire(.heavy, intensity: 1)
    }

    func sting() {
        fire(.rigid, intensity: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.fire(.heavy, intensity: 0.8)
        }
    }

    private enum Style {
        case light, medium, heavy, rigid
    }

    private func fire(_ style: Style, intensity: CGFloat) {
        let now = CACurrentMediaTime()
        if now - lastFire < 0.05 { return }
        lastFire = now
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light: generator = light
        case .medium: generator = medium
        case .heavy: generator = heavy
        case .rigid: generator = rigid
        }
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }
}
