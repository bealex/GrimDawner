// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import SwiftUI

/// The devotion sky, drawn where the game puts it: nebulas, constellations, and the stars between them.
///
/// The whole map is one `Canvas` rather than a view per star. There are 559 of them across 110
/// constellations, and hit-testing them by hand costs far less than laying out that many views.
struct DevotionMapView: View {
    let map: DevotionMap
    let search: QuickSearch
    @Binding
    var camera: MapCamera
    @Binding
    var selectedStar: DevotionStar.ID?
    @Binding
    var selectedConstellation: ResolvedConstellation.ID?

    @Environment(\.textures)
    private var textures

    @State
    private var size: CGSize = .zero
    @State
    private var hovered: DevotionStar.ID?
    private static let fallbackStarSize = CGSize(width: 64, height: 64)

    var body: some View {
        Canvas(opaque: true) { context, size in
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: camera.zoom, y: camera.zoom)
            context.translateBy(x: -camera.centre.x, y: -camera.centre.y)
            draw(in: &context)
        }
        .background(.black)
        .background(MapMouseInput(scale: scale, pan: pan))
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: resized)
        .onTapGesture { select(at: $0) }
        .onContinuousHover { phase in
            switch phase {
                case let .active(location): hovered = star(at: location)?.star.id
                case .ended: hovered = nil
            }
        }
        .accessibilityLabel("Devotion map, \(map.takenStars) stars taken")
    }

    // MARK: - The camera

    private func resized(_ size: CGSize) {
        self.size = size
        guard !camera.isFramed else { return }

        camera.frame(map.starBounds, in: size)
    }

    private func scale(by factor: CGFloat, around point: CGPoint) {
        camera.scale(by: factor, around: point, in: size, within: map.bounds)
    }

    private func pan(by translation: CGSize) {
        camera.pan(by: translation, within: map.bounds)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext) {
        drawSky(in: &context)
        for constellation in map.constellations {
            draw(constellation, in: &context)
        }
    }

    private func drawSky(in context: inout GraphicsContext) {
        if let tile = textures?.image(at: map.tile) {
            let size = CGSize(width: tile.width, height: tile.height)
            let image = Image(decorative: tile, scale: 1)
            var y = map.bounds.minY
            while y < map.bounds.maxY {
                var x = map.bounds.minX
                while x < map.bounds.maxX {
                    context.draw(image, in: CGRect(origin: CGPoint(x: x, y: y), size: size))
                    x += size.width
                }
                y += size.height
            }
        }

        for nebula in map.nebulas {
            guard let image = textures?.image(at: nebula.bitmap) else { continue }

            context.draw(
                Image(decorative: image, scale: 1),
                in: CGRect(origin: nebula.position, size: CGSize(width: image.width, height: image.height))
            )
        }
    }

    private func draw(_ constellation: ResolvedConstellation, in context: inout GraphicsContext) {
        let tint = constellation.tint
        let fade = emphasis(of: constellation) == .faded ? 0.3 : 1

        if let art = textures?.image(at: constellation.iconPath) {
            let rect = CGRect(origin: constellation.position, size: CGSize(width: art.width, height: art.height))
            context.drawLayer { layer in
                layer.opacity = tint.opacity * fade
                layer.addFilter(.colorMultiply(tint.color))
                layer.draw(Image(decorative: art, scale: 1), in: rect)
            }
        }

        drawLinks(constellation, tint: tint, fade: fade, in: &context)

        for star in constellation.stars {
            draw(star, in: constellation, tint: tint, fade: fade, in: &context)
        }
    }

    private func drawLinks(
        _ constellation: ResolvedConstellation,
        tint: DevotionTint,
        fade: Double,
        in context: inout GraphicsContext
    ) {
        for (index, star) in constellation.stars.enumerated() {
            guard
                let linked = star.linkedTo,
                constellation.stars.indices.contains(linked),
                linked != index
            else { continue }

            let other = constellation.stars[linked]
            let bothTaken = star.isTaken && other.isTaken
            let art = bothTaken
                ? map.links.active
                : (constellation.isAvailable ? map.links.inactive : map.links.locked)
            drawLink(
                from: centre(of: star),
                to: centre(of: other),
                art: art,
                tint: tint,
                opacity: (bothTaken ? 1 : tint.opacity) * fade,
                in: &context
            )
        }
    }

    /// Lays the window's connector art along the line between two stars.
    private func drawLink(
        from start: CGPoint,
        to end: CGPoint,
        art: String,
        tint: DevotionTint,
        opacity: Double,
        in context: inout GraphicsContext
    ) {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return }
        guard
            let image = textures?.image(at: art)
        else {
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(tint.color.opacity(opacity)), lineWidth: map.links.width)
            return
        }

        context.drawLayer { layer in
            layer.opacity = opacity
            layer.translateBy(x: start.x, y: start.y)
            layer.rotate(by: .radians(atan2(end.y - start.y, end.x - start.x)))
            layer.draw(
                Image(decorative: image, scale: 1),
                in: CGRect(x: 0, y: -map.links.width / 2, width: length, height: map.links.width)
            )
        }
    }

    private func draw(
        _ star: DevotionStar,
        in constellation: ResolvedConstellation,
        tint: DevotionTint,
        fade: Double,
        in context: inout GraphicsContext
    ) {
        let rect = CGRect(origin: star.position, size: starSize)
        let isMatch = search.isActive && matches(star, in: constellation)

        if let sprite = textures?.image(at: star.sprite) {
            context.drawLayer { layer in
                layer.opacity = (star.isTaken ? 1 : tint.opacity) * fade
                if !star.isTaken { layer.addFilter(.colorMultiply(tint.color)) }
                layer.draw(Image(decorative: sprite, scale: 1), in: rect)
            }
        }

        if star.isPower, let icon = textures?.image(at: star.skill.iconPath) {
            let inset = rect.insetBy(dx: rect.width / 5, dy: rect.height / 5)
            context.drawLayer { layer in
                layer.opacity = (star.isTaken ? 1 : 0.5) * fade
                layer.draw(Image(decorative: icon, scale: 1), in: inset)
            }
        }

        if star.id == selectedStar || star.id == hovered {
            let colour = star.id == selectedStar ? Theme.accent : Color.white
            context.stroke(Path(ellipseIn: rect.insetBy(dx: 6, dy: 6)), with: .color(colour), lineWidth: 3)
        }

        if isMatch {
            context.stroke(Path(ellipseIn: rect.insetBy(dx: 2, dy: 2)), with: .color(Theme.match), lineWidth: 4)
        }
    }

    // MARK: - Selection

    private func select(at location: CGPoint) {
        guard let hit = star(at: location) else { return }

        selectedStar = hit.star.id
        selectedConstellation = hit.constellation.id
    }

    /// The star under a point of the view, if the pointer is on one.
    private func star(at location: CGPoint) -> (star: DevotionStar, constellation: ResolvedConstellation)? {
        let point = camera.mapPoint(location, in: size)

        for constellation in map.constellations {
            for star in constellation.stars where CGRect(origin: star.position, size: starSize).contains(point) {
                return (star, constellation)
            }
        }
        return nil
    }

    // MARK: - Geometry

    private var starSize: CGSize {
        textures?.size(at: map.constellations.first?.stars.first?.sprite ?? "") ?? Self.fallbackStarSize
    }

    private func centre(of star: DevotionStar) -> CGPoint {
        CGPoint(x: star.position.x + starSize.width / 2, y: star.position.y + starSize.height / 2)
    }

    private func emphasis(of constellation: ResolvedConstellation) -> QuickSearch.Emphasis {
        search.emphasis(isMatch: constellation.stars.contains { matches($0, in: constellation) })
    }

    private func matches(_ star: DevotionStar, in constellation: ResolvedConstellation) -> Bool {
        search.matches([ constellation.name, star.skill.name ] + star.skill.stats.titles)
    }
}
