#!/usr/bin/env swift
// fix-sharing.swift — Force-clear a stuck SCContentSharingPicker session.
// Run with: swift fix-sharing.swift

import Foundation
import ScreenCaptureKit

if #available(macOS 15.0, *) {
    let picker = SCContentSharingPicker.shared
    picker.isActive = false
    print("✓ SCContentSharingPicker.shared.isActive set to false")
    print("  The menu bar sharing indicator should clear within a few seconds.")
    print("  If not, run: killall controlcenter")
} else {
    print("This script requires macOS 15.0+")
}

// Give the run loop a moment to process the state change
RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
