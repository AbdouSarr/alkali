//
//  AXIRAnimation.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-06.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct AXIRAnimation: Codable, Hashable, Sendable {
    public let trigger: String
    public let curve: AnimationCurve
    public let properties: [String]
    public let sourceLocation: SourceLocation?

    public init(
        trigger: String,
        curve: AnimationCurve,
        properties: [String],
        sourceLocation: SourceLocation? = nil
    ) {
        self.trigger = trigger
        self.curve = curve
        self.properties = properties
        self.sourceLocation = sourceLocation
    }
}

public enum AnimationCurve: Codable, Hashable, Sendable {
    case spring(response: Double, dampingFraction: Double)
    case easeIn(duration: Double)
    case easeOut(duration: Double)
    case easeInOut(duration: Double)
    case linear(duration: Double)
    case interactiveSpring(response: Double, dampingFraction: Double, blendDuration: Double)
    case none
}
