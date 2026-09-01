import AppKit

/// The standard macOS about panel, filled in from the bundle so the name and
/// version never drift from Info.plist.
enum AboutPanel {
    private static let creator = "bmminky"
    private static let repository = "https://github.com/bmminky/potatus-hub"

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "potatus hub"
    }

    static func show() {
        // An LSUIElement app is not automatically foregrounded when its tray
        // action fires, so bring the standard panel forward explicitly.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .credits: credits,
        ])
    }

    private static var credits: NSAttributedString {
        let body = NSFont.systemFont(ofSize: 11)
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(
            string: L.t(
                ko: "만든 사람  \(creator)\n",
                en: "Created by \(creator)\n",
                ja: "作成者 \(creator)\n",
                zh: "作者 \(creator)\n"
            ),
            attributes: [.font: body, .foregroundColor: NSColor.labelColor]
        ))
        result.append(link("GitHub", url: repository, font: body))

        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineSpacing = 2
        result.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: result.length))
        return result
    }

    private static func link(_ text: String, url: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .link: URL(string: url) as Any,
            .foregroundColor: NSColor.linkColor,
        ])
    }
}
