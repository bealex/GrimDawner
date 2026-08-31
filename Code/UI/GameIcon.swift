// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import GrimDawnerEngine
import SwiftUI

/// Carries the texture store down the view tree so any view can draw a record's art.
private struct TextureStoreKey: EnvironmentKey {
    static let defaultValue: TextureStore? = nil
}

private struct DamageIconsKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}

extension EnvironmentValues {
    var textures: TextureStore? {
        get { self[TextureStoreKey.self] }
        set { self[TextureStoreKey.self] = newValue }
    }

    /// The game's own mark for each damage type, by the token `Theme.damageToken` reads from a stat key.
    var damageIcons: [String: String] {
        get { self[DamageIconsKey.self] }
        set { self[DamageIconsKey.self] = newValue }
    }
}

/// Draws a panel's artwork at the size the game authored it, cropped to the region the panel occupies.
///
/// The character window ships as one texture holding several panels, so the doll is the top-left corner
/// of it rather than the whole image.
struct GameArtwork: View {
    let path: String
    let size: CGSize

    @Environment(\.textures)
    private var textures

    var body: some View {
        Group {
            if let image = textures?.image(at: path) {
                Image(decorative: image, scale: 1, orientation: .up)
                    .interpolation(.high)
            } else {
                Color.black.opacity(0.35)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A record's artwork at the size the game authored it, for the buttons whose records state only where
/// they go.
struct GameBitmap: View {
    let path: String

    @Environment(\.textures)
    private var textures

    var body: some View {
        if let image = textures?.image(at: path) {
            Image(decorative: image, scale: 1, orientation: .up)
                .interpolation(.high)
        }
    }
}

/// The game's quality badge, sat in the corner of an item's icon the way the game's own slots wear it.
struct ItemQualityMark: View {
    let path: String
    var size: CGFloat = 14

    var body: some View {
        if !path.isEmpty {
            GameIcon(path: path, size: size, fallbackSymbol: "")
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Draws the artwork a `.dbr` record names, falling back to a symbol when the texture is unavailable.
struct GameIcon: View {
    let path: String
    var size: CGFloat = 32
    /// Overrides the square frame; constellation art in particular is far wider than it is tall.
    var width: CGFloat?
    var height: CGFloat?
    /// `.fill` suits backdrop artwork, where a letterboxed edge would read as a stray rectangle.
    var contentMode: ContentMode = .fit
    /// False where the art may be shrunk to fit but never blown up past the size it was drawn at. The
    /// game's item icons are small, and a 32-point one stretched to 64 is a blurry 32-point one.
    var magnifies = true
    var fallbackSymbol = "questionmark"
    var label: String?

    @Environment(\.textures)
    private var textures

    var body: some View {
        let image = textures?.image(at: path)
        let asked = CGSize(width: width ?? size, height: height ?? size)
        let drawn = magnifies ? asked : Self.fitted(asked, within: image)

        return Group {
            if let image {
                Image(decorative: image, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: drawn.width, height: drawn.height)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }

    /// The asked-for box, shrunk by however much the artwork would have been blown up inside it.
    ///
    /// Fitting draws the picture at the smaller of the two ratios, so that is what decides whether it is
    /// magnified: a 32×32 icon in a 64-point box is drawn at twice its size and the box is halved, while
    /// a 32×64 one already fits a 64-point box exactly and is left alone.
    private static func fitted(_ asked: CGSize, within image: CGImage?) -> CGSize {
        guard let image, image.width > 0, image.height > 0 else { return asked }

        let fit = min(asked.width / CGFloat(image.width), asked.height / CGFloat(image.height))
        guard fit > 1 else { return asked }

        return CGSize(width: asked.width / fit, height: asked.height / fit)
    }
}
