//
//  Permissions.swift
//  ScreenExtend
//

import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

enum Permissions {

    // MARK: Screen Recording (required for ScreenCaptureKit)

    static func hasScreenRecording() -> Bool {
        // CGPreflightScreenCaptureAccess is available on macOS 10.15+.
        return CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecording() -> Bool {
        // Triggers the system prompt the first time; subsequent calls just
        // reflect current state.
        return CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Accessibility (required for synthetic mouse events)

    static func hasAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt.
        // Using the literal avoids CFString-vs-Unmanaged import differences that
        // vary across SDK versions.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
