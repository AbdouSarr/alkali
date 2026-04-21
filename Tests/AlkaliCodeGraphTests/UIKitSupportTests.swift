//
//  UIKitSupportTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliCodeGraph
@testable import AlkaliCore

@Suite("UIKit detection — BodyAnalyzer")
struct UIKitDetectionTests {

    let analyzer = BodyAnalyzer()

    @Test("Detects direct UIView subclass")
    func uiViewSubclass() {
        let source = """
        import UIKit
        class FancyView: UIView {
            @IBOutlet var label: UILabel!
            @IBAction func tapped(_ sender: UIButton) {}
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "FancyView.swift")
        let fancy = views.first { $0.name == "FancyView" }
        #expect(fancy != nil)
        #expect(fancy?.framework == .uiKit)
        #expect(fancy?.superclass == "UIView")
        #expect(fancy?.dataBindings.contains(where: { $0.bindingKind == .iboutlet && $0.property == "label" }) == true)
        #expect(fancy?.dataBindings.contains(where: { $0.bindingKind == .ibaction && $0.property == "tapped" }) == true)
    }

    @Test("Detects UIViewController subclass")
    func uiViewController() {
        let source = """
        import UIKit
        class SignInVC: UIViewController {
            @Published var isLoading: Bool = false
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "SignInVC.swift")
        let vc = views.first { $0.name == "SignInVC" }
        #expect(vc != nil)
        #expect(vc?.framework == .uiKit)
        #expect(vc?.superclass == "UIViewController")
        #expect(vc?.dataBindings.contains(where: { $0.bindingKind == .published && $0.property == "isLoading" }) == true)
    }

    @Test("Detects delegate conformance")
    func delegateConformance() {
        let source = """
        import UIKit
        class PhotoCollectionVC: UICollectionViewController, UICollectionViewDelegate, UICollectionViewDataSource {
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "PhotoCollectionVC.swift")
        let vc = views.first { $0.name == "PhotoCollectionVC" }
        #expect(vc?.dataBindings.contains(where: { $0.sourceType == "UICollectionViewDelegate" }) == true)
        #expect(vc?.dataBindings.contains(where: { $0.sourceType == "UICollectionViewDataSource" }) == true)
    }

    @Test("Non-UI class is flagged but not retained by transitive resolver")
    func nonUIClass() {
        // Class that inherits from a non-UIKit base — BodyAnalyzer tags it as a UIKit
        // candidate, but UnifiedCodeGraph's transitive resolver should drop it.
        let source = """
        class Widget: NSObject {
            @Published var ready: Bool = false
        }
        """
        let views = analyzer.analyzeFile(source: source, fileName: "Widget.swift")
        let widget = views.first { $0.name == "Widget" }
        #expect(widget?.framework == .uiKit)   // raw pass surfaces it
        #expect(widget?.superclass == "NSObject")
    }
}

@Suite("UIKit transitive resolution — UnifiedCodeGraph")
struct UIKitResolutionTests {

    @Test("Transitive UIKit inheritance is resolved")
    func transitiveInheritance() async throws {
        // Mini fixture: a Swift file declaring a chain BaseView -> MidView -> LeafView.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let source = """
        import UIKit
        class BaseView: UIView {}
        class MidView: BaseView {}
        class LeafView: MidView {}
        class NotAView: NSObject {}
        """
        let srcPath = tempDir.appendingPathComponent("Views.swift")
        try source.write(to: srcPath, atomically: true, encoding: .utf8)

        let graph = UnifiedCodeGraph(projectRoot: tempDir.path)
        let all = try await graph.viewDeclarations(in: nil)

        let names = Set(all.map { $0.name })
        #expect(names.contains("BaseView"))
        #expect(names.contains("MidView"))
        #expect(names.contains("LeafView"))
        #expect(!names.contains("NotAView"))
    }
}

@Suite("XIB/Storyboard hierarchy — InterfaceBuilderParser")
struct InterfaceBuilderParserTests {

    @Test("Extracts customClass from a tiny XIB fixture")
    func customClass() throws {
        let xibXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document>
          <objects>
            <view customClass="MyCustomView" id="aaa">
              <rect key="frame" x="0" y="0" width="320" height="200"/>
              <subviews>
                <label customClass="MyLabel" id="bbb" text="Hello">
                  <rect key="frame" x="10" y="10" width="100" height="20"/>
                </label>
              </subviews>
            </view>
          </objects>
        </document>
        """
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xib")
        try xibXML.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let parser = InterfaceBuilderParser()
        let classes = parser.extractCustomClasses(from: tempFile.path)
        let names = Set(classes.map { $0.className })
        #expect(names.contains("MyCustomView"))
        #expect(names.contains("MyLabel"))
    }

    @Test("Builds a hierarchy with nested children")
    func hierarchy() throws {
        let xibXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <document>
          <objects>
            <view id="aaa">
              <rect key="frame" x="0" y="0" width="320" height="200"/>
              <subviews>
                <label id="bbb" text="Hello">
                  <rect key="frame" x="10" y="10" width="100" height="20"/>
                </label>
                <button id="ccc" title="Tap">
                  <rect key="frame" x="10" y="40" width="80" height="40"/>
                </button>
              </subviews>
            </view>
          </objects>
        </document>
        """
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xib")
        try xibXML.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let parser = InterfaceBuilderParser()
        let root = parser.extractHierarchy(from: tempFile.path)
        #expect(root != nil)
        #expect(root?.elementType == "view")
        #expect(root?.children.count == 2)
        #expect(root?.children.first?.elementType == "label")
        #expect(root?.children.first?.text == "Hello")
    }
}

@Suite("Asset usages across SwiftUI and UIKit")
struct AssetUsageTests {

    @Test("UIImage(named:) is discovered in a pure-UIKit file")
    func uikitImageNamed() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let source = """
        import UIKit
        class Icon: UIView {
            override func draw(_ rect: CGRect) {
                let img = UIImage(named: "brand-logo")
                _ = img
            }
        }
        """
        let srcPath = tempDir.appendingPathComponent("Icon.swift")
        try source.write(to: srcPath, atomically: true, encoding: .utf8)

        let graph = UnifiedCodeGraph(projectRoot: tempDir.path)
        let refs = try await graph.viewsReferencing(asset: "brand-logo")
        #expect(refs.map(\.name).contains("Icon"))
    }
}
