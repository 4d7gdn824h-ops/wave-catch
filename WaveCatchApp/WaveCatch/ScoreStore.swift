import Foundation

struct ScoreStore {
    private let scoreKey = "wavecatch.bestScore"
    private let comboKey = "wavecatch.bestCombo"

    var bestScore: Int { UserDefaults.standard.integer(forKey: scoreKey) }
    var bestCombo: Int { UserDefaults.standard.integer(forKey: comboKey) }

    func record(score: Int, combo: Int) {
        if score > bestScore {
            UserDefaults.standard.set(score, forKey: scoreKey)
        }
        if combo > bestCombo {
            UserDefaults.standard.set(combo, forKey: comboKey)
        }
    }
}
