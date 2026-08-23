// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// The shape every tab takes: what you browse on the left, what you clicked on the right.
///
/// The sidebar keeps whatever width it was last dragged to, in this tab and every other. A window resize
/// moves the browsing side only, which is why this is a plain divider rather than an `HSplitView` — that
/// hands the trailing pane its maximum and re-splits on every resize.
struct TabLayout<Content: View, Detail: View>: View {
    @ViewBuilder
    var content: Content
    @ViewBuilder
    var detail: Detail

    @AppStorage("detailSidebarWidth")
    private var sidebarWidth: Double = 350
    @State
    private var widthAtDragStart: Double?

    private static var widthRange: ClosedRange<Double> { 260 ... 500 }

    var body: some View {
        HStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            divider

            ScrollView {
                detail
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: sidebarWidth)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.subtleBorder)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(.rect)
                    .onHover { $0 ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
                    .gesture(resize)
            }
            .accessibilityLabel("Sidebar width")
    }

    private var resize: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let start = widthAtDragStart ?? sidebarWidth
                widthAtDragStart = start
                sidebarWidth = min(
                    max(start - value.translation.width, Self.widthRange.lowerBound),
                    Self.widthRange.upperBound
                )
            }
            .onEnded { _ in widthAtDragStart = nil }
    }
}

/// The sidebar before anything has been clicked.
struct DetailPlaceholder: View {
    let title: String
    let hint: String

    var body: some View {
        ContentUnavailableView(label: { Label(title, systemImage: "hand.tap") }, description: { Text(hint) })
            .padding(.top, 60)
    }
}

/// A canvas drawn in the game's own pixel coordinates, scaled to the space it is given.
///
/// The game's UI records place everything by pixel, so the panels are laid out at their native size and
/// scaled once here — otherwise every position would need scaling at its own call site.
struct ScaledCanvas<Content: View>: View {
    let size: CGSize
    /// The art is authored at its final size, so it is only ever shrunk to fit a narrow window.
    var maximumScale: CGFloat = 1
    var alignment: Alignment = .top
    @ViewBuilder
    var content: Content

    @State
    private var availableWidth: CGFloat = 0

    var body: some View {
        let scale = availableWidth > 0 ? min(maximumScale, availableWidth / size.width) : 1

        content
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // Scaling leaves the layout size untouched, so the outer frame restates the scaled size.
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            // The measured width is this frame's, not the canvas's: an unscaled canvas is wider than the
            // window, and measuring it would keep proposing its own width back to itself.
            .frame(maxWidth: .infinity, alignment: alignment.horizontal == .leading ? .leading : .center)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { availableWidth = $0 })
    }
}
