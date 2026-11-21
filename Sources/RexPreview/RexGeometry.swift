import AppKit
import CoreGraphics
import Foundation

/// Computes target AppKit window frames docked relative to Rex's frontmost workspace window.
@MainActor
enum RexGeometry {
    static let rexBundleID = "com.superlogical.rex"
    private static let rexAppDomain = "com.superlogical.rex" as CFString

    struct RexWindowInfo {
        /// Rex's workspace window frame in AppKit global screen coordinates.
        let frame: CGRect
        /// Rex's content area (excluding its left/right sidebar when expanded).
        let contentFrame: CGRect
    }

    static func frontmostRexWindow() -> RexWindowInfo? {
        guard let rexApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == rexBundleID
        }), !rexApp.isHidden else {
            return nil
        }

        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else {
            return nil
        }

        let rexPID = rexApp.processIdentifier
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == rexPID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            let title = (info[kCGWindowName as String] as? String) ?? ""
            if title.hasPrefix("Settings") || cgRect.width < 450 || cgRect.height < 300 {
                continue
            }

            let appKitFrame = CGRect(
                x: cgRect.origin.x,
                y: primaryHeight - (cgRect.origin.y + cgRect.height),
                width: cgRect.width,
                height: cgRect.height
            )

            CFPreferencesAppSynchronize(rexAppDomain)
            let collapsed = prefBool("Workspace.sidebarCollapsed") ?? false
            let tabStyle = prefString("Workspace.tabStyle") ?? "vertical"
            let sidebarPos = prefString("Workspace.sidebarPosition") ?? "left"
            let sidebarWidth = (!collapsed && tabStyle == "vertical")
                ? CGFloat(prefDouble("Workspace.sidebarWidth") ?? 167)
                : 0

            let contentFrame: CGRect
            if sidebarWidth > 0 && sidebarPos == "left" {
                contentFrame = CGRect(
                    x: appKitFrame.minX + sidebarWidth,
                    y: appKitFrame.minY,
                    width: max(300, appKitFrame.width - sidebarWidth),
                    height: appKitFrame.height
                )
            } else if sidebarWidth > 0 && sidebarPos == "right" {
                contentFrame = CGRect(
                    x: appKitFrame.minX,
                    y: appKitFrame.minY,
                    width: max(300, appKitFrame.width - sidebarWidth),
                    height: appKitFrame.height
                )
            } else {
                contentFrame = appKitFrame
            }

            return RexWindowInfo(frame: appKitFrame, contentFrame: contentFrame)
        }
        return nil
    }

    static func targetFrame(side: DockSide, widthPercent: CGFloat) -> CGRect {
        let base: CGRect
        if let rex = frontmostRexWindow() {
            base = rex.contentFrame
        } else {
            base = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
                ?? CGRect(x: 100, y: 100, width: 1200, height: 800)
        }

        let inset: CGFloat = 6
        let usable = base.insetBy(dx: inset, dy: inset)
        let frac = max(0.2, min(1.0, widthPercent / 100.0))

        switch side {
        case .right:
            let w = max(360, usable.width * frac)
            return CGRect(x: usable.maxX - w, y: usable.minY, width: w, height: usable.height)
        case .left:
            let w = max(360, usable.width * frac)
            return CGRect(x: usable.minX, y: usable.minY, width: w, height: usable.height)
        case .center:
            let w = max(480, usable.width * min(0.85, max(0.6, frac)))
            let h = max(420, usable.height * 0.88)
            return CGRect(
                x: usable.midX - w / 2,
                y: usable.midY - h / 2,
                width: w,
                height: h
            )
        case .full:
            return usable
        }
    }

    static func refocusRex() {
        guard let rexApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == rexBundleID
        }) else { return }
        rexApp.activate()
    }

    private static func prefBool(_ key: String) -> Bool? {
        guard let val = CFPreferencesCopyAppValue(key as CFString, rexAppDomain) else { return nil }
        if let b = val as? Bool { return b }
        if let n = val as? NSNumber { return n.boolValue }
        return nil
    }

    private static func prefDouble(_ key: String) -> Double? {
        guard let val = CFPreferencesCopyAppValue(key as CFString, rexAppDomain) else { return nil }
        if let d = val as? Double { return d }
        if let n = val as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func prefString(_ key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, rexAppDomain) as? String
    }
}
