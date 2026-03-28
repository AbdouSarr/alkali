//
//  EnvironmentOverrides.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-19.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct EnvironmentOverrides: Codable, Hashable, Sendable {
    public var colorScheme: ColorSchemeOverride?
    public var dynamicTypeSize: DynamicTypeSizeOverride?
    public var locale: String?
    public var layoutDirection: LayoutDirectionOverride?
    public var horizontalSizeClass: SizeClassOverride?
    public var verticalSizeClass: SizeClassOverride?
    public var accessibilityEnabled: Bool?
    public var reduceMotion: Bool?
    public var reduceTransparency: Bool?
    public var customValues: [String: String]

    public init(
        colorScheme: ColorSchemeOverride? = nil,
        dynamicTypeSize: DynamicTypeSizeOverride? = nil,
        locale: String? = nil,
        layoutDirection: LayoutDirectionOverride? = nil,
        horizontalSizeClass: SizeClassOverride? = nil,
        verticalSizeClass: SizeClassOverride? = nil,
        accessibilityEnabled: Bool? = nil,
        reduceMotion: Bool? = nil,
        reduceTransparency: Bool? = nil,
        customValues: [String: String] = [:]
    ) {
        self.colorScheme = colorScheme
        self.dynamicTypeSize = dynamicTypeSize
        self.locale = locale
        self.layoutDirection = layoutDirection
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
        self.accessibilityEnabled = accessibilityEnabled
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.customValues = customValues
    }

    public static let `default` = EnvironmentOverrides()
}

public enum ColorSchemeOverride: String, Codable, Hashable, Sendable, CaseIterable {
    case light
    case dark
}

public enum DynamicTypeSizeOverride: String, Codable, Hashable, Sendable, CaseIterable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge
    case accessibility1
    case accessibility2
    case accessibility3
    case accessibility4
    case accessibility5
}

public enum LayoutDirectionOverride: String, Codable, Hashable, Sendable, CaseIterable {
    case leftToRight
    case rightToLeft
}

public enum SizeClassOverride: String, Codable, Hashable, Sendable, CaseIterable {
    case compact
    case regular
}
