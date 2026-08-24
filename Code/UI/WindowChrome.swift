// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import AppKit
import GrimDawnerEngine
import SwiftUI

/// Runs the title bar across the whole window instead of one strip per column.
///
/// A split view gives each of its columns its own titlebar separator, which draws the toolbar as three
/// boxes rather than one bar. Only AppKit can say otherwise.
struct UnifiedTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            window.titlebarSeparatorStyle = .none
            for controller in Self.splitControllers(under: window.contentViewController) {
                for item in controller.splitViewItems { item.titlebarSeparatorStyle = .none }
            }
        }

        private static func splitControllers(under root: NSViewController?) -> [NSSplitViewController] {
            guard let root else { return [] }

            let children = root.children.flatMap { splitControllers(under: $0) }
            return ((root as? NSSplitViewController).map { [ $0 ] } ?? []) + children
        }
    }
}
