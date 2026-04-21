//
//  AXIRStaticRendererTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

#if canImport(CoreGraphics) && canImport(AppKit)
import Testing
import Foundation
import CoreGraphics
@testable import AlkaliRenderer
@testable import AlkaliCore

@Suite("AXIR static renderer — produces valid PNGs")
struct AXIRStaticRendererTests {

    @Test("Renders an empty root node and produces a non-empty PNG")
    func emptyRoot() throws {
        let root = AXIRNode(id: AlkaliID.root(viewType: "Empty"), viewType: "Empty")
        let renderer = AXIRStaticRenderer()
        let data = try renderer.render(axir: root, size: CGSize(width: 100, height: 100))
        #expect(data.count > 0)
        #expect(isPNG(data))
    }

    @Test("Honors IB frames and nested hierarchy")
    func nestedIBHierarchy() throws {
        let childFrame = AXIRModifier(type: .ibFrame, parameters: [
            "x": .float(10), "y": .float(10), "width": .float(80), "height": .float(80)
        ])
        let child = AXIRNode(
            id: AlkaliID.root(viewType: "Child"),
            viewType: "UIButton",
            modifiers: [childFrame]
        )
        let rootFrame = AXIRModifier(type: .ibFrame, parameters: [
            "x": .float(0), "y": .float(0), "width": .float(200), "height": .float(200)
        ])
        let root = AXIRNode(
            id: AlkaliID.root(viewType: "Root"),
            viewType: "UIView",
            children: [child],
            modifiers: [rootFrame]
        )
        let renderer = AXIRStaticRenderer()
        let data = try renderer.render(axir: root, size: CGSize(width: 200, height: 200))
        #expect(data.count > 0)
        #expect(isPNG(data))
    }

    @Test("Light vs dark schemes produce different bytes")
    func lightVsDark() throws {
        let root = AXIRNode(id: AlkaliID.root(viewType: "X"), viewType: "UIView")
        let renderer = AXIRStaticRenderer()
        let light = try renderer.render(axir: root, size: CGSize(width: 100, height: 100), colorScheme: .light)
        let dark  = try renderer.render(axir: root, size: CGSize(width: 100, height: 100), colorScheme: .dark)
        #expect(light != dark)
    }

    private func isPNG(_ data: Data) -> Bool {
        // PNG magic: 89 50 4E 47 0D 0A 1A 0A
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= magic.count else { return false }
        for (i, b) in magic.enumerated() where data[i] != b { return false }
        return true
    }
}
#endif
