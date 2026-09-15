import AppKit
import GlazeCore
import SwiftUI

/// The keyboard page: every player action, the key it answers to, and a way to change it.
struct ShortcutSettingsContent: View {
    @State private var shortcuts = PlayerShortcuts.shared
    /// The action waiting for a key.
    @State private var recording: PlayerAction?
    /// Said for a moment after a key was taken from another action, so the change is not
    /// silent.
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(PlayerAction.Group.allCases) { group in
                SettingsCard(titleKey: group.titleKey) {
                    ForEach(PlayerAction.allCases.filter { $0.group == group }) { action in
                        row(action)
                    }
                }
            }

            if let notice {
                Label(notice, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            HStack {
                Text(L10n.string("shortcut.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.string("shortcut.reset")) {
                    stopRecording()
                    shortcuts.resetToDefaults()
                    notice = nil
                }
                .disabled(shortcuts.isDefault)
            }
        }
        .animation(.easeOut(duration: 0.15), value: notice)
        .onDisappear(perform: stopRecording)
    }

    private func row(_ action: PlayerAction) -> some View {
        HStack {
            Text(L10n.string(action.titleKey))
            Spacer()

            ShortcutRecorderButton(
                combo: shortcuts.combo(for: action),
                isRecording: recording == action,
                onStart: { startRecording(action) },
                onClear: {
                    stopRecording()
                    shortcuts.clear(action)
                }
            )
        }
        .padding(.vertical, 2)
    }

    private func startRecording(_ action: PlayerAction) {
        recording = action
        notice = nil
        ShortcutRecorder.shared.begin { combo in
            // Escape on its own gives up rather than binding Escape.
            if let combo, !(combo.keyCode == 53 && combo.modifiers == 0) {
                if let taken = shortcuts.conflict(for: combo, excluding: action) {
                    notice = String(
                        format: L10n.string("shortcut.moved_format"),
                        combo.displayString,
                        L10n.string(taken.titleKey),
                        L10n.string(action.titleKey)
                    )
                }
                shortcuts.set(combo, for: action)
            }
            recording = nil
        }
    }

    private func stopRecording() {
        ShortcutRecorder.shared.cancel()
        recording = nil
    }
}

/// The key cap, or "press a key" while it is listening.
private struct ShortcutRecorderButton: View {
    let combo: KeyCombo?
    let isRecording: Bool
    let onStart: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onStart) {
                Text(label)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .monospacedDigit()
                    .frame(minWidth: 118)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? GlazeGlass.amber : nil)
            .accessibilityHint(L10n.string("shortcut.a11y.change"))

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(combo == nil ? 0 : 1)
            .disabled(combo == nil)
            .help(L10n.string("shortcut.clear"))
            .accessibilityLabel(L10n.string("shortcut.clear"))
        }
    }

    private var label: String {
        if isRecording { return L10n.string("shortcut.press") }
        return combo?.displayString ?? L10n.string("shortcut.none")
    }
}

/// Listens for the one key a recorder is waiting for.
///
/// An event monitor so the arrow keys and ⌘ combinations arrive intact — a focused
/// SwiftUI control would have the arrows move focus before it ever saw them.
@MainActor
final class ShortcutRecorder {
    static let shared = ShortcutRecorder()

    private var monitor: Any?
    private var completion: ((KeyCombo?) -> Void)?

    func begin(_ completion: @escaping (KeyCombo?) -> Void) {
        cancel()
        self.completion = completion
        PlayerShortcuts.shared.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let combo = KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags)
            MainActor.assumeIsolated { self?.finish(combo) }
            return nil
        }
    }

    func cancel() {
        guard monitor != nil || completion != nil else { return }
        let pending = completion
        tearDown()
        pending?(nil)
    }

    private func finish(_ combo: KeyCombo) {
        let pending = completion
        tearDown()
        pending?(combo)
    }

    private func tearDown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        completion = nil
        PlayerShortcuts.shared.isRecording = false
    }
}
