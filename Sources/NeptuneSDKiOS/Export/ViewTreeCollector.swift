import Foundation

#if canImport(UIKit)
import UIKit
#endif

public protocol NeptuneViewTreeCollecting: Sendable {
    func captureViewTreeSnapshot(platform: String) async -> NeptuneViewTreeSnapshot
    func captureInspectorSnapshot(platform: String) async -> InspectorSnapshot
}

fileprivate func makeNeptuneViewTreeSnapshotId(prefix: String) -> String {
    "\(prefix)-\(Int(Date().timeIntervalSince1970 * 1000))"
}

fileprivate func makeNeptuneViewTreeTimestampString() -> String {
    ISO8601DateFormatter().string(from: Date())
}

fileprivate func normalizeNeptuneViewTreeText(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

struct NeptuneTypographyMetrics: Sendable, Equatable {
    let typographyUnit: String
    let sourceTypographyUnit: String
    let platformFontScale: Double
    let fontSize: Double?
    let lineHeight: Double?
    let letterSpacing: Double?
    let fontWeightRaw: String?
}

func makeNeptuneInspectorStyleAttributes(
    from style: NeptuneViewTreeNode.Style
) -> [String: InspectorPayloadValue] {
    var attributes: [String: InspectorPayloadValue] = [:]
    if let typographyUnit = style.typographyUnit {
        attributes["typographyUnit"] = .string(typographyUnit)
    }
    if let sourceTypographyUnit = style.sourceTypographyUnit {
        attributes["sourceTypographyUnit"] = .string(sourceTypographyUnit)
    }
    if let platformFontScale = style.platformFontScale {
        attributes["platformFontScale"] = .number(platformFontScale)
    }
    if let opacity = style.opacity {
        attributes["opacity"] = .number(opacity)
    }
    if let backgroundColor = style.backgroundColor {
        attributes["backgroundColor"] = .string(backgroundColor)
    }
    if let textColor = style.textColor {
        attributes["textColor"] = .string(textColor)
    }
    if let fontSize = style.fontSize {
        attributes["fontSize"] = .number(fontSize)
    }
    if let lineHeight = style.lineHeight {
        attributes["lineHeight"] = .number(lineHeight)
    }
    if let letterSpacing = style.letterSpacing {
        attributes["letterSpacing"] = .number(letterSpacing)
    }
    if let fontWeight = style.fontWeight {
        attributes["fontWeight"] = .string(fontWeight)
    }
    if let fontWeightRaw = style.fontWeightRaw {
        attributes["fontWeightRaw"] = .string(fontWeightRaw)
    }
    if let borderRadius = style.borderRadius {
        attributes["borderRadius"] = .number(borderRadius)
    }
    if let borderWidth = style.borderWidth {
        attributes["borderWidth"] = .number(borderWidth)
    }
    if let borderColor = style.borderColor {
        attributes["borderColor"] = .string(borderColor)
    }
    if let zIndex = style.zIndex {
        attributes["zIndex"] = .number(zIndex)
    }
    if let textAlign = style.textAlign {
        attributes["textAlign"] = .string(textAlign)
    }
    return attributes
}

public struct NeptuneFallbackViewTreeCollector: NeptuneViewTreeCollecting {
    public init() {}

    public func captureViewTreeSnapshot(platform: String) async -> NeptuneViewTreeSnapshot {
        NeptuneViewTreeSnapshot(
            snapshotId: makeNeptuneViewTreeSnapshotId(prefix: "ios-ui-tree"),
            capturedAt: makeNeptuneViewTreeTimestampString(),
            platform: platform,
            roots: []
        )
    }

    public func captureInspectorSnapshot(platform: String) async -> InspectorSnapshot {
        InspectorSnapshot(
            snapshotId: makeNeptuneViewTreeSnapshotId(prefix: "ios-inspector"),
            capturedAt: makeNeptuneViewTreeTimestampString(),
            platform: platform,
            available: false,
            payload: nil,
            reason: "UIKit unavailable."
        )
    }
}

#if canImport(UIKit)
@MainActor
public final class NeptuneUIKitViewTreeCollector: NeptuneViewTreeCollecting {
    public init() {}

    public func captureViewTreeSnapshot(platform: String) async -> NeptuneViewTreeSnapshot {
        let roots = captureWindowRoots().enumerated().map { index, window in
            captureNode(from: window, parentId: nil, fallbackSeed: "window-\(index)")
        }
        return NeptuneViewTreeSnapshot(
            snapshotId: makeNeptuneViewTreeSnapshotId(prefix: "ios-ui-tree"),
            capturedAt: makeNeptuneViewTreeTimestampString(),
            platform: platform,
            roots: roots.map(\.viewTreeNode)
        )
    }

    public func captureInspectorSnapshot(platform: String) async -> InspectorSnapshot {
        let roots = captureWindowRoots().enumerated().map { index, window in
            captureNode(from: window, parentId: nil, fallbackSeed: "window-\(index)")
        }
        return InspectorSnapshot(
            snapshotId: makeNeptuneViewTreeSnapshotId(prefix: "ios-inspector"),
            capturedAt: makeNeptuneViewTreeTimestampString(),
            platform: platform,
            available: true,
            payload: .object([
                "roots": .array(roots.map(\.inspectorPayload))
            ]),
            reason: nil
        )
    }

    private func captureWindowRoots() -> [UIWindow] {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows
            .filter { window in
                window.windowScene != nil && !window.isHidden && window.alpha > 0
            }
            .sorted(by: Self.compareWindows(_:_:))
    }

    private func captureNode(
        from view: UIView,
        parentId: String?,
        fallbackSeed: String
    ) -> NeptuneViewTreeCaptureNode {
        let id = Self.buildIdentifier(for: view, fallbackSeed: fallbackSeed)
        let frame = Self.captureFrame(of: view)
        let style = Self.captureStyle(of: view)
        let constraints = Self.captureConstraints(of: view, viewId: id)
        let text = Self.captureText(of: view)
        let visible = Self.isVisible(view)
        let viewChildren = view.subviews.enumerated().map { index, child in
            captureNode(from: child, parentId: id, fallbackSeed: "\(fallbackSeed)-\(index)")
        }
        let layerChildren = Self.captureLayerNodes(from: view.layer, parentNodeId: id)
        let children = viewChildren + layerChildren
        return NeptuneViewTreeCaptureNode(
            id: id,
            parentId: parentId,
            name: String(describing: type(of: view)),
            className: String(describing: type(of: view)),
            frame: frame,
            style: style,
            constraints: constraints,
            text: text,
            visible: visible,
            rawAttributes: Self.captureRawAttributes(
                of: view,
                id: id,
                frame: frame,
                style: style,
                constraints: constraints,
                text: text,
                visible: visible
            ),
            children: children
        )
    }

    private static func compareWindows(_ lhs: UIWindow, _ rhs: UIWindow) -> Bool {
        if lhs.isKeyWindow != rhs.isKeyWindow {
            return lhs.isKeyWindow && !rhs.isKeyWindow
        }
        if lhs.windowLevel != rhs.windowLevel {
            return lhs.windowLevel > rhs.windowLevel
        }
        let lhsAddress = UInt(bitPattern: Unmanaged.passUnretained(lhs).toOpaque())
        let rhsAddress = UInt(bitPattern: Unmanaged.passUnretained(rhs).toOpaque())
        return lhsAddress < rhsAddress
    }

    static func buildIdentifier(for view: UIView, fallbackSeed _: String) -> String {
        let memoryAddress = String(UInt(bitPattern: Unmanaged.passUnretained(view).toOpaque()), radix: 16)
        return "0x\(memoryAddress)"
    }

    static func captureLayerNodes(
        from layer: CALayer,
        parentNodeId: String
    ) -> [NeptuneViewTreeCaptureNode] {
        guard let layerNode = captureLayerNode(
            layer,
            parentNodeId: parentNodeId
        ) else {
            return []
        }
        return [layerNode]
    }

    private static func captureLayerNode(
        _ layer: CALayer,
        parentNodeId: String
    ) -> NeptuneViewTreeCaptureNode? {
        let layerId = buildLayerIdentifier(for: layer)
        let frame = captureFrame(of: layer)
        let style = captureStyle(of: layer)
        let text = captureText(of: layer)
        let visible = isVisible(layer)

        let children = (layer.sublayers ?? []).compactMap { child in
            captureLayerNode(
                child,
                parentNodeId: layerId
            )
        }

        return NeptuneViewTreeCaptureNode(
            id: layerId,
            parentId: parentNodeId,
            name: String(describing: type(of: layer)),
            className: String(describing: type(of: layer)),
            frame: frame,
            style: style,
            constraints: nil,
            text: text,
            visible: visible,
            rawAttributes: captureRawAttributes(of: layer, id: layerId, frame: frame, style: style, text: text, visible: visible),
            children: children
        )
    }

    private static func buildLayerIdentifier(for layer: CALayer) -> String {
        let memoryAddress = String(UInt(bitPattern: Unmanaged.passUnretained(layer).toOpaque()), radix: 16)
        return "0x\(memoryAddress)"
    }

    private static func captureFrame(of layer: CALayer) -> NeptuneViewTreeNode.Frame? {
        let rect = layer.convert(layer.bounds, to: nil)
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite else {
            return nil
        }
        return NeptuneViewTreeNode.Frame(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }

    private static func captureStyle(of layer: CALayer) -> NeptuneViewTreeNode.Style? {
        let backgroundColor = layer.backgroundColor.flatMap { Self.colorHexString(UIColor(cgColor: $0)) }
        let borderColor = layer.borderColor.flatMap { Self.colorHexString(UIColor(cgColor: $0)) }
        let style = NeptuneViewTreeNode.Style(
            opacity: Double(layer.opacity),
            backgroundColor: backgroundColor,
            borderRadius: Double(layer.cornerRadius),
            borderWidth: Double(layer.borderWidth),
            borderColor: borderColor,
            zIndex: Double(layer.zPosition)
        )
        if style.opacity == nil &&
            style.backgroundColor == nil &&
            style.borderRadius == nil &&
            style.borderWidth == nil &&
            style.borderColor == nil &&
            style.zIndex == nil {
            return nil
        }
        return style
    }

    private static func captureText(of layer: CALayer) -> String? {
        if let textLayer = layer as? CATextLayer {
            if let text = textLayer.string as? String {
                return normalizeNeptuneViewTreeText(text)
            }
            if let attributed = textLayer.string as? NSAttributedString {
                return normalizeNeptuneViewTreeText(attributed.string)
            }
        }
        return nil
    }

    private static func isVisible(_ layer: CALayer) -> Bool {
        guard !layer.isHidden, layer.opacity > 0 else {
            return false
        }
        let frame = layer.convert(layer.bounds, to: nil)
        return frame.width > 0 && frame.height > 0
    }

    private static func captureFrame(of view: UIView) -> NeptuneViewTreeNode.Frame? {
        let rect = view.convert(view.bounds, to: nil)
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.size.width.isFinite,
              rect.size.height.isFinite else {
            return nil
        }
        return NeptuneViewTreeNode.Frame(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }

    static func captureStyle(of view: UIView) -> NeptuneViewTreeNode.Style? {
        let backgroundColor = Self.resolveBackgroundColor(from: view)
            .flatMap { Self.colorHexString($0.resolvedColor(with: view.traitCollection)) }
        let opacity = Double(view.alpha)
        let borderColor = view.layer.borderColor.flatMap { Self.colorHexString(UIColor(cgColor: $0)) }
        let typography = Self.captureTypography(from: view)
        let font = Self.resolveFont(from: view)
        let textColor = Self.resolveTextColor(from: view)
        let textAlign = Self.resolveTextAlignment(from: view)
        let style = NeptuneViewTreeNode.Style(
            typographyUnit: typography.map(\.typographyUnit),
            sourceTypographyUnit: typography.map(\.sourceTypographyUnit),
            platformFontScale: typography?.platformFontScale,
            opacity: opacity,
            backgroundColor: backgroundColor,
            textColor: textColor.flatMap { Self.colorHexString($0.resolvedColor(with: view.traitCollection)) },
            fontSize: typography?.fontSize,
            lineHeight: typography?.lineHeight,
            letterSpacing: typography?.letterSpacing,
            fontWeight: font.flatMap(Self.fontWeightString(from:)),
            fontWeightRaw: typography?.fontWeightRaw,
            borderRadius: Self.resolveBorderRadius(from: view),
            borderWidth: Double(view.layer.borderWidth),
            borderColor: borderColor,
            zIndex: Double(view.layer.zPosition),
            textAlign: textAlign
        )

        if style.opacity == nil &&
            style.backgroundColor == nil &&
            style.textColor == nil &&
            style.fontSize == nil &&
            style.lineHeight == nil &&
            style.letterSpacing == nil &&
            style.fontWeight == nil &&
            style.borderRadius == nil &&
            style.borderWidth == nil &&
            style.borderColor == nil &&
            style.zIndex == nil &&
            style.textAlign == nil {
            return nil
        }
        return style
    }

    static func captureText(of view: UIView) -> String? {
        if let label = view as? UILabel {
            return normalizeNeptuneViewTreeText(label.text) ?? normalizeNeptuneViewTreeText(label.attributedText?.string) ?? normalizeNeptuneViewTreeText(label.accessibilityLabel)
        }
        if view is UIButton {
            return nil
        }
        if let textField = view as? UITextField {
            return normalizeNeptuneViewTreeText(textField.text) ?? normalizeNeptuneViewTreeText(textField.placeholder) ?? normalizeNeptuneViewTreeText(textField.accessibilityLabel)
        }
        if let textView = view as? UITextView {
            return normalizeNeptuneViewTreeText(textView.text) ?? normalizeNeptuneViewTreeText(textView.accessibilityLabel)
        }
        return normalizeNeptuneViewTreeText(view.accessibilityLabel)
    }

    private static func isVisible(_ view: UIView) -> Bool {
        guard !view.isHidden, view.alpha > 0 else {
            return false
        }
        let frame = view.convert(view.bounds, to: nil)
        return frame.width > 0 && frame.height > 0
    }

    private static func captureRawAttributes(
        of view: UIView,
        id: String,
        frame: NeptuneViewTreeNode.Frame?,
        style: NeptuneViewTreeNode.Style?,
        constraints: [NeptuneViewTreeNode.Constraint]?,
        text: String?,
        visible: Bool
    ) -> [String: InspectorPayloadValue] {
        var attributes: [String: InspectorPayloadValue] = [
            "id": .string(id),
            "className": .string(String(describing: type(of: view))),
            "name": .string(String(describing: type(of: view))),
            "hidden": .bool(view.isHidden),
            "alpha": .number(Double(view.alpha)),
            "isUserInteractionEnabled": .bool(view.isUserInteractionEnabled),
            "visible": .bool(visible),
            "children": .array([])
        ]

        if let accessibilityIdentifier = normalizeNeptuneViewTreeText(view.accessibilityIdentifier) {
            attributes["accessibilityIdentifier"] = .string(accessibilityIdentifier)
        }
        if let accessibilityLabel = normalizeNeptuneViewTreeText(view.accessibilityLabel) {
            attributes["accessibilityLabel"] = .string(accessibilityLabel)
        }
        if let frame {
            attributes["frame"] = .object([
                "x": .number(frame.x),
                "y": .number(frame.y),
                "width": .number(frame.width),
                "height": .number(frame.height)
            ])
        }
        if let style {
            attributes["style"] = .object(makeNeptuneInspectorStyleAttributes(from: style))
        }
        if let constraints {
            attributes["constraints"] = .array(constraints.map(makeNeptuneInspectorConstraintPayload(from:)))
        }
        if let text {
            attributes["text"] = .string(text)
        }
        if let window = view as? UIWindow {
            attributes["windowLevel"] = .number(Double(window.windowLevel.rawValue))
            attributes["isKeyWindow"] = .bool(window.isKeyWindow)
        }
        return attributes
    }

    private static func captureRawAttributes(
        of layer: CALayer,
        id: String,
        frame: NeptuneViewTreeNode.Frame?,
        style: NeptuneViewTreeNode.Style?,
        text: String?,
        visible: Bool
    ) -> [String: InspectorPayloadValue] {
        var attributes: [String: InspectorPayloadValue] = [
            "id": .string(id),
            "className": .string(String(describing: type(of: layer))),
            "name": .string(String(describing: type(of: layer))),
            "hidden": .bool(layer.isHidden),
            "alpha": .number(Double(layer.opacity)),
            "visible": .bool(visible),
            "children": .array([])
        ]

        if let frame {
            attributes["frame"] = .object([
                "x": .number(frame.x),
                "y": .number(frame.y),
                "width": .number(frame.width),
                "height": .number(frame.height)
            ])
        }
        if let style {
            attributes["style"] = .object(makeNeptuneInspectorStyleAttributes(from: style))
        }
        if let text {
            attributes["text"] = .string(text)
        }
        return attributes
    }

    static func captureConstraints(of view: UIView, viewId: String) -> [NeptuneViewTreeNode.Constraint]? {
        var captured: [NeptuneViewTreeNode.Constraint] = []
        var seenConstraintIDs = Set<ObjectIdentifier>()

        for constraint in view.constraints {
            let objectID = ObjectIdentifier(constraint)
            guard seenConstraintIDs.insert(objectID).inserted else { continue }
            captured.append(makeConstraint(constraint, source: "self", view: view, viewId: viewId))
        }

        var ancestor = view.superview
        var depth = 1
        while let current = ancestor {
            for constraint in current.constraints where constraintInvolvesView(constraint, view: view) {
                let objectID = ObjectIdentifier(constraint)
                guard seenConstraintIDs.insert(objectID).inserted else { continue }
                let source = depth == 1 ? "superview" : "ancestor-\(depth)"
                captured.append(makeConstraint(constraint, source: source, view: view, viewId: viewId))
            }
            ancestor = current.superview
            depth += 1
        }

        return captured.isEmpty ? nil : captured
    }

    private static func constraintInvolvesView(_ constraint: NSLayoutConstraint, view: UIView) -> Bool {
        let firstItem = constraint.firstItem as AnyObject?
        let secondItem = constraint.secondItem as AnyObject?
        return firstItem === view || secondItem === view
    }

    private static func makeConstraint(
        _ constraint: NSLayoutConstraint,
        source: String,
        view: UIView,
        viewId: String
    ) -> NeptuneViewTreeNode.Constraint {
        let pointer = String(UInt(bitPattern: Unmanaged.passUnretained(constraint).toOpaque()), radix: 16)
        return NeptuneViewTreeNode.Constraint(
            id: "0x\(pointer)",
            source: source,
            relation: relationString(constraint.relation),
            firstAttribute: attributeString(constraint.firstAttribute),
            secondAttribute: constraint.secondItem == nil ? nil : attributeString(constraint.secondAttribute),
            firstItem: constraintItemString(constraint.firstItem, ownerView: view, ownerViewId: viewId),
            secondItem: constraintItemString(constraint.secondItem, ownerView: view, ownerViewId: viewId),
            constant: Double(constraint.constant),
            multiplier: Double(constraint.multiplier),
            priority: Double(constraint.priority.rawValue),
            isActive: constraint.isActive
        )
    }

    private static func relationString(_ relation: NSLayoutConstraint.Relation) -> String {
        switch relation {
        case .equal:
            return "equal"
        case .lessThanOrEqual:
            return "lessThanOrEqual"
        case .greaterThanOrEqual:
            return "greaterThanOrEqual"
        @unknown default:
            return "unknown"
        }
    }

    private static func attributeString(_ attribute: NSLayoutConstraint.Attribute) -> String {
        switch attribute {
        case .left:
            return "left"
        case .right:
            return "right"
        case .top:
            return "top"
        case .bottom:
            return "bottom"
        case .leading:
            return "leading"
        case .trailing:
            return "trailing"
        case .width:
            return "width"
        case .height:
            return "height"
        case .centerX:
            return "centerX"
        case .centerY:
            return "centerY"
        case .lastBaseline:
            return "lastBaseline"
        case .firstBaseline:
            return "firstBaseline"
        case .leftMargin:
            return "leftMargin"
        case .rightMargin:
            return "rightMargin"
        case .topMargin:
            return "topMargin"
        case .bottomMargin:
            return "bottomMargin"
        case .leadingMargin:
            return "leadingMargin"
        case .trailingMargin:
            return "trailingMargin"
        case .centerXWithinMargins:
            return "centerXWithinMargins"
        case .centerYWithinMargins:
            return "centerYWithinMargins"
        case .notAnAttribute:
            return "notAnAttribute"
        @unknown default:
            return "unknown"
        }
    }

    private static func constraintItemString(_ item: AnyObject?, ownerView: UIView, ownerViewId: String) -> String? {
        guard let item else { return nil }
        if let itemView = item as? UIView {
            if itemView === ownerView {
                return ownerViewId
            }
            return buildIdentifier(for: itemView, fallbackSeed: "constraint-item")
        }
        if let itemGuide = item as? UILayoutGuide {
            let pointer = String(UInt(bitPattern: Unmanaged.passUnretained(itemGuide).toOpaque()), radix: 16)
            return "\(String(describing: type(of: itemGuide)))@0x\(pointer)"
        }
        let pointer = String(UInt(bitPattern: Unmanaged.passUnretained(item).toOpaque()), radix: 16)
        return "\(String(describing: type(of: item)))@0x\(pointer)"
    }

    private static func resolveTextColor(from view: UIView) -> UIColor? {
        if let label = view as? UILabel {
            return label.textColor
        }
        if let button = view as? UIButton {
            return button.titleLabel?.textColor
        }
        if let textField = view as? UITextField {
            return textField.textColor
        }
        if let textView = view as? UITextView {
            return textView.textColor
        }
        return nil
    }

    private static func resolveFont(from view: UIView) -> UIFont? {
        if let label = view as? UILabel {
            return label.font
        }
        if let button = view as? UIButton {
            return button.titleLabel?.font
        }
        if let textField = view as? UITextField {
            return textField.font
        }
        if let textView = view as? UITextView {
            return textView.font
        }
        if let attributedText = resolveTypographyAttributedString(from: view),
           let font = attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
            return font
        }
        return nil
    }

    private static func resolveTextAlignment(from view: UIView) -> String? {
        let alignment: NSTextAlignment?
        if let label = view as? UILabel {
            alignment = label.textAlignment
        } else if let textField = view as? UITextField {
            alignment = textField.textAlignment
        } else if let textView = view as? UITextView {
            alignment = textView.textAlignment
        } else if let button = view as? UIButton {
            if button.contentHorizontalAlignment == .center {
                return "center"
            }
            alignment = button.titleLabel?.textAlignment
        } else {
            alignment = nil
        }
        guard let alignment else {
            return nil
        }
        switch alignment {
        case .left:
            return "left"
        case .center:
            return "center"
        case .right:
            return "right"
        case .justified:
            return "justified"
        case .natural:
            return "natural"
        @unknown default:
            return nil
        }
    }

    private static func resolveBackgroundColor(from view: UIView) -> UIColor? {
        if let button = view as? UIButton {
            if let color = button.configuration?.baseBackgroundColor {
                return color
            }
            if let color = button.configuration?.background.backgroundColor {
                return color
            }
        }
        return view.backgroundColor
    }

    private static func resolveBorderRadius(from view: UIView) -> Double {
        let measuredHeight = max(Double(view.bounds.height), Double(view.frame.height))
        if let button = view as? UIButton, let configuration = button.configuration {
            switch configuration.cornerStyle {
            case .capsule:
                let inferredCapsule = measuredHeight > 0 ? measuredHeight / 2 : 0
                return max(inferredCapsule, Double(button.layer.cornerRadius))
            case .large:
                return max(14, Double(button.layer.cornerRadius))
            case .medium:
                return max(10, Double(button.layer.cornerRadius))
            case .small:
                return max(8, Double(button.layer.cornerRadius))
            case .fixed:
                let hasBackground =
                    (button.configuration?.baseBackgroundColor != nil) ||
                    (button.configuration?.background.backgroundColor != nil) ||
                    (button.backgroundColor != nil)
                if hasBackground, button.layer.cornerRadius <= 0, measuredHeight > 0 {
                    return measuredHeight / 2
                }
                return Double(button.layer.cornerRadius)
            @unknown default:
                return Double(button.layer.cornerRadius)
            }
        }
        if view is UIButton, measuredHeight > 0, view.layer.cornerRadius <= 0 {
            return measuredHeight / 2
        }
        return Double(view.layer.cornerRadius)
    }

    private static func captureTypography(from view: UIView) -> NeptuneTypographyMetrics? {
        let attributedText = resolveTypographyAttributedString(from: view)
        let font = resolveFont(from: view)

        let fontSize = font.map { Double($0.pointSize) }
        let lineHeight = resolveLineHeight(from: attributedText, font: font)
        let letterSpacing = resolveLetterSpacing(from: attributedText)
        let platformFontScale = resolvePlatformFontScale()
        let fontWeightRaw = font.flatMap(Self.fontWeightRawString(from:))

        guard fontSize != nil || lineHeight != nil || letterSpacing != nil else {
            return nil
        }

        return NeptuneTypographyMetrics(
            typographyUnit: "dp",
            sourceTypographyUnit: "pt",
            platformFontScale: platformFontScale,
            fontSize: fontSize,
            lineHeight: lineHeight,
            letterSpacing: letterSpacing,
            fontWeightRaw: fontWeightRaw
        )
    }

    private static func resolveTypographyAttributedString(from view: UIView) -> NSAttributedString? {
        if let label = view as? UILabel {
            return label.attributedText
        }
        if let button = view as? UIButton {
            return button.titleLabel?.attributedText ?? button.attributedTitle(for: .normal)
        }
        if let textField = view as? UITextField {
            return textField.attributedText ?? textField.attributedPlaceholder
        }
        if let textView = view as? UITextView {
            return textView.attributedText
        }
        return nil
    }

    private static func resolveLineHeight(from attributedText: NSAttributedString?, font: UIFont?) -> Double? {
        if let attributedText, attributedText.length > 0 {
            let attributes = attributedText.attributes(at: 0, effectiveRange: nil)
            if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
                if paragraphStyle.minimumLineHeight > 0 {
                    return Double(paragraphStyle.minimumLineHeight)
                }
                if paragraphStyle.maximumLineHeight > 0 {
                    return Double(paragraphStyle.maximumLineHeight)
                }
                if paragraphStyle.lineHeightMultiple != 1, let font {
                    return Double(font.lineHeight * paragraphStyle.lineHeightMultiple)
                }
            }
        }

        guard let font else {
            return nil
        }
        return Double(font.lineHeight)
    }

    private static func resolveLetterSpacing(from attributedText: NSAttributedString?) -> Double? {
        guard let attributedText, attributedText.length > 0 else {
            return nil
        }

        let attributes = attributedText.attributes(at: 0, effectiveRange: nil)
        guard let kern = attributes[.kern] else {
            return nil
        }

        if let value = kern as? NSNumber {
            return value.doubleValue
        }
        if let value = kern as? CGFloat {
            return Double(value)
        }
        return nil
    }

    private static func colorHexString(_ color: UIColor) -> String? {
        let resolvedColor = color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return String(
            format: "#%02lX%02lX%02lX%02lX",
            lround(Double(red * 255)),
            lround(Double(green * 255)),
            lround(Double(blue * 255)),
            lround(Double(alpha * 255))
        )
    }

    private static func resolvePlatformFontScale() -> Double {
        let scale = UIFontMetrics.default.scaledValue(for: 1)
        guard scale.isFinite, scale > 0 else {
            return 1
        }
        return Double(scale)
    }

    private static func fontWeightString(from font: UIFont) -> String? {
        guard let weight = fontWeightValue(from: font) else {
            return font.fontDescriptor.symbolicTraits.contains(.traitBold) ? "bold" : nil
        }
        switch weight {
        case ..<(-0.8):
            return "ultraLight"
        case ..<(-0.4):
            return "thin"
        case ..<(-0.2):
            return "light"
        case ..<0.2:
            return "regular"
        case ..<0.4:
            return "medium"
        case ..<0.6:
            return "semibold"
        case ..<0.8:
            return "bold"
        default:
            return "heavy"
        }
    }

    private static func fontWeightRawString(from font: UIFont) -> String? {
        if let weight = fontWeightValue(from: font) {
            return String(weight)
        }
        if font.fontDescriptor.symbolicTraits.contains(.traitBold) {
            return "bold"
        }
        return nil
    }

    private static func fontWeightValue(from font: UIFont) -> Double? {
        guard
            let traits = font.fontDescriptor.fontAttributes[.traits] as? [UIFontDescriptor.TraitKey: Any],
            let weight = traits[.weight]
        else {
            return nil
        }

        if let number = weight as? NSNumber {
            return number.doubleValue
        }
        if let value = weight as? CGFloat {
            return Double(value)
        }
        if let value = weight as? Double, value.isFinite {
            return value
        }
        if let value = weight as? Float, value.isFinite {
            return Double(value)
        }
        if let value = weight as? String, let parsed = Double(value), parsed.isFinite {
            return parsed
        }
        return nil
    }
}

public struct NeptuneUIKitViewTreeCollectorBridge: NeptuneViewTreeCollecting, Sendable {
    public init() {}

    public func captureViewTreeSnapshot(platform: String) async -> NeptuneViewTreeSnapshot {
        let collector = await MainActor.run { NeptuneUIKitViewTreeCollector() }
        return await collector.captureViewTreeSnapshot(platform: platform)
    }

    public func captureInspectorSnapshot(platform: String) async -> InspectorSnapshot {
        let collector = await MainActor.run { NeptuneUIKitViewTreeCollector() }
        return await collector.captureInspectorSnapshot(platform: platform)
    }
}
#endif

struct NeptuneViewTreeCaptureNode {
    let id: String
    let parentId: String?
    let name: String
    let className: String
    let frame: NeptuneViewTreeNode.Frame?
    let style: NeptuneViewTreeNode.Style?
    let constraints: [NeptuneViewTreeNode.Constraint]?
    let text: String?
    let visible: Bool?
    let rawAttributes: [String: InspectorPayloadValue]
    let children: [NeptuneViewTreeCaptureNode]

    var viewTreeNode: NeptuneViewTreeNode {
        NeptuneViewTreeNode(
            id: id,
            parentId: parentId,
            name: name,
            frame: frame,
            style: style,
            constraints: constraints,
            text: text,
            visible: visible,
            children: children.map(\.viewTreeNode)
        )
    }

    var inspectorPayload: InspectorPayloadValue {
        var payload = rawAttributes
        payload["children"] = .array(children.map(\.inspectorPayload))
        payload["className"] = .string(className)
        payload["name"] = .string(name)
        payload["id"] = .string(id)
        if let parentId {
            payload["parentId"] = .string(parentId)
        } else {
            payload["parentId"] = .null
        }
        if let frame {
            payload["frame"] = .object([
                "x": .number(frame.x),
                "y": .number(frame.y),
                "width": .number(frame.width),
                "height": .number(frame.height)
            ])
        }
        if let style {
            payload["style"] = .object(makeNeptuneInspectorStyleAttributes(from: style))
        }
        if let constraints {
            payload["constraints"] = .array(constraints.map(makeNeptuneInspectorConstraintPayload(from:)))
        }
        if let text {
            payload["text"] = .string(text)
        } else {
            payload["text"] = .null
        }
        if let visible {
            payload["visible"] = .bool(visible)
        } else {
            payload["visible"] = .null
        }
        return .object(payload)
    }
}

private func makeNeptuneInspectorConstraintPayload(from constraint: NeptuneViewTreeNode.Constraint) -> InspectorPayloadValue {
    var attributes: [String: InspectorPayloadValue] = [
        "id": .string(constraint.id),
        "source": .string(constraint.source),
        "relation": .string(constraint.relation),
        "firstAttribute": .string(constraint.firstAttribute),
        "constant": .number(constraint.constant),
        "multiplier": .number(constraint.multiplier),
        "priority": .number(constraint.priority),
        "isActive": .bool(constraint.isActive)
    ]

    if let secondAttribute = constraint.secondAttribute {
        attributes["secondAttribute"] = .string(secondAttribute)
    } else {
        attributes["secondAttribute"] = .null
    }
    if let firstItem = constraint.firstItem {
        attributes["firstItem"] = .string(firstItem)
    } else {
        attributes["firstItem"] = .null
    }
    if let secondItem = constraint.secondItem {
        attributes["secondItem"] = .string(secondItem)
    } else {
        attributes["secondItem"] = .null
    }
    return .object(attributes)
}
