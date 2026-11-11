import XCTest
import AppKit
@testable import PotatusHub

final class MenuBarTests: XCTestCase {
    func testSettingsRoundTripDefaultsAndUnknownStrings() {
        let name = "PotatusHubTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.menuBarKinds.isEmpty)

        settings.menuBarKinds = [.disk, .ram]
        XCTAssertEqual(defaults.stringArray(forKey: "PotatusHub.menuBarKinds"), ["ram", "disk"])
        XCTAssertEqual(settings.menuBarKinds, [.ram, .disk])

        defaults.set(["cpu", "bogus", "gpu"], forKey: "PotatusHub.menuBarKinds")
        XCTAssertEqual(settings.menuBarKinds, [.cpu, .gpu])
    }

    func testDisplayItemsOrderAndPlaceholder() {
        let items = MenuBarDisplay.items(
            kinds: [.gpu, .ram, .disk],
            values: [.ram: 62.0, .gpu: nil, .disk: 96.4, .cpu: 10]
        )
        XCTAssertEqual(items, [
            .init(symbol: "memorychip", text: "62%"),
            .init(symbol: "rectangle.3.group", text: "—"),
            .init(symbol: "internaldrive", text: "96%"),
        ])
    }

    func testSamplingPolicy() {
        // Panels visible: always on, as before.
        XCTAssertTrue(SamplingPolicy.shouldSample(panelVisible: true, menuBarKindsSelected: false, displayAwake: false, sessionActive: false))
        // Menu bar only: needs awake display and active session.
        XCTAssertTrue(SamplingPolicy.shouldSample(panelVisible: false, menuBarKindsSelected: true, displayAwake: true, sessionActive: true))
        XCTAssertFalse(SamplingPolicy.shouldSample(panelVisible: false, menuBarKindsSelected: true, displayAwake: false, sessionActive: true))
        XCTAssertFalse(SamplingPolicy.shouldSample(panelVisible: false, menuBarKindsSelected: true, displayAwake: true, sessionActive: false))
        // Nothing to show: off.
        XCTAssertFalse(SamplingPolicy.shouldSample(panelVisible: false, menuBarKindsSelected: false, displayAwake: true, sessionActive: true))
    }

    func testNumberBoxKeepsWidthStableBetweenOneAndTwoDigits() {
        func width(_ text: String) -> CGFloat {
            MenuBarImage.make(items: [.init(symbol: "memorychip", text: text)]).size.width
        }
        XCTAssertEqual(width("7%"), width("62%"))
        XCTAssertEqual(width("—"), width("62%"))
        XCTAssertGreaterThan(width("100%"), width("62%"))
    }

    @MainActor
    func testRenderedImageIsTemplateAndFits() throws {
        let items = MenuBarDisplay.items(kinds: Set(MetricKind.allCases), values: [.ram: 62, .cpu: 7, .gpu: nil, .disk: 100])
        let image = MenuBarImage.make(items: items)
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size.height, 18)
        XCTAssertGreaterThan(image.size.width, 100)

        // Preview PNG for eyeballing (only when asked).
        guard let dir = ProcessInfo.processInfo.environment["MENUBAR_PREVIEW_DIR"] else { return }
        let scale: CGFloat = 6
        let pixelW = Int(image.size.width * scale), pixelH = Int(image.size.height * scale)
        for (name, bg, fg) in [("light", NSColor(white: 0.93, alpha: 1), NSColor.black),
                               ("dark", NSColor(white: 0.15, alpha: 1), NSColor.white)] {
            let rep = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixelW, pixelsHigh: pixelH, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            bg.setFill()
            NSRect(x: 0, y: 0, width: pixelW, height: pixelH).fill()
            let rect = NSRect(x: 0, y: 0, width: pixelW, height: pixelH)
            // Tint: draw template alpha in fg colour.
            let tinted = NSImage(size: rect.size)
            tinted.lockFocus()
            image.draw(in: rect)
            fg.setFill()
            rect.fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("menubar-\(name).png"))
        }
    }
}
