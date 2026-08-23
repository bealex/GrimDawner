// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// Lays cards out in columns, each card going to whichever column is currently shortest.
///
/// A `LazyVGrid` gives every row the height of its tallest cell, which leaves large gaps under short
/// cards when they sit beside a long one. Measuring the cards and packing columns instead keeps the sheet
/// dense however uneven the cards are.
struct MasonryLayout: Layout {
    struct Cache {
        var columnCount: Int = 0
        var columnWidth: CGFloat = 0
        var heights: [CGFloat] = []
        var placements: [CGPoint] = []
    }

    /// The narrowest a column may become before the layout drops to fewer columns.
    var minimumColumnWidth: CGFloat = 280
    var maximumColumnWidth: CGFloat = 460
    var spacing: CGFloat = 14

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        // A split view proposes an infinite width while it sizes its columns; one column is the answer.
        let proposed = proposal.width ?? minimumColumnWidth
        let width = proposed.isFinite ? max(proposed, minimumColumnWidth) : minimumColumnWidth
        pack(width: width, subviews: subviews, cache: &cache)

        return CGSize(width: width, height: cache.heights.max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        pack(width: bounds.width, subviews: subviews, cache: &cache)

        for (index, subview) in subviews.enumerated() {
            guard index < cache.placements.count else { continue }

            let origin = cache.placements[index]
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(width: cache.columnWidth, height: nil)
            )
        }
    }

    private func pack(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        let columnCount = max(1, Int((width + spacing) / (minimumColumnWidth + spacing)))
        let available = width - spacing * CGFloat(columnCount - 1)
        let columnWidth = min(maximumColumnWidth, available / CGFloat(columnCount))

        cache.columnCount = columnCount
        cache.columnWidth = columnWidth
        cache.heights = [CGFloat](repeating: 0, count: columnCount)
        cache.placements = []
        cache.placements.reserveCapacity(subviews.count)

        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            let column = cache.heights.enumerated().min { $0.element < $1.element }?.offset ?? 0

            let x = CGFloat(column) * (columnWidth + spacing)
            cache.placements.append(CGPoint(x: x, y: cache.heights[column]))
            cache.heights[column] += height + spacing
        }

        // The trailing gap after the last card in each column is not part of the content.
        for index in cache.heights.indices where cache.heights[index] > 0 {
            cache.heights[index] -= spacing
        }
    }
}
