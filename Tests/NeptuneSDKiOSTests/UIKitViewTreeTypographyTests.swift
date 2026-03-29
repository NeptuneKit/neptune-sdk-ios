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

    @Test("Collector captures node constraints from self and superview")
    func collectorCapturesNodeConstraints() throws {
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 180))
        let child = UIView()
        child.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child)

        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            child.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            child.widthAnchor.constraint(equalToConstant: 100),
            child.heightAnchor.constraint(equalToConstant: 44)
        ])

        let childId = NeptuneUIKitViewTreeCollector.buildIdentifier(for: child, fallbackSeed: "child")
        let constraints = try #require(NeptuneUIKitViewTreeCollector.captureConstraints(of: child, viewId: childId))

        #expect(constraints.isEmpty == false)
        #expect(constraints.contains(where: { $0.source == "self" }))
        #expect(constraints.contains(where: { $0.source == "superview" }))
        #expect(constraints.contains(where: { $0.firstAttribute == "leading" || $0.secondAttribute == "leading" }))
    }

    @Test("Collector includes inactive constraints")
    func collectorIncludesInactiveConstraints() throws {
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 180))
        let child = UIView()
        child.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child)

        let active = child.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12)
        let inactive = NSLayoutConstraint(
            item: child,
            attribute: .width,
            relatedBy: .greaterThanOrEqual,
            toItem: nil,
            attribute: .notAnAttribute,
            multiplier: 1,
            constant: 90
        )
        child.addConstraint(inactive)
        inactive.isActive = false
        NSLayoutConstraint.activate([active])

        let childId = NeptuneUIKitViewTreeCollector.buildIdentifier(for: child, fallbackSeed: "child")
        let constraints = try #require(NeptuneUIKitViewTreeCollector.captureConstraints(of: child, viewId: childId))

        #expect(constraints.contains(where: { $0.isActive == true }))
        #expect(
            constraints.contains(where: {
                $0.isActive == false &&
                    $0.firstAttribute == "width" &&
                    $0.relation == "greaterThanOrEqual"
            })
        )
    }

    @Test("Collector captures CALayer nodes under view nodes")
    func collectorCapturesLayerNodes() throws {
        let label = UILabel(frame: .init(x: 12, y: 20, width: 200, height: 28))
        label.text = "discover ok"

        let markerLayer = CALayer()
        markerLayer.frame = CGRect(x: 0, y: 0, width: 120, height: 20)
        markerLayer.backgroundColor = UIColor.red.cgColor
        label.layer.addSublayer(markerLayer)

        let labelId = NeptuneUIKitViewTreeCollector.buildIdentifier(for: label, fallbackSeed: "label")
        let layerNodes = NeptuneUIKitViewTreeCollector.captureLayerNodes(from: label.layer, parentNodeId: labelId)

        #expect(layerNodes.isEmpty == false)
        #expect(layerNodes.contains(where: { $0.name.contains("CALayer") }))
        #expect(layerNodes.contains(where: { $0.parentId == labelId }))
    }

    @Test("Collector includes view-backed sublayers in full layer tree")
    func collectorIncludesViewBackedSublayers() throws {
        let container = UIView(frame: .init(x: 0, y: 0, width: 300, height: 200))
        let child = UIView(frame: .init(x: 12, y: 16, width: 120, height: 40))
        container.addSubview(child)

        let containerId = NeptuneUIKitViewTreeCollector.buildIdentifier(for: container, fallbackSeed: "container")
        let layerNodes = NeptuneUIKitViewTreeCollector.captureLayerNodes(from: container.layer, parentNodeId: containerId)

        #expect(layerNodes.isEmpty == false)
        let childLayerId = "0x\(String(UInt(bitPattern: Unmanaged.passUnretained(child.layer).toOpaque()), radix: 16))"
        let hasChildBackingLayer = layerNodes.contains(where: { node in
            node.children.contains(where: { $0.id == childLayerId })
        })
        #expect(hasChildBackingLayer == true)
    }
}
#endif
