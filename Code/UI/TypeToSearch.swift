// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import AppKit
import SwiftUI

/// Starts a quick search on the first keystroke, with no field to click into first.
///
/// The keys are taken from a local monitor: nothing in these panels accepts text, so a keystroke that is
/// not a shortcut belongs to the search. Escape clears it, delete backs over it.
struct TypeToSearch: NSViewRepresentable {
    @Binding
    var text: String

    func makeNSView(context: Context) -> NSView {
        let view = TypingView()
        view.apply = { text = $0(text) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? TypingView)?.apply = { text = $0(text) }
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        (view as? TypingView)?.stopWatching()
    }

    private final class TypingView: NSView {
        /// Applies an edit to the query the view is bound to.
        var apply: ((@escaping (String) -> String) -> Void)?

        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? stopWatching() : startWatching()
        }

        func startWatching() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) == true ? nil : event
            }
        }

        func stopWatching() {
            guard let monitor else { return }

            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        /// True when the keystroke was typing rather than a shortcut, and has been taken for the search.
        private func handle(_ event: NSEvent) -> Bool {
            guard
                event.window === window,
                !event.modifierFlags.intersects([ .command, .control, .option, .function ]),
                !(window?.firstResponder is NSText)
            else { return false }

            switch event.keyCode {
                case Self.escapeKey:
                    var wasSearching = false
                    apply? { current in
                        wasSearching = !current.isEmpty
                        return ""
                    }
                    return wasSearching
                case Self.deleteKey:
                    var wasSearching = false
                    apply? { current in
                        wasSearching = !current.isEmpty
                        return String(current.dropLast())
                    }
                    return wasSearching
                default:
                    return type(event.characters ?? "")
            }
        }

        private func type(_ characters: String) -> Bool {
            let typed = characters.filter { $0.isLetter || $0.isNumber || $0.isPunctuation || $0 == " " }
            guard !typed.isEmpty else { return false }

            var accepted = false
            apply? { current in
                // A leading space is a button press, not the start of a search.
                guard !(current.isEmpty && typed.allSatisfy { $0 == " " }) else { return current }

                accepted = true
                return current + typed
            }
            return accepted
        }

        private static let escapeKey: UInt16 = 53
        private static let deleteKey: UInt16 = 51
    }
}

extension NSEvent.ModifierFlags {
    fileprivate func intersects(_ others: NSEvent.ModifierFlags) -> Bool {
        !intersection(others).isEmpty
    }
}

/// The floating chrome that shows what is being searched for.
struct SearchOverlay: View {
    @Binding
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(.body, design: .rounded).weight(.medium))
                .lineLimit(1)
                .truncationMode(.head)

            Text("esc")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 4))
                .fixedSize()

            Button("Clear the search", systemImage: "xmark.circle.fill") { text = "" }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(.secondary)
        }
        .focusEffectDisabled()
        .frame(maxWidth: 420)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.match.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(.top, 14)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Searching for \(text)")
    }
}
