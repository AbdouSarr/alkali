//
//  InterfaceBuilderParser.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Lightweight XML parser for `.xib` and `.storyboard` files.
///
/// Extracts:
/// - Custom class declarations via `customClass="X" customModule="Y"` attributes
/// - View hierarchy (the `objects`/`subviews` tree) as an IB-flavored AXIR
/// - IBOutlet connections (`<connections><outlet property="x" destination="..."/>`)
public final class InterfaceBuilderParser: NSObject, Sendable {
    public struct CustomClassEntry: Sendable {
        public let className: String
        public let superclass: String?
        public let line: Int
    }

    public override init() { super.init() }

    /// Returns all `customClass` names declared in an .xib/.storyboard.
    /// `superclass` is approximated from the element tag name (e.g. `<view>` → `UIView`,
    /// `<viewController>` → `UIViewController`).
    public func extractCustomClasses(from path: String) -> [CustomClassEntry] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        let handler = CustomClassHandler()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return handler.entries
    }

    /// Returns an IB view-hierarchy tree. For .xib files, returns the single root.
    /// For .storyboard files, returns the first scene's root (use `extractHierarchy(from:matchingCustomClass:)`
    /// to target a specific scene by its customClass).
    public func extractHierarchy(from path: String) -> IBViewNode? {
        return extractHierarchies(from: path).first
    }

    /// Returns a specific scene matching a customClass name. Searches the scene's entire
    /// descendant tree for the customClass, then returns that scene's root view.
    /// If no match, returns the first scene (safe fallback).
    public func extractHierarchy(from path: String, matchingCustomClass targetClass: String) -> IBViewNode? {
        let scenes = extractHierarchies(from: path)
        for scene in scenes {
            if sceneContains(node: scene, customClass: targetClass) {
                return scene
            }
        }
        return scenes.first
    }

    /// Returns every top-level scene's root view. For an .xib, this is a single-element array.
    /// For a .storyboard, it's one element per `<scene>`.
    public func extractHierarchies(from path: String) -> [IBViewNode] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        let handler = HierarchyHandler()
        let parser = XMLParser(data: data)
        parser.delegate = handler
        parser.parse()
        return handler.allScenes
    }

    private func sceneContains(node: IBViewNode, customClass: String) -> Bool {
        if node.customClass == customClass { return true }
        return node.children.contains { sceneContains(node: $0, customClass: customClass) }
    }
}

/// IB view node — a normalized representation of an element in the xib/storyboard tree.
public struct IBViewNode: Sendable, Codable, Hashable {
    public let elementType: String   // view / button / label / imageView / …
    public let customClass: String?
    public let identifier: String?
    public let frame: IBRect?
    public let backgroundColorHex: String?
    public let text: String?         // label text / button title
    public let imageName: String?    // UIImage(named:) from IB
    public let children: [IBViewNode]

    public init(
        elementType: String,
        customClass: String? = nil,
        identifier: String? = nil,
        frame: IBRect? = nil,
        backgroundColorHex: String? = nil,
        text: String? = nil,
        imageName: String? = nil,
        children: [IBViewNode] = []
    ) {
        self.elementType = elementType
        self.customClass = customClass
        self.identifier = identifier
        self.frame = frame
        self.backgroundColorHex = backgroundColorHex
        self.text = text
        self.imageName = imageName
        self.children = children
    }
}

public struct IBRect: Sendable, Codable, Hashable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

// MARK: - XMLParser delegates

private final class CustomClassHandler: NSObject, XMLParserDelegate {
    var entries: [InterfaceBuilderParser.CustomClassEntry] = []
    private var currentLine: Int = 1

    /// Map element names to UIKit base types so the returned `superclass` is meaningful
    /// to the transitive resolver (even when customClass elements don't declare one).
    private static let elementToBase: [String: String] = [
        "viewController":          "UIViewController",
        "tableViewController":     "UITableViewController",
        "collectionViewController": "UICollectionViewController",
        "navigationController":    "UINavigationController",
        "tabBarController":        "UITabBarController",
        "pageViewController":      "UIPageViewController",
        "splitViewController":     "UISplitViewController",
        "view":                    "UIView",
        "button":                  "UIButton",
        "label":                   "UILabel",
        "imageView":               "UIImageView",
        "scrollView":              "UIScrollView",
        "stackView":               "UIStackView",
        "textField":               "UITextField",
        "textView":                "UITextView",
        "switch":                  "UISwitch",
        "slider":                  "UISlider",
        "segmentedControl":        "UISegmentedControl",
        "progressView":            "UIProgressView",
        "activityIndicatorView":   "UIActivityIndicatorView",
        "pickerView":              "UIPickerView",
        "datePicker":              "UIDatePicker",
        "tableView":               "UITableView",
        "collectionView":          "UICollectionView",
        "tableViewCell":           "UITableViewCell",
        "collectionViewCell":      "UICollectionViewCell",
        "visualEffectView":        "UIVisualEffectView",
        "window":                  "UIWindow"
    ]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        currentLine = parser.lineNumber
        guard let customClass = attributeDict["customClass"] else { return }
        let base = CustomClassHandler.elementToBase[elementName]
        entries.append(.init(className: customClass, superclass: base, line: parser.lineNumber))
    }
}

private final class HierarchyHandler: NSObject, XMLParserDelegate {
    /// Every top-level scene root (xib: 1, storyboard: N).
    var allScenes: [IBViewNode] = []
    /// Convenience alias — first scene.
    var root: IBViewNode? { allScenes.first }

    private var stack: [MutableIBNode] = []
    // The outermost "objects" container is not a rendered view — skip it.
    private var insideObjects = false

    private let viewElements: Set<String> = [
        "view", "button", "label", "imageView", "scrollView", "stackView",
        "textField", "textView", "switch", "slider", "segmentedControl",
        "progressView", "activityIndicatorView", "pickerView", "datePicker",
        "tableView", "collectionView", "tableViewCell", "collectionViewCell",
        "visualEffectView", "pageControl", "searchBar", "toolbar", "navigationBar",
        "tabBar", "viewController", "tableViewController", "collectionViewController"
    ]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attr: [String: String]) {
        if elementName == "objects" { insideObjects = true; return }

        if viewElements.contains(elementName) {
            var rect: IBRect? = nil
            // Rect info usually comes as a sibling <rect ...> tag; we'll assign below.
            _ = rect
            let node = MutableIBNode(
                elementType: elementName,
                customClass: attr["customClass"],
                identifier: attr["id"] ?? attr["restorationIdentifier"],
                frame: nil,
                backgroundColorHex: nil,
                text: attr["text"] ?? attr["title"],
                imageName: attr["image"],
                children: []
            )
            stack.append(node)
        } else if elementName == "rect" {
            // Attach to current top-of-stack view.
            guard var top = stack.popLast() else { return }
            if let x = Double(attr["x"] ?? ""), let y = Double(attr["y"] ?? ""),
               let w = Double(attr["width"] ?? ""), let h = Double(attr["height"] ?? "") {
                top.frame = IBRect(x: x, y: y, width: w, height: h)
            }
            stack.append(top)
        } else if elementName == "color" {
            guard var top = stack.popLast() else { return }
            if attr["key"] == "backgroundColor" {
                if let r = Double(attr["red"] ?? ""), let g = Double(attr["green"] ?? ""),
                   let b = Double(attr["blue"] ?? ""), let a = Double(attr["alpha"] ?? "1.0") {
                    top.backgroundColorHex = String(format: "#%02X%02X%02X%02X",
                        Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
                }
            }
            stack.append(top)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "objects" { insideObjects = false; return }
        guard viewElements.contains(elementName) else { return }
        guard let popped = stack.popLast() else { return }
        let finished = popped.frozen()
        if var parent = stack.popLast() {
            parent.children.append(finished)
            stack.append(parent)
        } else {
            // This is a top-level scene root — accumulate instead of only keeping the first.
            allScenes.append(finished)
        }
    }
}

private struct MutableIBNode {
    var elementType: String
    var customClass: String?
    var identifier: String?
    var frame: IBRect?
    var backgroundColorHex: String?
    var text: String?
    var imageName: String?
    var children: [IBViewNode]

    func frozen() -> IBViewNode {
        IBViewNode(
            elementType: elementType,
            customClass: customClass,
            identifier: identifier,
            frame: frame,
            backgroundColorHex: backgroundColorHex,
            text: text,
            imageName: imageName,
            children: children
        )
    }
}
