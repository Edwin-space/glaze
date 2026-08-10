import SwiftUI

enum GlazeColors {
    static let playerBackground = Color.black
    static let panelBackground = Color(nsColor: .windowBackgroundColor)
    static let subtlePanel = Color(nsColor: .controlBackgroundColor)
    static let accent = Color.accentColor
    static let positive = Color.green
    static let warning = Color.orange
    static let danger = Color.red

    // Ceramic-glaze palette — the video stage and its "vessel" readiness signature
    // deliberately move off system/generic dark-UI tones toward the brand's literal
    // metaphor (자막 없는 영상에 유약을 입힌다). Kept separate from `accent` (which
    // stays bound to the system AccentColor asset for interactive controls).
    static let kiln = Color(red: 0x17 / 255, green: 0x12 / 255, blue: 0x0F / 255)
    static let kiln2 = Color(red: 0x1F / 255, green: 0x18 / 255, blue: 0x12 / 255)
    static let glazeDeep = Color(red: 0xA8 / 255, green: 0x63 / 255, blue: 0x1F / 255)
    static let glaze = Color(red: 0xD9 / 255, green: 0x8C / 255, blue: 0x3F / 255)
    static let glazeHoney = Color(red: 0xF0 / 255, green: 0xB9 / 255, blue: 0x68 / 255)
    static let celadon = Color(red: 0x7A / 255, green: 0x9B / 255, blue: 0x8E / 255)
    static let porcelain = Color(red: 0xED / 255, green: 0xE6 / 255, blue: 0xDA / 255)
    static let ash = Color(red: 0x94 / 255, green: 0x8A / 255, blue: 0x7B / 255)
}
