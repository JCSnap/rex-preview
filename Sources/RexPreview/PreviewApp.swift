import AppKit
import SwiftUI

final class PreviewWindow: NSWindow {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}

struct PreviewRootView: View {
    let kind: PreviewKind
    @ObservedObject var controller: PreviewController
    @State var isPinned: Bool
    @State var activeSide: DockSide

    let onDock: (DockSide) -> Void
    let onTogglePin: (Bool) -> Void
    let onOpenExternal: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            previewBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.08, green: 0.085, blue: 0.10))
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Space for macOS traffic lights on the left.
            Color.clear.frame(width: 66, height: 1)

            Text(kind.badge)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

            Text(kind.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                dockButton("sidebar.left", side: .left, help: "Dock left over Rex")
                dockButton("sidebar.right", side: .right, help: "Dock right over Rex")
                dockButton("rectangle.inset.filled", side: .center, help: "Center over Rex")
            }

            Divider().frame(height: 12).opacity(0.4)

            Button {
                isPinned.toggle()
                onTogglePin(isPinned)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(isPinned ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin from floating above Rex" : "Pin floating above Rex")

            Button {
                controller.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reload (⌘R)")

            Button {
                onOpenExternal()
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in default app (⌘O)")
        }
        .padding(.trailing, 12)
        .frame(height: 34)
        .background(Color(red: 0.105, green: 0.112, blue: 0.13))
    }

    private func dockButton(_ icon: String, side: DockSide, help: String) -> some View {
        Button {
            activeSide = side
            onDock(side)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(activeSide == side ? Color.primary : .secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private var previewBody: some View {
        switch kind {
        case .pdf(let url):
            NativePDFView(url: url, controller: controller)
        case .html, .webURL, .markdown, .csv, .image:
            NativeWebView(kind: kind, controller: controller)
        case .video(let url):
            NativeVideoView(url: url, controller: controller)
        case .quickLook(let url):
            NativeQuickLookView(url: url, controller: controller)
        }
    }
}

@MainActor
final class PreviewAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let options: LaunchOptions
    let kind: PreviewKind
    let controller = PreviewController()
    var window: PreviewWindow?
    var watcher: FileWatcher?

    init(options: LaunchOptions, kind: PreviewKind) {
        self.options = options
        self.kind = kind
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenu()

        let frame = RexGeometry.targetFrame(side: options.side, widthPercent: options.widthPercent)
        let win = PreviewWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = kind.title
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.backgroundColor = NSColor(red: 0.08, green: 0.085, blue: 0.10, alpha: 1)
        win.level = options.pinned ? .floating : .normal
        win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        win.delegate = self
        win.onEscape = { [weak self] in self?.closeAndRefocusRex() }

        let root = PreviewRootView(
            kind: kind,
            controller: controller,
            isPinned: options.pinned,
            activeSide: options.side,
            onDock: { [weak self] side in
                guard let self, let win = self.window else { return }
                let target = RexGeometry.targetFrame(side: side, widthPercent: self.options.widthPercent)
                win.setFrame(target, display: true, animate: true)
            },
            onTogglePin: { [weak self] pinned in
                self?.window?.level = pinned ? .floating : .normal
            },
            onOpenExternal: { [weak self] in
                guard let self else { return }
                NSWorkspace.shared.open(self.kind.externalURL)
            },
            onClose: { [weak self] in
                self?.closeAndRefocusRex()
            }
        )

        win.contentView = NSHostingView(rootView: root)
        win.setFrame(frame, display: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win

        if let fileURL = kind.fileURL {
            let w = FileWatcher(url: fileURL) { [weak self] in
                self?.controller.reload()
            }
            w.start()
            self.watcher = w
        }
    }

    func windowWillClose(_ notification: Notification) {
        watcher?.stop()
        RexGeometry.refocusRex()
        NSApp.terminate(nil)
    }

    private func closeAndRefocusRex() {
        window?.close()
    }

    private func installMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close", action: #selector(menuClose), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Reload", action: #selector(menuReload), keyEquivalent: "r")
        appMenu.addItem(withTitle: "Open in Default App", action: #selector(menuOpenExternal), keyEquivalent: "o")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Zoom In", action: #selector(menuZoomIn), keyEquivalent: "+")
        appMenu.addItem(withTitle: "Zoom Out", action: #selector(menuZoomOut), keyEquivalent: "-")
        appMenu.addItem(withTitle: "Actual Size", action: #selector(menuZoomReset), keyEquivalent: "0")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit", action: #selector(menuClose), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu so Cmd+C / Cmd+A / Cmd+F work in WebView and PDFView.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func menuClose() { closeAndRefocusRex() }
    @objc private func menuReload() { controller.reload() }
    @objc private func menuOpenExternal() { NSWorkspace.shared.open(kind.externalURL) }
    @objc private func menuZoomIn() { controller.onZoomIn?() }
    @objc private func menuZoomOut() { controller.onZoomOut?() }
    @objc private func menuZoomReset() { controller.onZoomReset?() }
}

@main
struct RexPreviewMain {
    static func main() {
        guard let options = CLI.parse(CommandLine.arguments) else { exit(2) }
        guard let kind = PreviewKind.classify(options.target) else {
            fputs("rex-preview: file not found: \(options.target)\n", stderr)
            exit(1)
        }

        // Detach by default so the terminal prompt returns immediately.
        if !options.foreground {
            let proc = Process()
            let exeURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
            proc.executableURL = exeURL
            proc.arguments = ["--foreground"] + Array(CommandLine.arguments.dropFirst())
            proc.standardInput = FileHandle.nullDevice
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                exit(0)
            } catch {
                fputs("rex-preview: failed to launch: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        let app = NSApplication.shared
        let delegate = PreviewAppDelegate(options: options, kind: kind)
        app.delegate = delegate
        app.run()
    }
}
