import AppKit

/// What the menu bar shows for the chosen metrics: `[icon] 62%` per item.
enum MenuBarDisplay {
    struct Item: Equatable {
        let symbol: String
        let text: String
    }

    /// Chosen kinds in `MetricKind.allCases` order; "—" when there is no value.
    static func items(kinds: Set<MetricKind>, values: [MetricKind: Double?]) -> [Item] {
        MetricKind.allCases.filter { kinds.contains($0) }.map { kind in
            let text = (values[kind] ?? nil).map { "\(Int($0.rounded()))%" } ?? "—"
            return Item(symbol: kind.symbol, text: text)
        }
    }
}

/// Draws the items into one template image, so the system tints icons and
/// numbers together (light/dark menu bar, highlighted when pressed).
enum MenuBarImage {
    static let height: CGFloat = 18
    private static let fontSize: CGFloat = 12
    private static let iconTextGap: CGFloat = 3
    private static let itemGap: CGFloat = 8
    private static let sidePadding: CGFloat = 2

    static func make(items: [MenuBarDisplay.Item]) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let config = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .medium)

        struct Laid {
            let icon: NSImage?
            let text: NSAttributedString
            let textSize: NSSize
            /// Width of the number box: at least "100%" (values top out at 100),
            /// so 9% <-> 10% <-> 100% never changes the menu bar width.
            let boxWidth: CGFloat
        }
        let minimumWidth = ceil(NSAttributedString(string: "100%", attributes: attributes).size().width)
        let laid = items.map { item -> Laid in
            let icon = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            let text = NSAttributedString(string: item.text, attributes: attributes)
            let size = text.size()
            return Laid(icon: icon, text: text, textSize: size, boxWidth: max(minimumWidth, ceil(size.width)))
        }

        var width = sidePadding * 2
        for (index, entry) in laid.enumerated() {
            if index > 0 { width += itemGap }
            width += (entry.icon?.size.width ?? 0) + iconTextGap + entry.boxWidth
        }

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x = sidePadding
            for (index, entry) in laid.enumerated() {
                if index > 0 { x += itemGap }
                if let icon = entry.icon {
                    let size = icon.size
                    icon.draw(in: NSRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height))
                    x += size.width
                }
                x += iconTextGap
                // Numbers align right in their box; the "—" placeholder centres.
                let slack = entry.boxWidth - ceil(entry.textSize.width)
                let isPlaceholder = !(entry.text.string.last == "%")
                let textX = x + (isPlaceholder ? slack / 2 : slack)
                entry.text.draw(at: NSPoint(x: textX, y: (height - entry.textSize.height) / 2))
                x += entry.boxWidth
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
