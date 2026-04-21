//
//  AXIRModifier.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-03.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct AXIRModifier: Codable, Hashable, Sendable {
    public let type: ModifierType
    public let parameters: [String: AXIRValue]
    public let sourceLocation: SourceLocation?

    public init(
        type: ModifierType,
        parameters: [String: AXIRValue] = [:],
        sourceLocation: SourceLocation? = nil
    ) {
        self.type = type
        self.parameters = parameters
        self.sourceLocation = sourceLocation
    }
}

public enum ModifierType: String, Codable, Hashable, Sendable {
    // Layout
    case padding
    case frame
    case fixedSize
    case layoutPriority
    case offset
    case position
    case edgesIgnoringSafeArea

    // Appearance
    case foregroundStyle
    case foregroundColor
    case background
    case tint
    case opacity
    case shadow
    case blur
    case cornerRadius
    case clipShape
    case mask

    // Typography
    case font
    case fontWeight
    case italic
    case bold
    case underline
    case strikethrough
    case lineLimit
    case multilineTextAlignment
    case minimumScaleFactor

    // Interaction
    case onTapGesture
    case onLongPressGesture
    case gesture
    case disabled
    case allowsHitTesting

    // Navigation
    case navigationTitle
    case navigationBarHidden
    case sheet
    case fullScreenCover
    case popover

    // Accessibility
    case accessibilityLabel
    case accessibilityHint
    case accessibilityValue
    case accessibilityAddTraits
    case accessibilityRemoveTraits
    case accessibilityHidden
    case accessibilityIdentifier
    case accessibilityAction

    // Animation
    case animation
    case transition
    case matchedGeometryEffect

    // Environment
    case environment
    case environmentObject

    // Other
    case id
    case tag
    case zIndex
    case overlay
    case border
    case listRowBackground
    case listRowInsets
    case listRowSeparator
    case task
    case onAppear
    case onDisappear
    case onChange

    // UIKit-specific (property assignments, IB attributes)
    case backgroundColor
    case textColor
    case text
    case image
    case alpha
    case hidden
    case isUserInteractionEnabled
    case contentMode
    case constraint
    case addSubview
    case ibFrame
    case ibIdentifier

    case unknown
}
