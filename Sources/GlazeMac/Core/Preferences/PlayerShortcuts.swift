import AppKit
import GlazeCore
import Observation
import SwiftUI

/// Something the keyboard can do to a film.
enum PlayerAction: String, CaseIterable, Codable, Identifiable {
    case playPause
    case skipBackward
    case skipForward
    case volumeUp
    case volumeDown
    case previousItem
    case nextItem

    var id: String { rawValue }

    var titleKey: String { "shortcut.action.\(rawValue)" }

    /// Which shelf of the settings list it sits on.
    var group: Group {
        switch self {
        case .playPause, .skipBackward, .skipForward: .playback
        case .volumeUp, .volumeDown: .volume
        case .previousItem, .nextItem: .playlist
        }
    }

    enum Group: String, CaseIterable, Identifiable {
        case playback, volume, playlist
        var id: String { rawValue }
        var titleKey: String { "shortcut.group.\(rawValue)" }
    }
}

/// A key and the modifiers held with it.
///
/// Stored by `keyCode` rather than by character: the arrow keys have no character, and a
/// Korean input source turns the same physical key into a different letter, which would
/// make a shortcut stop working the moment someone switched to 한글.
struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt16
    /// `NSEvent.ModifierFlags.rawValue`, limited to the four that mean something here.
    let modifiers: UInt

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode
            && event.modifierFlags.intersection(Self.relevantModifiers).rawValue == modifiers
    }

    /// The way macOS writes a shortcut in its menus: ⌃⌥⇧⌘ then the key.
    var displayString: String {
        var text = ""
        let flags = modifierFlags
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    private static func keyName(_ code: UInt16) -> String {
        switch code {
        case 49: "Space"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        case 36: "↩"
        case 48: "⇥"
        case 51: "⌫"
        case 53: "⎋"
        case 116: "Page Up"
        case 121: "Page Down"
        case 115: "Home"
        case 119: "End"
        default: letter(for: code) ?? "Key \(code)"
        }
    }

    /// The letter the key prints on a US layout, which is what is engraved on it. Asking
    /// the current input source instead would label ⌘N as ⌘ㅜ for a Korean typist.
    private static func letter(for code: UInt16) -> String? {
        let letters: [UInt16: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
            38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
            15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8",
            25: "9", 29: "0", 27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'",
            43: ",", 47: ".", 44: "/", 42: "\\", 50: "`"
        ]
        return letters[code]
    }
}

/// Which keys do what, as the viewer has set them.
///
/// The defaults are what people already reach for in a video player on a Mac: space to
/// pause, the arrows to skip and change the volume. Moving between films is a combination
/// rather than a bare key, so a stray press does not throw someone into the next episode.
@MainActor
@Observable
final class PlayerShortcuts {
    static let shared = PlayerShortcuts()

    static let defaults: [PlayerAction: KeyCombo] = [
        .playPause: KeyCombo(keyCode: 49, modifiers: []),
        .skipBackward: KeyCombo(keyCode: 123, modifiers: []),
        .skipForward: KeyCombo(keyCode: 124, modifiers: []),
        .volumeUp: KeyCombo(keyCode: 126, modifiers: []),
        .volumeDown: KeyCombo(keyCode: 125, modifiers: []),
        .previousItem: KeyCombo(keyCode: 123, modifiers: .command),
        .nextItem: KeyCombo(keyCode: 124, modifiers: .command)
    ]

    /// How much one press of the volume keys moves it.
    static let volumeStep = 0.05

    private(set) var bindings: [PlayerAction: KeyCombo]
    /// True while the settings screen is waiting for a key. The player must not act on
    /// that key — pressing → to assign it would otherwise also skip the film ten seconds.
    var isRecording = false
    private let store: UserDefaults
    private let key = "player.shortcuts"

    /// What is written to disk. `known` is every action that existed when it was saved:
    /// an action in `known` with no binding was cleared on purpose and stays cleared,
    /// while an action added in a later version picks up its default. Without it a
    /// shortcut someone removed came back the next time the app opened.
    private struct Saved: Codable {
        var bindings: [String: KeyCombo]
        var known: [String]
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        var merged = Self.defaults
        if let data = store.data(forKey: key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            for name in saved.known {
                guard let action = PlayerAction(rawValue: name) else { continue }
                merged[action] = saved.bindings[name]
            }
        }
        bindings = merged
    }

    func combo(for action: PlayerAction) -> KeyCombo? { bindings[action] }

    func action(for combo: KeyCombo) -> PlayerAction? {
        bindings.first { $0.value == combo }?.key
    }

    /// The action already using a combination, other than the one being changed — so the
    /// settings screen can say so instead of silently leaving two actions on one key.
    func conflict(for combo: KeyCombo, excluding action: PlayerAction) -> PlayerAction? {
        bindings.first { $0.key != action && $0.value == combo }?.key
    }

    /// Assigns a combination. Whatever held it before loses it rather than both firing.
    func set(_ combo: KeyCombo, for action: PlayerAction) {
        if let previous = conflict(for: combo, excluding: action) {
            bindings[previous] = nil
        }
        bindings[action] = combo
        save()
    }

    func clear(_ action: PlayerAction) {
        bindings[action] = nil
        save()
    }

    func resetToDefaults() {
        bindings = Self.defaults
        save()
    }

    var isDefault: Bool { bindings == Self.defaults }

    private func save() {
        let saved = Saved(
            bindings: Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) }),
            known: PlayerAction.allCases.map(\.rawValue)
        )
        store.set(try? JSONEncoder().encode(saved), forKey: key)
    }
}

/// What the player needs from a key press, copied out of the `NSEvent` on the thread
/// AppKit delivered it on.
struct KeyEventSnapshot: Sendable {
    let combo: KeyCombo
    let isTyping: Bool
    let isInMainWindowWithoutSheet: Bool

    init(_ event: NSEvent) {
        combo = KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags)
        isTyping = event.window?.firstResponder is NSText
        isInMainWindowWithoutSheet = event.window?.isMainWindow == true && event.window?.attachedSheet == nil
    }
}
