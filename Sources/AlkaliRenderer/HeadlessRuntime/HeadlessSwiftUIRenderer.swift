//
//  HeadlessSwiftUIRenderer.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-25.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI
import Foundation
import AlkaliCore

/// Renders SwiftUI views to bitmaps on macOS using NSHostingView.
public final class HeadlessSwiftUIRenderer: @unchecked Sendable {

    public init() {}

    /// Render any SwiftUI View to PNG data at a given size.
    @MainActor
    public func render<V: View>(
        view: V,
        size: CGSize,
        colorScheme: ColorScheme = .light
    ) -> Data? {
        let hostingView = NSHostingView(rootView:
            view
                .environment(\.colorScheme, colorScheme)
                .frame(width: size.width, height: size.height)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layout()
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return nil
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    /// Render a SwiftUI view with environment overrides and device profile.
    /// Walks the rendered NSView hierarchy to extract AXIR with layout and accessibility.
    @MainActor
    public func render<V: View>(
        view: V,
        device: DeviceProfile,
        environment: EnvironmentOverrides
    ) -> RenderResult? {
        let size = CGSize(width: device.screenSize.width, height: device.screenSize.height)
        let colorScheme: ColorScheme = environment.colorScheme == .dark ? .dark : .light

        let hostingView = NSHostingView(rootView:
            view
                .environment(\.colorScheme, colorScheme)
                .frame(width: size.width, height: size.height)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layout()
        hostingView.layoutSubtreeIfNeeded()

        let startTime = CFAbsoluteTimeGetCurrent()

        guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return nil
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)
        guard let imageData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }

        let renderTime = CFAbsoluteTimeGetCurrent() - startTime

        // Walk the rendered view hierarchy to build rich AXIR
        let axir = extractAXIR(from: hostingView, viewType: String(describing: V.self), screenSize: size)

        return RenderResult(
            imageData: imageData,
            axir: axir,
            renderTime: renderTime,
            deviceProfile: device
        )
    }

    // MARK: - AXIR Extraction from NSView Hierarchy

    @MainActor
    private func extractAXIR(from view: NSView, viewType: String, screenSize: CGSize) -> AXIRNode {
        let rootID = AlkaliID.root(viewType: viewType)
        let children = walkSubviews(view: view, parentID: rootID, depth: 0)
        let a11y = extractAccessibility(from: view)

        return AXIRNode(
            id: rootID,
            viewType: viewType,
            children: children,
            resolvedLayout: AXIRLayout(
                frame: AXIRRect(x: 0, y: 0, width: Double(screenSize.width), height: Double(screenSize.height)),
                absoluteFrame: AXIRRect(x: 0, y: 0, width: Double(screenSize.width), height: Double(screenSize.height))
            ),
            accessibilityTree: a11y
        )
    }

    @MainActor
    private func walkSubviews(view: NSView, parentID: AlkaliID, depth: Int) -> [AXIRNode] {
        guard depth < 20 else { return [] } // prevent infinite recursion

        var children: [AXIRNode] = []
        for (index, subview) in view.subviews.enumerated() {
            let typeName = demangledTypeName(subview)
            let childID = parentID.appending(.child(index: index, containerType: typeName))

            let frame = subview.frame
            let absoluteFrame = subview.convert(subview.bounds, to: nil)

            let layout = AXIRLayout(
                frame: AXIRRect(x: Double(frame.origin.x), y: Double(frame.origin.y),
                               width: Double(frame.size.width), height: Double(frame.size.height)),
                absoluteFrame: AXIRRect(x: Double(absoluteFrame.origin.x), y: Double(absoluteFrame.origin.y),
                                       width: Double(absoluteFrame.size.width), height: Double(absoluteFrame.size.height))
            )

            let grandchildren = walkSubviews(view: subview, parentID: childID, depth: depth + 1)
            let a11y = extractAccessibility(from: subview)

            let node = AXIRNode(
                id: childID,
                viewType: typeName,
                children: grandchildren,
                resolvedLayout: layout,
                accessibilityTree: a11y
            )
            children.append(node)
        }
        return children
    }

    @MainActor
    private func extractAccessibility(from view: NSView) -> AXIRAccessibility? {
        let cell = view as? NSControl
        let label = view.accessibilityLabel()
        let value = view.accessibilityValue() as? String
        let role = view.accessibilityRole()

        // Only return accessibility info if there's meaningful data
        guard label != nil || value != nil || role != nil else { return nil }

        let mappedRole: AccessibilityRole
        switch role {
        case .button: mappedRole = .button
        case .link: mappedRole = .link
        case .image: mappedRole = .image
        case .staticText: mappedRole = .staticText
        case .textField, .textArea: mappedRole = .textField
        case .slider: mappedRole = .slider
        case .list: mappedRole = .list
        case .cell: mappedRole = .cell
        default: mappedRole = .unknown
        }

        return AXIRAccessibility(
            role: mappedRole,
            label: label,
            value: value,
            isAccessibilityElement: view.isAccessibilityElement()
        )
    }

    private func demangledTypeName(_ view: NSView) -> String {
        let fullName = String(describing: type(of: view))
        // Extract the meaningful part from mangled names like _NSHostingView<ModifiedContent<...>>
        if let range = fullName.range(of: "<") {
            let prefix = String(fullName[..<range.lowerBound])
            if prefix.hasPrefix("_") {
                return String(prefix.dropFirst())
            }
            return prefix
        }
        return fullName
    }
}
#endif
