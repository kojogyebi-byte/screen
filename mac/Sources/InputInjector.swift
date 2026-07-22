//
//  InputInjector.swift
//  ScreenExtend
//
//  Receives normalized pointer coordinates (0...1) from the tablet and posts
//  synthetic mouse events into the virtual display's region of the global
//  display space. Requires Accessibility permission.
//

import Foundation
import CoreGraphics

/// Mirrors the wire protocol pointer subtypes (see protocol notes in README).
enum PointerAction: UInt8 {
    case move      = 0
    case down      = 1
    case up        = 2
    case drag      = 3
    case rightDown = 4
    case rightUp   = 5
    case scroll    = 6
}

final class InputInjector {

    private var displayID: CGDirectDisplayID = 0
    private var bounds: CGRect = .zero
    private var leftDown = false
    private var rightDown = false

    /// Point in global coordinates, kept so move/drag can reuse it.
    private var lastPoint: CGPoint = .zero

    func setDisplay(_ id: CGDirectDisplayID) {
        displayID = id
        bounds = CGDisplayBounds(id)   // global coords, top-left origin
    }

    /// nx, ny are normalized within the extended display (0...1).
    /// dx, dy are scroll deltas (only used for .scroll).
    func handle(action: PointerAction, nx: Double, ny: Double, dx: Double, dy: Double) {
        guard displayID != 0, bounds.width > 0, bounds.height > 0 else { return }

        let x = bounds.origin.x + CGFloat(max(0.0, min(1.0, nx))) * bounds.width
        let y = bounds.origin.y + CGFloat(max(0.0, min(1.0, ny))) * bounds.height
        let pt = CGPoint(x: x, y: y)
        lastPoint = pt

        switch action {
        case .move:
            post(.mouseMoved, pt, button: .left)

        case .down:
            leftDown = true
            post(.leftMouseDown, pt, button: .left)

        case .up:
            leftDown = false
            post(.leftMouseUp, pt, button: .left)

        case .drag:
            // A finger held and moved == left-button drag.
            if leftDown {
                post(.leftMouseDragged, pt, button: .left)
            } else {
                post(.mouseMoved, pt, button: .left)
            }

        case .rightDown:
            rightDown = true
            post(.rightMouseDown, pt, button: .right)

        case .rightUp:
            rightDown = false
            post(.rightMouseUp, pt, button: .right)

        case .scroll:
            postScroll(dx: dx, dy: dy)
        }
    }

    private func post(_ type: CGEventType, _ point: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(mouseEventSource: nil,
                                  mouseType: type,
                                  mouseCursorPosition: point,
                                  mouseButton: button) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postScroll(dx: Double, dy: Double) {
        // Pixel-precise scrolling. Vertical first axis, horizontal second.
        let yLines = Int32(dy.rounded())
        let xLines = Int32(dx.rounded())
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 2,
                                  wheel1: yLines,
                                  wheel2: xLines,
                                  wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }
}
