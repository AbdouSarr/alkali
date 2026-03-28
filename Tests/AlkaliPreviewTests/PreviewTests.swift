//
//  PreviewTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-08.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliPreview
@testable import AlkaliCore

@Suite("Variant Space Tests")
struct VariantSpaceTests {

    @Test("Cartesian product of 3 axes")
    func cartesianProduct() {
        let space = VariantSpace(axes: [
            VariantAxis(name: "color", values: ["red", "blue"]),
            VariantAxis(name: "size", values: ["small", "large"]),
            VariantAxis(name: "scheme", values: ["light", "dark"]),
        ])
        let variants = space.cartesianProduct()
        // 2 × 2 × 2 = 8
        #expect(variants.count == 8)

        // Verify all combinations exist
        let expected = Set([
            "color=red|scheme=light|size=small",
            "color=red|scheme=dark|size=small",
            "color=red|scheme=light|size=large",
            "color=red|scheme=dark|size=large",
            "color=blue|scheme=light|size=small",
            "color=blue|scheme=dark|size=small",
            "color=blue|scheme=light|size=large",
            "color=blue|scheme=dark|size=large",
        ])
        let actual = Set(variants.map { v in
            v.values.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "|")
        })
        #expect(actual == expected)
    }

    @Test("Pairwise reduces large space")
    func pairwiseReduction() {
        let space = VariantSpace(axes: [
            VariantAxis(name: "a", values: ["1", "2", "3", "4"]),
            VariantAxis(name: "b", values: ["1", "2", "3", "4"]),
            VariantAxis(name: "c", values: ["1", "2", "3", "4"]),
            VariantAxis(name: "d", values: ["1", "2", "3", "4"]),
            VariantAxis(name: "e", values: ["1", "2", "3", "4"]),
        ])
        let full = space.cartesianProduct()
        let pairwise = space.pairwiseCoverage()

        // Full product = 4^5 = 1024
        #expect(full.count == 1024)
        // Pairwise should be much smaller
        #expect(pairwise.count < 50)
        #expect(pairwise.count > 0)
    }

    @Test("Empty variant space returns single instance")
    func emptySpace() {
        let space = VariantSpace(axes: [])
        let variants = space.cartesianProduct()
        #expect(variants.count == 1)
    }

    @Test("Single axis returns all values")
    func singleAxis() {
        let space = VariantSpace(axes: [
            VariantAxis(name: "color", values: ["red", "green", "blue"]),
        ])
        let variants = space.cartesianProduct()
        #expect(variants.count == 3)
    }
}

@Suite("Variant Discovery Tests")
struct VariantDiscoveryTests {

    @Test("Auto-discovers variants from data bindings")
    func autoDiscovery() {
        let discovery = VariantDiscovery()
        let bindings: [AXIRDataBinding] = [
            AXIRDataBinding(property: "isExpanded", bindingKind: .state, sourceType: "Bool"),
            AXIRDataBinding(property: "title", bindingKind: .binding, sourceType: "String"),
            AXIRDataBinding(property: "user", bindingKind: .observedObject, sourceType: "Optional<User>"),
        ]

        let space = discovery.discover(dataBindings: bindings)

        // Should have axes for: isExpanded (Bool), title (String), user (Optional),
        // + colorScheme + dynamicTypeSize
        #expect(space.axes.count >= 4)

        let axisNames = space.axes.map(\.name)
        #expect(axisNames.contains("isExpanded"))
        #expect(axisNames.contains("title"))
        #expect(axisNames.contains("env.colorScheme"))
        #expect(axisNames.contains("env.dynamicTypeSize"))
    }
}

@Suite("Visual Differ Tests")
struct VisualDifferTests {

    let differ = VisualDiffer()

    @Test("Identical images match")
    func identicalMatch() {
        let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: UInt8(0), count: 100))
        #expect(differ.bytesMatch(data, data))
        #expect(differ.perceptualHashesMatch(data, data))
    }

    @Test("Semantic diff detects modifier change")
    func semanticModifierChange() {
        let id = AlkaliID.root(viewType: "Text")
        let old = AXIRNode(id: id, viewType: "Text", modifiers: [
            AXIRModifier(type: .padding, parameters: ["length": .float(16)])
        ])
        let new = AXIRNode(id: id, viewType: "Text", modifiers: [
            AXIRModifier(type: .padding, parameters: ["length": .float(24)])
        ])

        let diffs = differ.semanticDiff(old: old, new: new)
        let modDiffs = diffs.filter { if case .modifierChanged = $0 { return true }; return false }
        #expect(modDiffs.count == 1)
    }

    @Test("Semantic diff detects node added")
    func semanticNodeAdded() {
        let rootID = AlkaliID.root(viewType: "VStack")
        let old = AXIRNode(id: rootID, viewType: "VStack", children: [
            AXIRNode(id: rootID.appending(.child(index: 0, containerType: "VStack")), viewType: "Text")
        ])
        let new = AXIRNode(id: rootID, viewType: "VStack", children: [
            AXIRNode(id: rootID.appending(.child(index: 0, containerType: "VStack")), viewType: "Text"),
            AXIRNode(id: rootID.appending(.child(index: 1, containerType: "VStack")), viewType: "Image")
        ])

        let diffs = differ.semanticDiff(old: old, new: new)
        let addDiffs = diffs.filter { if case .nodeAdded = $0 { return true }; return false }
        #expect(addDiffs.count == 1)
    }
}

@Suite("Screenshot Catalog Tests")
struct ScreenshotCatalogTests {

    @Test("Store and query entries")
    func storeAndQuery() {
        let catalog = ScreenshotCatalog()
        let variant = VariantInstance(values: ["env.colorScheme": "light"])
        let axir = AXIRNode(id: AlkaliID.root(viewType: "Text"), viewType: "Text")

        catalog.add(CatalogEntry(
            viewName: "ProfileCard",
            variant: variant,
            imageData: Data([1, 2, 3]),
            axir: axir,
            renderTime: 0.05,
            deviceProfile: .iPhone16Pro
        ))
        catalog.add(CatalogEntry(
            viewName: "SettingsView",
            variant: variant,
            imageData: Data([4, 5, 6]),
            axir: axir,
            renderTime: 0.03,
            deviceProfile: .iPhoneSE
        ))

        #expect(catalog.allEntries().count == 2)
    }

    @Test("Filter by device")
    func filterByDevice() {
        let catalog = ScreenshotCatalog()
        let variant = VariantInstance(values: [:])
        let axir = AXIRNode(id: AlkaliID.root(viewType: "V"), viewType: "V")

        catalog.add(CatalogEntry(viewName: "V", variant: variant, imageData: Data(), axir: axir, renderTime: 0, deviceProfile: .iPhone16Pro))
        catalog.add(CatalogEntry(viewName: "V", variant: variant, imageData: Data(), axir: axir, renderTime: 0, deviceProfile: .iPhoneSE))
        catalog.add(CatalogEntry(viewName: "V", variant: variant, imageData: Data(), axir: axir, renderTime: 0, deviceProfile: .iPadPro13))

        let filtered = catalog.filter(device: "iPhone 16 Pro")
        #expect(filtered.count == 1)
    }

    @Test("HTML export creates valid files")
    func htmlExport() throws {
        let catalog = ScreenshotCatalog()
        let variant = VariantInstance(values: ["env.colorScheme": "light"])
        let axir = AXIRNode(id: AlkaliID.root(viewType: "Test"), viewType: "Test")

        catalog.add(CatalogEntry(
            viewName: "TestView",
            variant: variant,
            imageData: Data([0x89, 0x50, 0x4E, 0x47]),
            axir: axir,
            renderTime: 0.01,
            deviceProfile: .iPhone16Pro
        ))

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("alkali-catalog-\(UUID().uuidString)")
        try catalog.exportHTML(to: tmpDir.path)

        let htmlPath = tmpDir.appendingPathComponent("index.html")
        #expect(FileManager.default.fileExists(atPath: htmlPath.path))

        let html = try String(contentsOf: htmlPath, encoding: .utf8)
        #expect(html.contains("Alkali Preview Catalog"))
        #expect(html.contains("TestView"))
        #expect(html.contains("render_0.png"))

        try? FileManager.default.removeItem(at: tmpDir)
    }
}

@Suite("Baseline Manager Tests")
struct BaselineManagerTests {

    @Test("Set and get baseline")
    func setGetBaseline() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("alkali-baseline-\(UUID().uuidString)")
        let manager = BaselineManager(baselinePath: tmpDir.path)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let variant = VariantInstance(values: ["env.colorScheme": "light"])
        let imageData = Data([1, 2, 3, 4, 5])
        let axir = AXIRNode(id: AlkaliID.root(viewType: "Card"), viewType: "Card")

        try manager.setBaseline(viewName: "Card", variant: variant, imageData: imageData, axir: axir)

        let result = manager.getBaseline(viewName: "Card", variant: variant)
        #expect(result != nil)
        #expect(result!.imageData == imageData)
        #expect(result!.axir.viewType == "Card")
    }
}
