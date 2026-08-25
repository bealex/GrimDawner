// Copyright (c) 2026 Alex Babaev. Licensed under the MIT licence — see LICENSE.

import AppKit
import CoreGraphics
import GrimDawnerEngine
import SwiftUI

/// Where the devotion map is looking: how far in, and at what point of the sky.
struct MapCamera: Equatable {
    static let zoomRange: ClosedRange<CGFloat> = 0.1 ... 2

    var zoom: CGFloat = 0.5
    /// The map point the view is centred on.
    var centre: CGPoint = .zero
    /// False asks the map to frame the sky again the next time it knows how large it is.
    var isFramed = false
    /// A patch of sky to move to. The map takes it the moment it knows how large it is and clears it,
    /// which is what lets something that has no idea of the view's size — a menu — ask to go there.
    var focus: CGRect?

    /// The map point drawn at a point of the view.
    func mapPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (point.x - size.width / 2) / zoom + centre.x, y: (point.y - size.height / 2) / zoom + centre.y)
    }

    /// Scales around a point of the view, so whatever is under the pointer stays under it.
    mutating func scale(by factor: CGFloat, around point: CGPoint, in size: CGSize, within bounds: CGRect) {
        let anchor = mapPoint(point, in: size)
        zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        centre = CGPoint(
            x: anchor.x - (point.x - size.width / 2) / zoom,
            y: anchor.y - (point.y - size.height / 2) / zoom
        )
        clamp(to: bounds)
    }

    /// Scales around the middle of the view, which is what the zoom controls step through.
    mutating func scale(by factor: CGFloat, within bounds: CGRect) {
        zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        clamp(to: bounds)
    }

    mutating func pan(by translation: CGSize, within bounds: CGRect) {
        centre = CGPoint(x: centre.x - translation.width / zoom, y: centre.y - translation.height / zoom)
        clamp(to: bounds)
    }

    /// Frames a region of the sky, which is how the map opens and what its Fit control returns to.
    mutating func frame(_ region: CGRect, in size: CGSize) {
        guard size.width > 0, size.height > 0, region.width > 0, region.height > 0 else { return }

        let fitted = min(size.width / region.width, size.height / region.height)
        zoom = min(max(fitted, Self.zoomRange.lowerBound), 1)
        centre = CGPoint(x: region.midX, y: region.midY)
        isFramed = true
    }

    private mutating func clamp(to bounds: CGRect) {
        guard !bounds.isEmpty else { return }

        centre.x = min(max(centre.x, bounds.minX), bounds.maxX)
        centre.y = min(max(centre.y, bounds.minY), bounds.maxY)
    }
}

/// The pointing-device input a map needs and SwiftUI does not deliver: the wheel, a pinch, a two-finger
/// scroll and a middle-button drag.
///
/// All of it comes from a local monitor rather than from the view itself, so the left clicks the map
/// selects with are left alone.
struct MapMouseInput: NSViewRepresentable {
    /// A wheel step: how much to scale by, and the point of the view it should hold still.
    var scale: (CGFloat, CGPoint) -> Void
    /// A middle-button drag, in points of the view.
    var pan: (CGSize) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = InputView()
        view.scale = scale
        view.pan = pan
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? InputView else { return }

        view.scale = scale
        view.pan = pan
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        (view as? InputView)?.stopWatching()
    }

    private final class InputView: NSView {
        var scale: ((CGFloat, CGPoint) -> Void)?
        var pan: ((CGSize) -> Void)?

        private var monitor: Any?
        private var lastDrag: NSPoint?

        /// Flipped, so a pointer position needs no conversion before it reaches the drawing code.
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? stopWatching() : startWatching()
        }

        func startWatching() {
            guard monitor == nil else { return }

            let events: NSEvent.EventTypeMask = [
                .scrollWheel, .magnify, .otherMouseDown, .otherMouseDragged, .otherMouseUp,
            ]
            monitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                self?.handle(event) == true ? nil : event
            }
        }

        func stopWatching() {
            guard let monitor else { return }

            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            lastDrag = nil
        }

        /// True when the event happened over the map and has been consumed.
        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }

            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return false }

            switch event.type {
                case .scrollWheel:
                    // Two fingers on a trackpad pan the sky, as they scroll anything else; a wheel,
                    // which reports coarse notches rather than precise deltas, zooms it. ⌘ zooms either.
                    if event.hasPreciseScrollingDeltas, !event.modifierFlags.contains(.command) {
                        pan?(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
                    } else {
                        scale?(Self.factor(of: event), point)
                    }
                case .magnify:
                    scale?(1 + event.magnification, point)
                case .otherMouseDown where event.buttonNumber == Self.middleButton:
                    lastDrag = event.locationInWindow
                case .otherMouseDragged where event.buttonNumber == Self.middleButton:
                    guard let previous = lastDrag else { return false }

                    // Window coordinates run bottom-up, the view's the other way.
                    pan?(CGSize(
                        width: event.locationInWindow.x - previous.x,
                        height: previous.y - event.locationInWindow.y
                    ))
                    lastDrag = event.locationInWindow
                case .otherMouseUp:
                    lastDrag = nil
                default:
                    return false
            }
            return true
        }

        /// A wheel notch is a coarse step; the fine deltas a trackpad sends arrive many times a second.
        private static func factor(of event: NSEvent) -> CGFloat {
            exp(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04))
        }

        private static let middleButton = 2
    }
}
