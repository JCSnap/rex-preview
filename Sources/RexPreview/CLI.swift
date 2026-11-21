import Foundation

enum DockSide: String, CaseIterable {
    case right
    case left
    case center
    case full
}

struct LaunchOptions {
    let target: String
    let side: DockSide
    let widthPercent: CGFloat
    let pinned: Bool
    let wait: Bool
    let foreground: Bool
}

enum CLI {
    static let version = "0.1.0"

    static func parse(_ args: [String]) -> LaunchOptions? {
        var side: DockSide = .right
        var widthPercent: CGFloat = 50
        var pinned = true
        var wait = false
        var foreground = false
        var target: String?

        var i = 1
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "-h", "--help":
                printUsage()
                exit(0)
            case "-v", "--version":
                print("rex-preview \(version)")
                exit(0)
            case "--side", "-s":
                guard i + 1 < args.count, let parsed = DockSide(rawValue: args[i + 1].lowercased()) else {
                    fputs("rex-preview: --side must be one of: right, left, center, full\n", stderr)
                    exit(2)
                }
                side = parsed
                i += 2
            case "--width", "-w":
                guard i + 1 < args.count, let val = Double(args[i + 1]), val >= 20, val <= 100 else {
                    fputs("rex-preview: --width must be a number between 20 and 100\n", stderr)
                    exit(2)
                }
                widthPercent = CGFloat(val)
                i += 2
            case "--no-pin":
                pinned = false
                i += 1
            case "--wait":
                wait = true
                foreground = true
                i += 1
            case "--foreground":
                foreground = true
                i += 1
            default:
                if arg.hasPrefix("-") {
                    fputs("rex-preview: unknown option: \(arg)\n", stderr)
                    exit(2)
                }
                target = arg
                i += 1
            }
        }

        guard let target else {
            printUsage()
            exit(2)
        }

        return LaunchOptions(
            target: target,
            side: side,
            widthPercent: widthPercent,
            pinned: pinned,
            wait: wait,
            foreground: foreground
        )
    }

    static func printUsage() {
        let text = """
        usage: rex-preview [options] <file-or-url>

        Native 120fps macOS preview companion for Rex.
        Renders PDF, HTML, Markdown, CSV, images, video, and Quick Look files
        docked cleanly over Rex's window.

        Options:
          -s, --side <side>     Where to dock: right (default), left, center, full
          -w, --width <pct>     Width percentage of Rex's content area (20-100, default 50)
              --no-pin          Do not float above Rex when unfocused
              --wait            Stay attached to the terminal until closed
          -v, --version         Print version
          -h, --help            Show this help

        Shortcuts inside the preview window:
          Esc / Cmd+W           Close and return focus to Rex
          Cmd+R                 Reload
          Cmd+O                 Open in default macOS app
          Cmd+Plus / Minus / 0  Zoom in / out / reset
        """
        print(text)
    }
}
