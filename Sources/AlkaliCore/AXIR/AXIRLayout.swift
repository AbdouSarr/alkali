//
//  AXIRLayout.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-05.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct AXIRLayout: Codable, Hashable, Sendable {
    public let frame: AXIRRect
    public let absoluteFrame: AXIRRect
    public let effectivePadding: AXIREdgeInsets
    public let safeAreaInsets: AXIREdgeInsets
    public let layoutPriority: Double

    public init(
        frame: AXIRRect,
        absoluteFrame: AXIRRect,
        effectivePadding: AXIREdgeInsets = .zero,
        safeAreaInsets: AXIREdgeInsets = .zero,
        layoutPriority: Double = 0
    ) {
        self.frame = frame
        self.absoluteFrame = absoluteFrame
        self.effectivePadding = effectivePadding
        self.safeAreaInsets = safeAreaInsets
        self.layoutPriority = layoutPriority
    }
}

public struct AXIRRect: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = AXIRRect(x: 0, y: 0, width: 0, height: 0)
}

public struct AXIREdgeInsets: Codable, Hashable, Sendable {
    public let top: Double
    public let leading: Double
    public let bottom: Double
    public let trailing: Double

    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = AXIREdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}
