//
//  CodeGraphTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-10.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliCodeGraph
@testable import AlkaliCore

@Suite("Body Analyzer Tests")
struct BodyAnalyzerTests {

    let analyzer = BodyAnalyzer()

    // MARK: - View declarations with body structure and data bindings

    @Test("Analyzes simple view with modifiers")
    func simpleViewWithModifiers() {
        let source = """
        import SwiftUI
        struct ProfileCard: View {
            @ObservedObject var user: User
            @State private var isExpanded: Bool = false

            var body: some View {
                Text("Hello")
                    .font(.headline)
                    .padding(16)
            }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "ProfileCard.swift")
        #expect(views.count == 1)

        let view = views[0]
        #expect(view.name == "ProfileCard")
        #expect(view.dataBindings.count == 2)
        #expect(view.dataBindings[0].bindingKind == .observedObject)
        #expect(view.dataBindings[0].property == "user")
        #expect(view.dataBindings[1].bindingKind == .state)
        #expect(view.dataBindings[1].property == "isExpanded")

        // Body should have a Text with two modifiers
        #expect(view.bodyAST != nil)
    }

    @Test("Analyzes VStack container with children")
    func vstackContainer() {
        let source = """
        import SwiftUI
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Title")
                    Button("Tap") {}
                    Spacer()
                }
            }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "MyView.swift")
        #expect(views.count == 1)

        guard case .container(let viewType, _, let children) = views[0].bodyAST else {
            Issue.record("Expected container")
            return
        }
        #expect(viewType == "VStack")
        #expect(children.count == 3)
    }

    @Test("Analyzes conditional view (if/else)")
    func conditionalView() {
        let source = """
        import SwiftUI
        struct CondView: View {
            @State var isShown: Bool = true
            var body: some View {
                if isShown {
                    Text("Visible")
                } else {
                    Text("Hidden")
                }
            }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "CondView.swift")
        #expect(views.count == 1)

        guard case .conditional(_, let trueBranch, let falseBranch, _) = views[0].bodyAST else {
            Issue.record("Expected conditional")
            return
        }
        #expect(trueBranch != nil)
        #expect(falseBranch != nil)
    }

    @Test("Analyzes ForEach")
    func forEachView() {
        let source = """
        import SwiftUI
        struct ListView: View {
            let items: [String]
            var body: some View {
                ForEach(items, id: \\.self) { item in
                    Text(item)
                }
            }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "ListView.swift")
        #expect(views.count == 1)

        guard case .forEach(_, _, let body, _) = views[0].bodyAST else {
            Issue.record("Expected ForEach")
            return
        }
        #expect(body != nil)
    }

    @Test("Analyzes multiple views in one file")
    func multipleViews() {
        let source = """
        import SwiftUI
        struct ViewA: View {
            var body: some View { Text("A") }
        }
        struct ViewB: View {
            var body: some View { Text("B") }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "Multi.swift")
        #expect(views.count == 2)
        #expect(views[0].name == "ViewA")
        #expect(views[1].name == "ViewB")
    }

    @Test("Detects @Environment binding")
    func environmentBinding() {
        let source = """
        import SwiftUI
        struct EnvView: View {
            @Environment(\\.colorScheme) var colorScheme
            var body: some View { Text("hi") }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "EnvView.swift")
        #expect(views.count == 1)
        #expect(views[0].dataBindings.count == 1)
        #expect(views[0].dataBindings[0].bindingKind == .environment)
    }
}

@Suite("Static AXIR Generation Tests")
struct StaticAXIRGenerationTests {

    let analyzer = BodyAnalyzer()
    let generator = StaticAXIRGenerator()

    @Test("Generates AXIR from simple view with modifiers")
    func simpleViewAXIR() {
        let source = """
        import SwiftUI
        struct Card: View {
            var body: some View {
                Text("Hello")
                    .font(.headline)
                    .padding(16)
            }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "Card.swift")
        let view = views[0]
        let axir = generator.generate(from: view)

        #expect(axir != nil)
        #expect(axir?.viewType == "Text")
        #expect(axir?.modifiers.count == 2)
        #expect(axir?.modifiers[0].type == .font)
        #expect(axir?.modifiers[1].type == .padding)
    }

    @Test("Generates AXIR from container with children")
    func containerAXIR() {
        let source = """
        import SwiftUI
        struct Layout: View {
            var body: some View {
                VStack {
                    Text("Title")
                    Text("Subtitle")
                }
            }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "Layout.swift")
        let axir = generator.generate(from: views[0])

        #expect(axir != nil)
        #expect(axir?.viewType == "VStack")
        #expect(axir?.children.count == 2)
        #expect(axir?.children[0].viewType == "Text")
        #expect(axir?.children[1].viewType == "Text")
    }

    @Test("Static AXIR has correct modifier ordering and source locations")
    func modifierOrdering() {
        let source = """
        import SwiftUI
        struct Styled: View {
            var body: some View {
                Text("X")
                    .bold()
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.blue)
                    .cornerRadius(12)
            }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "Styled.swift")
        let axir = generator.generate(from: views[0])

        #expect(axir != nil)
        let modTypes = axir!.modifiers.map(\.type)
        #expect(modTypes == [.bold, .foregroundStyle, .padding, .background, .cornerRadius])

        // All modifiers should have source locations
        for mod in axir!.modifiers {
            #expect(mod.sourceLocation != nil)
            #expect(mod.sourceLocation?.file == "Styled.swift")
        }
    }

    @Test("AXIR for conditional content")
    func conditionalAXIR() {
        let source = """
        import SwiftUI
        struct CondView: View {
            @State var show: Bool = true
            var body: some View {
                if show {
                    Text("Yes")
                } else {
                    Text("No")
                }
            }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "Cond.swift")
        let axir = generator.generate(from: views[0])

        #expect(axir != nil)
        #expect(axir?.viewType == "ConditionalContent")
        #expect(axir?.children.count == 2) // both branches
    }

    @Test("AXIR for ForEach")
    func forEachAXIR() {
        let source = """
        import SwiftUI
        struct ListV: View {
            let items: [String]
            var body: some View {
                ForEach(items, id: \\.self) { item in
                    Text(item)
                }
            }
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "ListV.swift")
        let axir = generator.generate(from: views[0])

        #expect(axir != nil)
        #expect(axir?.viewType == "ForEach")
        #expect(axir?.children.count == 1)
    }
}

@Suite("Asset Catalog Parser Tests")
struct AssetCatalogParserTests {

    @Test("Parses color asset with light/dark variants")
    func parseColorAsset() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let catalogDir = tmpDir.appendingPathComponent("Colors.xcassets")
        let colorsetDir = catalogDir.appendingPathComponent("brandBlue.colorset")
        try FileManager.default.createDirectory(at: colorsetDir, withIntermediateDirectories: true)

        let contents = """
        {
          "colors": [
            {
              "color": {
                "color-space": "srgb",
                "components": { "red": "0.102", "green": "0.451", "blue": "0.910", "alpha": "1.0" }
              },
              "idiom": "universal"
            },
            {
              "appearances": [{ "appearance": "luminosity", "value": "dark" }],
              "color": {
                "color-space": "srgb",
                "components": { "red": "0.541", "green": "0.706", "blue": "0.973", "alpha": "1.0" }
              },
              "idiom": "universal"
            }
          ],
          "info": { "author": "xcode", "version": 1 }
        }
        """
        try contents.write(to: colorsetDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

        let parser = AssetCatalogParser()
        let colors = try parser.parseColors(in: catalogDir.path)

        #expect(colors.count == 1)
        #expect(colors[0].name == "brandBlue")
        #expect(colors[0].catalog == "Colors.xcassets")
        #expect(colors[0].appearances.count == 2)
        #expect(colors[0].gamut == .sRGB)

        // Cleanup
        try? FileManager.default.removeItem(at: tmpDir)
    }
}
