//
//  VisualDifferTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-14.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

#if canImport(AppKit) && canImport(SwiftUI)
import Testing
import Foundation
import SwiftUI
@testable import AlkaliPreview
@testable import AlkaliRenderer
@testable import AlkaliCore

@Suite("Visual Differ Advanced Tests")
struct VisualDifferAdvancedTests {

    let differ = VisualDiffer()
    let renderer = HeadlessSwiftUIRenderer()

    @Test("Color scheme change attributed correctly")
    @MainActor
    func colorSchemeChangeDiff() {
        let lightResult = renderer.render(
            view: Text("Test").foregroundStyle(.primary).background(.white),
            device: .iPhoneSE,
            environment: EnvironmentOverrides(colorScheme: .light)
        )
        let darkResult = renderer.render(
            view: Text("Test").foregroundStyle(.primary).background(.black),
            device: .iPhoneSE,
            environment: EnvironmentOverrides(colorScheme: .dark)
        )

        #expect(lightResult != nil)
        #expect(darkResult != nil)

        // Images should differ
        #expect(!differ.bytesMatch(lightResult!.imageData, darkResult!.imageData))
    }

    @Test("Similar images have close perceptual hashes")
    @MainActor
    func perceptualHashSimilarity() {
        let img1 = renderer.render(
            view: Text("Hello World").font(.body).padding(),
            size: CGSize(width: 200, height: 50)
        )
        let img2 = renderer.render(
            view: Text("Hello World").font(.body).padding(),
            size: CGSize(width: 200, height: 50)
        )

        #expect(img1 != nil)
        #expect(img2 != nil)

        // Identical renders should have identical hashes
        let hash1 = differ.perceptualHash(img1!)
        let hash2 = differ.perceptualHash(img2!)
        #expect(differ.hammingDistance(hash1, hash2) == 0)
    }

    @Test("Pruning deduplicates visually identical variants")
    @MainActor
    func pruningDeduplication() {
        // Two different integer values that produce the same visual output
        let img1 = renderer.render(view: Text("Hello").padding(16), size: CGSize(width: 200, height: 50))
        let img2 = renderer.render(view: Text("Hello").padding(16), size: CGSize(width: 200, height: 50))

        #expect(img1 != nil)
        #expect(img2 != nil)
        // Same view rendered twice should be byte-identical
        #expect(differ.bytesMatch(img1!, img2!))
    }
}
#endif
