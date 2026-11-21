import Foundation

/// Zero-dependency Markdown to HTML renderer with a crisp dark stylesheet.
enum MarkdownRenderer {
    static func renderHTML(markdown: String, title: String, baseDirectory: URL?) -> String {
        let body = convert(markdown)
        let escapedTitle = escapeHTML(title)
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapedTitle)</title>
        <style>
          :root {
            color-scheme: dark;
            --bg: #141519;
            --surface: #1b1d23;
            --border: rgba(255, 255, 255, 0.10);
            --text: #e6e8ee;
            --muted: #9aa0ae;
            --accent: #6ea8fe;
            --code-bg: #1e2129;
          }
          * { box-sizing: border-box; }
          html, body {
            margin: 0;
            padding: 0;
            background: var(--bg);
            color: var(--text);
            font: 14.5px/1.65 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
            -webkit-font-smoothing: antialiased;
          }
          main {
            max-width: 820px;
            margin: 0 auto;
            padding: 28px 32px 64px;
          }
          h1, h2, h3, h4, h5, h6 {
            margin: 1.5em 0 0.55em;
            line-height: 1.25;
            font-weight: 600;
            letter-spacing: -0.015em;
          }
          h1 { font-size: 1.9em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border); margin-top: 0; }
          h2 { font-size: 1.45em; padding-bottom: 0.25em; border-bottom: 1px solid var(--border); }
          h3 { font-size: 1.18em; }
          p { margin: 0 0 0.95em; }
          a { color: var(--accent); text-decoration: none; }
          a:hover { text-decoration: underline; }
          code {
            font: 12.5px/1.5 ui-monospace, "SF Mono", Menlo, monospace;
            background: var(--code-bg);
            padding: 0.14em 0.4em;
            border-radius: 5px;
            border: 1px solid rgba(255,255,255,0.06);
          }
          pre {
            margin: 0 0 1.1em;
            padding: 14px 16px;
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 8px;
            overflow-x: auto;
          }
          pre code {
            background: none;
            border: none;
            padding: 0;
            font-size: 12.5px;
            line-height: 1.55;
            display: block;
          }
          blockquote {
            margin: 0 0 1em;
            padding: 4px 14px;
            border-left: 3px solid var(--accent);
            color: var(--muted);
            background: rgba(255,255,255,0.02);
            border-radius: 0 6px 6px 0;
          }
          ul, ol { margin: 0 0 1em; padding-left: 1.5em; }
          li { margin: 0.25em 0; }
          hr { border: none; border-top: 1px solid var(--border); margin: 1.8em 0; }
          table {
            width: 100%;
            border-collapse: collapse;
            margin: 0 0 1.2em;
            font-size: 13.5px;
          }
          th, td {
            border: 1px solid var(--border);
            padding: 7px 11px;
            text-align: left;
          }
          th { background: var(--surface); font-weight: 600; }
          tr:nth-child(even) td { background: rgba(255,255,255,0.015); }
          img { max-width: 100%; height: auto; border-radius: 6px; }
        </style>
        </head>
        <body><main>\(body)</main></body>
        </html>
        """
    }

    private static func convert(_ input: String) -> String {
        let lines = input.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                out.append("<pre><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
                continue
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                out.append("<hr>")
                i += 1
                continue
            }

            // ATX heading
            if let (level, text) = parseHeading(trimmed) {
                out.append("<h\(level)>\(renderInline(text))</h\(level)>")
                i += 1
                continue
            }

            // Pipe table
            if line.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                let headers = splitTableRow(line)
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let rowLine = lines[i]
                    if rowLine.trimmingCharacters(in: .whitespaces).isEmpty || !rowLine.contains("|") { break }
                    rows.append(splitTableRow(rowLine))
                    i += 1
                }
                var html = "<table><thead><tr>"
                for h in headers { html += "<th>\(renderInline(h))</th>" }
                html += "</tr></thead><tbody>"
                for r in rows {
                    html += "<tr>"
                    for c in r { html += "<td>\(renderInline(c))</td>" }
                    html += "</tr>"
                }
                html += "</tbody></table>"
                out.append(html)
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if !t.hasPrefix(">") { break }
                    var content = String(t.dropFirst())
                    if content.hasPrefix(" ") { content = String(content.dropFirst()) }
                    quoteLines.append(content)
                    i += 1
                }
                out.append("<blockquote>\(convert(quoteLines.joined(separator: "\n")))</blockquote>")
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isUnorderedListItem(t) else { break }
                    var content = String(t.dropFirst(2))
                    if content.hasPrefix("[ ] ") {
                        content = "☐ " + String(content.dropFirst(4))
                    } else if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
                        content = "☑ " + String(content.dropFirst(4))
                    }
                    items.append("<li>\(renderInline(content))</li>")
                    i += 1
                }
                out.append("<ul>\(items.joined())</ul>")
                continue
            }

            // Ordered list
            if let firstText = parseOrderedListItem(trimmed) {
                var items = ["<li>\(renderInline(firstText))</li>"]
                i += 1
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let text = parseOrderedListItem(t) else { break }
                    items.append("<li>\(renderInline(text))</li>")
                    i += 1
                }
                out.append("<ol>\(items.joined())</ol>")
                continue
            }

            // Paragraph
            var paraLines: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("#") || next.hasPrefix("```") || next.hasPrefix("~~~")
                    || next.hasPrefix(">") || isUnorderedListItem(next) || parseOrderedListItem(next) != nil
                    || isHorizontalRule(next) {
                    break
                }
                paraLines.append(next)
                i += 1
            }
            out.append("<p>\(renderInline(paraLines.joined(separator: " ")))</p>")
        }

        return out.joined(separator: "\n")
    }

    private static func parseHeading(_ line: String) -> (Int, String)? {
        var count = 0
        for ch in line {
            if ch == "#" { count += 1 } else { break }
        }
        guard count >= 1, count <= 6 else { return nil }
        let rest = line.dropFirst(count)
        guard rest.first == " " else { return nil }
        return (count, String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" } || stripped.allSatisfy { $0 == "_" }
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func parseOrderedListItem(_ line: String) -> String? {
        guard let dotIdx = line.firstIndex(of: "."), dotIdx != line.startIndex else { return nil }
        let numPart = line[..<dotIdx]
        guard numPart.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dotIdx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...])
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard stripped.contains("-") && stripped.contains("|") else { return false }
        return stripped.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func renderInline(_ raw: String) -> String {
        var s = escapeHTML(raw)

        // Inline code spans first, protected with placeholders.
        var codeSpans: [String] = []
        s = replaceRegex(s, pattern: #"`([^`]+)`"#) { groups in
            let idx = codeSpans.count
            codeSpans.append("<code>\(groups[1])</code>")
            return "\u{0001}CODE\(idx)\u{0002}"
        }

        // Images ![alt](url)
        s = replaceRegex(s, pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) { g in
            "<img src=\"\(g[2])\" alt=\"\(g[1])\">"
        }
        // Links [text](url)
        s = replaceRegex(s, pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) { g in
            "<a href=\"\(g[2])\">\(g[1])</a>"
        }
        // Bold **text** or __text__
        s = replaceRegex(s, pattern: #"\*\*([^*]+)\*\*"#) { "<strong>\($0[1])</strong>" }
        s = replaceRegex(s, pattern: #"__([^_]+)__"#) { "<strong>\($0[1])</strong>" }
        // Italic *text* or _text_
        s = replaceRegex(s, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#) { "<em>\($0[1])</em>" }
        // Strikethrough ~~text~~
        s = replaceRegex(s, pattern: #"~~([^~]+)~~"#) { "<del>\($0[1])</del>" }

        for (idx, span) in codeSpans.enumerated() {
            s = s.replacingOccurrences(of: "\u{0001}CODE\(idx)\u{0002}", with: span)
        }
        return s
    }

    private static func replaceRegex(_ text: String, pattern: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var result = ""
        var cursor = 0
        for m in matches {
            result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            var groups: [String] = []
            for idx in 0..<m.numberOfRanges {
                let r = m.range(at: idx)
                groups.append(r.location != NSNotFound ? ns.substring(with: r) : "")
            }
            result += transform(groups)
            cursor = m.range.location + m.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
