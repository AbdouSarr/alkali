//
//  IBAXIRGenerator.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Converts an `IBViewNode` hierarchy (parsed from .xib/.storyboard) into an AXIR tree.
///
/// The produced AXIR nodes use UIKit-flavored `ModifierType`s (`.backgroundColor`, `.ibFrame`,
/// `.text`, `.image`) so the renderer can pick them up without re-inspecting the IB source.
public struct IBAXIRGenerator: Sendable {
    public init() {}

    public func generate(viewName: String, sourceFile: String, root: IBViewNode) -> AXIRNode {
        let anchor = SourceAnchor(file: sourceFile, line: 1, column: 1)
        let rootID = AlkaliID.root(viewType: viewName, anchor: anchor)
        let loc = AlkaliCore.SourceLocation(file: sourceFile, line: 1, column: 1)
        return build(node: root, parentID: rootID, index: 0, sourceFile: sourceFile, fallbackLocation: loc, overrideViewType: viewName)
    }

    private func build(node: IBViewNode, parentID: AlkaliID, index: Int, sourceFile: String, fallbackLocation: AlkaliCore.SourceLocation, overrideViewType: String? = nil) -> AXIRNode {
        let viewType = overrideViewType ?? node.customClass ?? uikitType(for: node.elementType)
        let id = parentID.appending(.child(index: index, containerType: viewType))

        var modifiers: [AXIRModifier] = []

        if let frame = node.frame {
            modifiers.append(AXIRModifier(
                type: .ibFrame,
                parameters: [
                    "x": .float(frame.x),
                    "y": .float(frame.y),
                    "width": .float(frame.width),
                    "height": .float(frame.height)
                ],
                sourceLocation: fallbackLocation
            ))
        }
        if let hex = node.backgroundColorHex {
            modifiers.append(AXIRModifier(
                type: .backgroundColor,
                parameters: ["hex": .string(hex)],
                sourceLocation: fallbackLocation
            ))
        }
        if let text = node.text {
            modifiers.append(AXIRModifier(
                type: .text,
                parameters: ["value": .string(text)],
                sourceLocation: fallbackLocation
            ))
        }
        if let image = node.imageName {
            modifiers.append(AXIRModifier(
                type: .image,
                parameters: ["name": .assetReference(catalog: "", name: image)],
                sourceLocation: fallbackLocation
            ))
        }
        if let identifier = node.identifier {
            modifiers.append(AXIRModifier(
                type: .ibIdentifier,
                parameters: ["id": .string(identifier)],
                sourceLocation: fallbackLocation
            ))
        }

        let children = node.children.enumerated().map { idx, child in
            build(node: child, parentID: id, index: idx, sourceFile: sourceFile, fallbackLocation: fallbackLocation)
        }

        return AXIRNode(
            id: id,
            viewType: viewType,
            sourceLocation: fallbackLocation,
            children: children,
            modifiers: modifiers
        )
    }

    private func uikitType(for elementName: String) -> String {
        switch elementName {
        case "view": return "UIView"
        case "button": return "UIButton"
        case "label": return "UILabel"
        case "imageView": return "UIImageView"
        case "scrollView": return "UIScrollView"
        case "stackView": return "UIStackView"
        case "textField": return "UITextField"
        case "textView": return "UITextView"
        case "switch": return "UISwitch"
        case "slider": return "UISlider"
        case "segmentedControl": return "UISegmentedControl"
        case "progressView": return "UIProgressView"
        case "activityIndicatorView": return "UIActivityIndicatorView"
        case "pickerView": return "UIPickerView"
        case "datePicker": return "UIDatePicker"
        case "tableView": return "UITableView"
        case "collectionView": return "UICollectionView"
        case "tableViewCell": return "UITableViewCell"
        case "collectionViewCell": return "UICollectionViewCell"
        case "visualEffectView": return "UIVisualEffectView"
        case "viewController": return "UIViewController"
        case "tableViewController": return "UITableViewController"
        case "collectionViewController": return "UICollectionViewController"
        case "pageControl": return "UIPageControl"
        case "searchBar": return "UISearchBar"
        case "toolbar": return "UIToolbar"
        case "navigationBar": return "UINavigationBar"
        case "tabBar": return "UITabBar"
        default: return elementName.prefix(1).uppercased() + elementName.dropFirst()
        }
    }
}
