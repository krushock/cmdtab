import CoreGraphics

/// Packs windows into rows at a single scale, like Mission Control: every window keeps its
/// proportions, nothing overlaps, and the scale is the largest one that fits.
enum ExposeLayout {
    static func layout(_ windows: [WindowInfo], in area: CGRect, spacing: CGFloat = 28, maxScale: CGFloat = 0.85) -> [CGWindowID: CGRect] {
        guard !windows.isEmpty, area.width > 0, area.height > 0 else { return [:] }
        let n = windows.count
        var bestScale: CGFloat = 0
        var bestRows: [[WindowInfo]] = [windows]

        for rowCount in 1...n {
            let perRow = Int(ceil(Double(n) / Double(rowCount)))
            var rows: [[WindowInfo]] = []
            var i = 0
            while i < n {
                rows.append(Array(windows[i..<min(n, i + perRow)]))
                i += perRow
            }
            let rowHeight = (area.height - spacing * CGFloat(rows.count - 1)) / CGFloat(rows.count)
            var scale = CGFloat.greatestFiniteMagnitude
            for row in rows {
                let sumWidth = row.reduce(0) { $0 + max(1, $1.frame.width) }
                let maxHeight = row.map { max(1, $0.frame.height) }.max() ?? 1
                let availWidth = area.width - spacing * CGFloat(row.count - 1)
                scale = min(scale, availWidth / sumWidth, rowHeight / maxHeight)
            }
            if scale > bestScale {
                bestScale = scale
                bestRows = rows
            }
        }

        let scale = min(bestScale, maxScale)
        let rowHeights = bestRows.map { row in (row.map { max(1, $0.frame.height) }.max() ?? 0) * scale }
        let totalHeight = rowHeights.reduce(0, +) + spacing * CGFloat(bestRows.count - 1)
        var y = area.minY + (area.height - totalHeight) / 2
        var result: [CGWindowID: CGRect] = [:]
        for (r, row) in bestRows.enumerated() {
            let widths = row.map { max(1, $0.frame.width) * scale }
            let totalWidth = widths.reduce(0, +) + spacing * CGFloat(row.count - 1)
            var x = area.minX + (area.width - totalWidth) / 2
            for (c, window) in row.enumerated() {
                let h = max(1, window.frame.height) * scale
                result[window.id] = CGRect(x: x, y: y + (rowHeights[r] - h) / 2, width: widths[c], height: h)
                x += widths[c] + spacing
            }
            y += rowHeights[r] + spacing
        }
        return result
    }
}
