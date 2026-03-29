import Foundation
import Testing
@testable import NeptuneSDKiOS

@Suite("NeptuneSDKiOS View Tree Typography")
struct ViewTreeTypographyTests {
    @Test("Style codable round-trips typography metadata")
    func styleCodableRoundTripsTypographyMetadata() throws {
        let style = NeptuneViewTreeNode.Style(
            typographyUnit: "dp",
            sourceTypographyUnit: "pt",
            platformFontScale: 1.25,
            opacity: 0.8,
            backgroundColor: "#FFFFFF",
            textColor: "#111111",
            fontSize: 17,
            lineHeight: 20,
            letterSpacing: 0.25,
            fontWeight: "semibold",
            fontWeightRaw: "0.4",
            borderRadius: 6,
            borderWidth: 1,
            borderColor: "#000000",
            zIndex: 1,
            textAlign: "center"
        )

        let encoded = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(NeptuneViewTreeNode.Style.self, from: encoded)

        #expect(decoded == style)
        #expect(decoded.typographyUnit == "dp")
        #expect(decoded.sourceTypographyUnit == "pt")
        #expect(decoded.platformFontScale == 1.25)
        #expect(decoded.fontSize == 17)
        #expect(decoded.lineHeight == 20)
        #expect(decoded.letterSpacing == 0.25)
        #expect(decoded.fontWeightRaw == "0.4")
    }

    @Test("Inspector style attrs expose typography metadata")
    func inspectorStyleAttributesExposeTypographyMetadata() {
        let style = NeptuneViewTreeNode.Style(
            typographyUnit: "dp",
            sourceTypographyUnit: "pt",
            platformFontScale: 1.25,
            fontSize: 17,
            lineHeight: 20,
            letterSpacing: 0.25,
            fontWeightRaw: "0.4"
        )

        let attributes = makeNeptuneInspectorStyleAttributes(from: style)

        #expect(attributes["typographyUnit"] == .string("dp"))
        #expect(attributes["sourceTypographyUnit"] == .string("pt"))
        #expect(attributes["platformFontScale"] == .number(1.25))
        #expect(attributes["fontSize"] == .number(17))
        #expect(attributes["lineHeight"] == .number(20))
        #expect(attributes["letterSpacing"] == .number(0.25))
        #expect(attributes["fontWeightRaw"] == .string("0.4"))
    }
}
