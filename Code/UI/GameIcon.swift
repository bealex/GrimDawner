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
    var fallbackSymbol = "questionmark"
    var label: String?

    @Environment(\.textures)
    private var textures

    var body: some View {
        Group {
            if let image = textures?.image(at: path) {
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
        .frame(width: width ?? size, height: height ?? size)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }
}
