import SwiftUI
import UIKit

enum Palette {
    static let indigo = Color(hex: 0x2B1055)
    static let violet = Color(hex: 0x7A2E8E)
    static let hotPink = Color(hex: 0xFF5E8A)
    static let tangerine = Color(hex: 0xFF9F5A)
    static let sun = Color(hex: 0xFFD66B)
    static let sea = Color(hex: 0x1FB5C9)
    static let deepSea = Color(hex: 0x0E7C99)
    static let foam = Color(hex: 0xFFF4E0)
    static let sand = Color(hex: 0xF7C9A0)
    static let buttonSand = Color(hex: 0xF6D7A7)
    static let buttonPlum = Color(hex: 0x3B1F4A)
    static let ink = Color(hex: 0x2A1A3A)
    static let shell = Color(hex: 0xFFB3C7)
    static let board = Color(hex: 0x3EE6B0)
    static let ring = Color(hex: 0xFF6B35)
    static let jelly = Color(hex: 0xB14CFF)
    static let lime = Color(hex: 0xC6FF3D)
    static let skin = Color(hex: 0xFFC7A1)
    static let hair = Color(hex: 0xF2C14E)

    static let uiIndigo = UIColor(hex: 0x2B1055)
    static let uiViolet = UIColor(hex: 0x7A2E8E)
    static let uiHotPink = UIColor(hex: 0xFF5E8A)
    static let uiTangerine = UIColor(hex: 0xFF9F5A)
    static let uiSun = UIColor(hex: 0xFFD66B)
    static let uiSea = UIColor(hex: 0x1FB5C9)
    static let uiDeepSea = UIColor(hex: 0x0E7C99)
    static let uiFoam = UIColor(hex: 0xFFF4E0)
    static let uiFoamLip = UIColor(hex: 0xFFF3E0)
    static let uiSand = UIColor(hex: 0xF7C9A0)
    static let uiInk = UIColor(hex: 0x2A1A3A)
    static let uiShell = UIColor(hex: 0xFFB3C7)
    static let uiBoard = UIColor(hex: 0x3EE6B0)
    static let uiRing = UIColor(hex: 0xFF6B35)
    static let uiJelly = UIColor(hex: 0xB14CFF)
    static let uiLime = UIColor(hex: 0xC6FF3D)
    static let uiSkin = UIColor(hex: 0xFFC7A1)
    static let uiHair = UIColor(hex: 0xF2C14E)
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
