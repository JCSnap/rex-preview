import AVKit
import AppKit
import PDFKit
import QuickLookUI
import SwiftUI
import WebKit

enum PreviewKind {
    case pdf(URL)
    case html(URL)
    case webURL(URL)
    case markdown(URL)
    case csv(URL, delimiter: Character)
    case image(URL)
    case video(URL)
    case quickLook(URL)

    var badge: String {
        switch self {
        case .pdf: "PDF"
        case .html: "HTML"
        case .webURL: "WEB"
        case .markdown: "MD"
        case .csv(_, let d): d == "\t" ? "TSV" : "CSV"
        case .image(let u): u.pathExtension.uppercased()
        case .video(let u): u.pathExtension.uppercased()
        case .quickLook(let u): u.pathExtension.isEmpty ? "FILE" : u.pathExtension.uppercased()
        }
    }

    var title: String {
        switch self {
        case .webURL(let u): u.host ?? u.absoluteString
        case .pdf(let u), .html(let u), .markdown(let u), .csv(let u, _),
             .image(let u), .video(let u), .quickLook(let u):
            u.lastPathComponent
        }
    }

    var fileURL: URL? {
        switch self {
        case .webURL: nil
        case .pdf(let u), .html(let u), .markdown(let u), .csv(let u, _),
             .image(let u), .video(let u), .quickLook(let u):
            u
        }
    }

    var externalURL: URL {
        switch self {
        case .webURL(let u), .pdf(let u), .html(let u), .markdown(let u), .csv(let u, _),
             .image(let u), .video(let u), .quickLook(let u):
            u
        }
    }

    static func classify(_ target: String) -> PreviewKind? {
        if target.hasPrefix("http://") || target.hasPrefix("https://"), let url = URL(string: target) {
            return .webURL(url)
        }
        let url: URL
        if target.hasPrefix("file://"), let parsed = URL(string: target) {
            url = parsed
        } else {
            let expanded = (target as NSString).expandingTildeInPath
            let path = expanded.hasPrefix("/")
                ? expanded
                : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(expanded).standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            url = URL(fileURLWithPath: path)
        }

        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf(url)
        case "html", "htm":
            return .html(url)
        case "md", "markdown", "mdx":
            return .markdown(url)
        case "csv":
            return .csv(url, delimiter: ",")
        case "tsv":
            return .csv(url, delimiter: "\t")
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "bmp", "tiff", "ico":
            return .image(url)
        case "mp4", "mov", "m4v", "webm":
            return .video(url)
        default:
            return .quickLook(url)
        }
    }
}

/// Shared controller so menu/keyboard shortcuts can reload or zoom any active renderer.
@MainActor
final class PreviewController: ObservableObject {
    @Published var reloadToken = 0
    @Published var zoomDelta: Int = 0 // +1 zoom in, -1 zoom out, 0 reset via zoomAction
    var onReload: (() -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onZoomReset: (() -> Void)?

    func reload() {
        reloadToken += 1
        onReload?()
    }
}

struct NativePDFView: NSViewRepresentable {
    let url: URL
    let controller: PreviewController

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.pageBreakMargins = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.backgroundColor = NSColor(red: 0.08, green: 0.085, blue: 0.10, alpha: 1)
        view.document = PDFDocument(url: url)

        controller.onReload = { [weak view] in
            guard let view else { return }
            let pageIndex = view.currentPage.flatMap { view.document?.index(for: $0) }
            let scale = view.scaleFactor
            let auto = view.autoScales
            view.document = PDFDocument(url: url)
            view.autoScales = auto
            if !auto { view.scaleFactor = scale }
            if let pageIndex, let page = view.document?.page(at: pageIndex) {
                view.go(to: page)
            }
        }
        controller.onZoomIn = { [weak view] in
            view?.autoScales = false
            view?.zoomIn(nil)
        }
        controller.onZoomOut = { [weak view] in
            view?.autoScales = false
            view?.zoomOut(nil)
        }
        controller.onZoomReset = { [weak view] in
            view?.autoScales = true
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}

struct NativeWebView: NSViewRepresentable {
    let kind: PreviewKind
    let controller: PreviewController

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = NSColor(red: 0.08, green: 0.085, blue: 0.10, alpha: 1)

        load(into: view)

        controller.onReload = { [weak view] in
            guard let view else { return }
            load(into: view)
        }
        controller.onZoomIn = { [weak view] in
            guard let view else { return }
            view.pageZoom = min(3.0, view.pageZoom + 0.1)
        }
        controller.onZoomOut = { [weak view] in
            guard let view else { return }
            view.pageZoom = max(0.4, view.pageZoom - 0.1)
        }
        controller.onZoomReset = { [weak view] in
            view?.pageZoom = 1.0
        }
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private func load(into view: WKWebView) {
        switch kind {
        case .html(let url):
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        case .webURL(let url):
            view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        case .markdown(let url):
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? "Unable to read \(url.lastPathComponent)"
            let html = MarkdownRenderer.renderHTML(markdown: text, title: url.lastPathComponent, baseDirectory: url.deletingLastPathComponent())
            view.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        case .csv(let url, let delimiter):
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let html = CSVRenderer.renderHTML(content: text, delimiter: delimiter, title: url.lastPathComponent)
            view.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        case .image(let url):
            let escaped = MarkdownRenderer.escapeHTML(url.lastPathComponent)
            let html = """
            <!doctype html>
            <html><head><meta charset="utf-8"><style>
              html, body {
                margin: 0; width: 100%; height: 100%;
                background: #141519;
                display: flex; align-items: center; justify-content: center;
                overflow: auto;
              }
              img {
                max-width: 96vw; max-height: 96vh;
                object-fit: contain;
                border-radius: 4px;
                box-shadow: 0 6px 28px rgba(0,0,0,0.45);
              }
            </style></head>
            <body><img src="\(escaped)" alt="\(escaped)"></body></html>
            """
            view.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        default:
            break
        }
    }
}

struct NativeVideoView: NSViewRepresentable {
    let url: URL
    let controller: PreviewController

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        let player = AVPlayer(url: url)
        view.player = player
        player.play()

        controller.onReload = { [weak view] in
            let next = AVPlayer(url: url)
            view?.player = next
            next.play()
        }
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

struct NativeQuickLookView: NSViewRepresentable {
    let url: URL
    let controller: PreviewController

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        controller.onReload = { [weak view] in
            view?.refreshPreviewItem()
        }
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {}
}
