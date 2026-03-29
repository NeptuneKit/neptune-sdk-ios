#if canImport(UIKit)
import Foundation
import Testing
import UIKit
@testable import NeptuneSDKiOS

@Suite("NeptuneSDKiOS UIKit View Tree Typography")
@MainActor
struct UIKitViewTreeTypographyTests {
    @Test("Collector extracts typography source metadata from UILabel")
    func collectorExtractsTypographySourceMetadataFromLabel() throws {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17, weight: .bold)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = 22

        label.attributedText = NSAttributedString(
            string: "Hello Neptune",
            attributes: [
                .paragraphStyle: paragraphStyle,
                .kern: 0.75
            ]
        )

        let style = try #require(NeptuneUIKitViewTreeCollector.captureStyle(of: label))

        #expect(style.typographyUnit == "dp")
        #expect(style.sourceTypographyUnit == "pt")
        #expect(style.platformFontScale != nil)
        #expect(style.fontSize == 17)
        #expect(style.lineHeight == 22)
        #expect(style.letterSpacing == 0.75)
        #expect(style.fontWeight != nil)
        #expect(style.fontWeightRaw != nil)
        #expect(style.fontWeightRaw?.isEmpty == false)
    }

    @Test("Collector node id uses memory address")
    func collectorNodeIdentifierUsesMemoryAddress() {
        let view = UIView()
        let identifier = NeptuneUIKitViewTreeCollector.buildIdentifier(for: view, fallbackSeed: "fallback")
        let rawAddress = String(UInt(bitPattern: Unmanaged.passUnretained(view).toOpaque()), radix: 16)

        #expect(identifier == "0x\(rawAddress)")
        #expect(identifier.contains("|") == false)
    }

    @Test("Collector does not export UIButton text")
    func collectorDoesNotExportUIButtonText() {
        let button = UIButton(type: .system)
        button.setTitle("Refresh", for: .normal)
        button.accessibilityLabel = "Refresh Button"

        #expect(NeptuneUIKitViewTreeCollector.captureText(of: button) == nil)
    }

    @Test("Collector extracts UIButton configuration style")
    func collectorExtractsUIButtonConfigurationStyle() throws {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 180, height: 44)
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = UIColor(red: 0.46, green: 0.83, blue: 0.97, alpha: 1)
        configuration.cornerStyle = .capsule
        button.configuration = configuration

        let style = try #require(NeptuneUIKitViewTreeCollector.captureStyle(of: button))
        #expect(style.backgroundColor == "#75D4F7FF")
        #expect(style.borderRadius != nil)
        #expect((style.borderRadius ?? 0) > 0)
        #expect(style.textAlign == "center")
    }
}
#endif
