import Foundation

/// Renders CSV or TSV files into a fast, searchable, sticky-header HTML table.
enum CSVRenderer {
    static func renderHTML(content: String, delimiter: Character, title: String) -> String {
        let rows = parse(content, delimiter: delimiter)
        let header = rows.first ?? []
        let bodyRows = Array(rows.dropFirst().prefix(5000))
        let truncated = rows.count > 5001

        var headerHTML = "<tr>"
        for col in header {
            headerHTML += "<th>\(MarkdownRenderer.escapeHTML(col))</th>"
        }
        headerHTML += "</tr>"

        var bodyHTML = ""
        for row in bodyRows {
            bodyHTML += "<tr>"
            for idx in 0..<max(header.count, row.count) {
                let cell = idx < row.count ? row[idx] : ""
                bodyHTML += "<td>\(MarkdownRenderer.escapeHTML(cell))</td>"
            }
            bodyHTML += "</tr>"
        }

        let note = truncated ? "Showing first 5,000 of \(rows.count - 1) rows" : "\(bodyRows.count) rows · \(header.count) columns"

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(MarkdownRenderer.escapeHTML(title))</title>
        <style>
          :root { color-scheme: dark; }
          * { box-sizing: border-box; }
          html, body {
            margin: 0; padding: 0;
            background: #141519; color: #e6e8ee;
            font: 12.5px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          }
          .bar {
            position: sticky; top: 0; z-index: 3;
            display: flex; align-items: center; gap: 10px;
            padding: 8px 12px;
            background: #1a1c22;
            border-bottom: 1px solid rgba(255,255,255,0.1);
          }
          input {
            flex: 1; max-width: 340px;
            background: #111216; color: #e6e8ee;
            border: 1px solid rgba(255,255,255,0.14);
            border-radius: 6px; padding: 5px 9px; font-size: 12px;
            outline: none;
          }
          input:focus { border-color: #6ea8fe; }
          .meta { color: #8c93a3; font-size: 11.5px; }
          .wrap { overflow: auto; }
          table { width: 100%; border-collapse: collapse; }
          th, td {
            padding: 6px 10px;
            border-bottom: 1px solid rgba(255,255,255,0.07);
            border-right: 1px solid rgba(255,255,255,0.05);
            text-align: left;
            white-space: nowrap;
            max-width: 360px;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          th {
            position: sticky; top: 0; z-index: 2;
            background: #1e2129; font-weight: 600; color: #d5dae5;
          }
          tr:nth-child(even) td { background: rgba(255,255,255,0.015); }
          tr:hover td { background: rgba(110,168,254,0.08); }
        </style>
        </head>
        <body>
          <div class="bar">
            <input id="q" type="search" placeholder="Filter rows..." autofocus>
            <span class="meta" id="meta">\(note)</span>
          </div>
          <div class="wrap">
            <table><thead>\(headerHTML)</thead><tbody id="tb">\(bodyHTML)</tbody></table>
          </div>
          <script>
            const q = document.getElementById('q');
            const tb = document.getElementById('tb');
            const meta = document.getElementById('meta');
            const rows = Array.from(tb.querySelectorAll('tr'));
            q.addEventListener('input', () => {
              const needle = q.value.trim().toLowerCase();
              let shown = 0;
              for (const tr of rows) {
                const ok = !needle || tr.textContent.toLowerCase().includes(needle);
                tr.style.display = ok ? '' : 'none';
                if (ok) shown++;
              }
              meta.textContent = needle ? `${shown} / ${rows.length} rows` : `\(note)`;
            });
          </script>
        </body>
        </html>
        """
    }

    private static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delimiter {
                row.append(field)
                field = ""
            } else if c == "\r" {
                // skip CR
            } else if c == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
