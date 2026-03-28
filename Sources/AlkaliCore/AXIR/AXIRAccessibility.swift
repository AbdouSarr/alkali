//
//  AXIRAccessibility.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-05.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct AXIRAccessibility: Codable, Hashable, Sendable {
    public let role: AccessibilityRole
    public let label: String?
    public let value: String?
    public let hint: String?
    public let traits: Set<AccessibilityTrait>
    public let isAccessibilityElement: Bool
    public let children: [AXIRAccessibility]

    public init(
        role: AccessibilityRole,
        label: String? = nil,
        value: String? = nil,
        hint: String? = nil,
        traits: Set<AccessibilityTrait> = [],
        isAccessibilityElement: Bool = true,
        children: [AXIRAccessibility] = []
    ) {
        self.role = role
        self.label = label
        self.value = value
        self.hint = hint
        self.traits = traits
        self.isAccessibilityElement = isAccessibilityElement
        self.children = children
    }
}

public enum AccessibilityRole: String, Codable, Hashable, Sendable {
    case button
    case link
    case image
    case staticText
    case searchField
    case textField
    case header
    case tab
    case tabBar
    case toggleSwitch = "switch"
    case slider
    case progressIndicator
    case list
    case cell
    case none
    case unknown
}

public enum AccessibilityTrait: String, Codable, Hashable, Sendable {
    case isButton
    case isHeader
    case isLink
    case isImage
    case isSearchField
    case isStaticText
    case isSelected
    case playsSound
    case isKeyboardKey
    case isSummaryElement
    case updatesFrequently
    case notEnabled
    case allowsDirectInteraction
    case causesPageTurn
    case isToggle
}
