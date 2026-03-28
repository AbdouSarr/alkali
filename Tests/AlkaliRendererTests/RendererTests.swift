//
//  RendererTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-28.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

#if canImport(AppKit) && canImport(SwiftUI)
import Testing
import Foundation
import SwiftUI
@testable import AlkaliRenderer
@testable import AlkaliCore

@Suite("Headless Renderer Tests")
struct HeadlessRendererTests {

    let renderer = HeadlessSwiftUIRenderer()

    @Test("Render simple Text view")
    @MainActor
    func renderSimpleText() {
        let result = renderer.render(
            view: Text("Hello Alkali").font(.title),
            device: .iPhone16Pro,
            environment: .default
        )
        #expect(result != nil)
        #expect(result!.imageData.count > 0)
        #expect(result!.renderTime > 0)
        #expect(result!.deviceProfile.name == "iPhone 16 Pro")
    }

    @Test("Light vs dark renders differ")
    @MainActor
    func lightDarkDiffer() {
        let lightResult = renderer.render(
            view: Text("Test").background(Color(.textBackgroundColor)),
            device: .iPhone16Pro,
            environment: EnvironmentOverrides(colorScheme: .light)
        )
        let darkResult = renderer.render(
            view: Text("Test").background(Color(.textBackgroundColor)),
            device: .iPhone16Pro,
            environment: EnvironmentOverrides(colorScheme: .dark)
        )

        #expect(lightResult != nil)
        #expect(darkResult != nil)
        // Image data should differ between light and dark mode
        #expect(lightResult!.imageData != darkResult!.imageData)
    }

    @Test("Different font sizes produce different renders")
    @MainActor
    func fontSizeScales() {
        let size = CGSize(width: 300, height: 200)
        let smallData = renderer.render(
            view: Text("Hello World, Alkali Testing Long Text").font(.caption2),
            size: size
        )
        let largeData = renderer.render(
            view: Text("Hello World, Alkali Testing Long Text").font(.largeTitle),
            size: size
        )

        #expect(smallData != nil)
        #expect(largeData != nil)
        // Different font sizes should produce different renders
        #expect(smallData != largeData)
    }

    @Test("Render complex view tree")
    @MainActor
    func renderComplexView() {
        let view = VStack(spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                Text("Alkali Preview")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            Text("This is a headlessly rendered SwiftUI view")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Divider()

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.blue.opacity(Double(i + 1) * 0.3))
                        .frame(height: 40)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)

        let result = renderer.render(
            view: view,
            device: .iPhone16Pro,
            environment: .default
        )

        #expect(result != nil)
        #expect(result!.imageData.count > 1000) // Should be a substantial image
    }

    @Test("Multiple renders produce distinct results")
    @MainActor
    func multipleRenders() {
        let views: [(any View, String)] = [
            (AnyView(Text("View 1").foregroundStyle(.red)), "red"),
            (AnyView(Text("View 2").foregroundStyle(.blue)), "blue"),
            (AnyView(Text("View 3").foregroundStyle(.green)), "green"),
        ]

        var results: [Data] = []
        for (view, _) in views {
            if let data = renderer.render(view: AnyView(view), size: CGSize(width: 200, height: 50)) {
                results.append(data)
            }
        }

        #expect(results.count == 3)
        // Each should be different
        #expect(results[0] != results[1])
        #expect(results[1] != results[2])
    }
}

@Suite("Compilation Cache Tests")
struct CompilationCacheTests {

    @Test("Cache persists across instances")
    func cachePersistence() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("alkali-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let cache = CompilationCache(cacheDir: tmpDir.path)
        let stats = cache.stats
        #expect(stats.entryCount == 0)
        #expect(stats.hitRate == 0)
    }

    @Test("FlagExtractor finds SDK and swiftc")
    func flagExtraction() throws {
        let extractor = FlagExtractor()
        let sdk = try extractor.macOSSDKPath()
        #expect(!sdk.isEmpty)
        #expect(sdk.contains("MacOSX"))

        let swiftc = try extractor.swiftcPath()
        #expect(!swiftc.isEmpty)
        #expect(swiftc.contains("swiftc"))
    }
}

#endif
