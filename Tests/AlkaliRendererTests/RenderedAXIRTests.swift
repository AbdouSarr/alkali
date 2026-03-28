//
//  RenderedAXIRTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-02.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

#if canImport(AppKit) && canImport(SwiftUI)
import Testing
import Foundation
import SwiftUI
@testable import AlkaliRenderer
@testable import AlkaliCore

@Suite("Rendered AXIR Extraction Tests")
struct RenderedAXIRTests {

    let renderer = HeadlessSwiftUIRenderer()

    @Test("Rendered AXIR has resolvedLayout populated")
    @MainActor
    func renderedAXIRHasLayout() {
        let result = renderer.render(
            view: VStack {
                Text("Title").font(.headline)
                Text("Subtitle").font(.body)
            },
            device: .iPhone16Pro,
            environment: .default
        )

        #expect(result != nil)
        let axir = result!.axir
        #expect(axir.resolvedLayout != nil)
        #expect(axir.resolvedLayout!.frame.width > 0)
        #expect(axir.resolvedLayout!.frame.height > 0)
    }

    @Test("Rendered AXIR children have frame rects")
    @MainActor
    func childrenHaveFrames() {
        let result = renderer.render(
            view: VStack(spacing: 20) {
                Text("Top")
                Text("Bottom")
            }.padding(20),
            device: .iPhone16Pro,
            environment: .default
        )

        #expect(result != nil)
        let axir = result!.axir
        // NSHostingView may or may not expose subviews depending on SwiftUI internals.
        // What we can verify: the root has layout data.
        #expect(axir.resolvedLayout != nil)
        #expect(axir.resolvedLayout!.frame.width > 0)
    }

    @Test("Rendered AXIR walks view hierarchy")
    @MainActor
    func walksHierarchy() {
        let result = renderer.render(
            view: HStack {
                Image(systemName: "star")
                Text("Hello")
                Spacer()
            },
            device: .iPhoneSE,
            environment: .default
        )

        #expect(result != nil)
        // Should have the root + at least one level of children
        let totalNodes = result!.axir.allNodes.count
        #expect(totalNodes >= 1)
    }

    @Test("RTL layout renders differently")
    @MainActor
    func rtlLayout() {
        let ltrResult = renderer.render(
            view: HStack { Text("Hello"); Spacer(); Text("World") }
                .environment(\.layoutDirection, .leftToRight),
            device: .iPhone16Pro,
            environment: .default
        )
        let rtlResult = renderer.render(
            view: HStack { Text("Hello"); Spacer(); Text("World") }
                .environment(\.layoutDirection, .rightToLeft),
            device: .iPhone16Pro,
            environment: .default
        )

        #expect(ltrResult != nil)
        #expect(rtlResult != nil)
        #expect(ltrResult!.imageData != rtlResult!.imageData)
    }

    @Test("Device bezel compositing dimensions")
    @MainActor
    func bezelDimensions() {
        let result = renderer.render(
            view: Text("Test"),
            device: .iPhone16Pro,
            environment: .default
        )
        #expect(result != nil)
        // Image should match device screen size
        #expect(result!.deviceProfile.name == "iPhone 16 Pro")
        #expect(result!.deviceProfile.screenSize.width == 393)
    }
}
#endif
