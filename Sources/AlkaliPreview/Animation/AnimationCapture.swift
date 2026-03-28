//
//  AnimationCapture.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-10.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Captures animation frames for state transitions.
public struct AnimationCapture: Sendable {
    public init() {}

    /// Build animation metadata from AXIR animation info.
    public func extractCurve(from animation: AXIRAnimation) -> AnimationCurveData {
        let (duration, samples) = sampleCurve(animation.curve, fps: 60)
        return AnimationCurveData(
            curve: animation.curve,
            trigger: animation.trigger,
            properties: animation.properties,
            duration: duration,
            samples: samples
        )
    }

    private func sampleCurve(_ curve: AnimationCurve, fps: Int) -> (Double, [Double]) {
        let frameCount: Int
        let duration: Double

        switch curve {
        case .spring(let response, _):
            duration = response * 4
            frameCount = Int(duration * Double(fps))
        case .easeIn(let d), .easeOut(let d), .easeInOut(let d), .linear(let d):
            duration = d
            frameCount = Int(d * Double(fps))
        case .interactiveSpring(let response, _, _):
            duration = response * 3
            frameCount = Int(duration * Double(fps))
        case .none:
            return (0, [0, 1])
        }

        var samples: [Double] = []
        for i in 0...max(frameCount, 1) {
            let t = Double(i) / Double(max(frameCount, 1))
            samples.append(interpolate(curve: curve, t: t))
        }
        return (duration, samples)
    }

    private func interpolate(curve: AnimationCurve, t: Double) -> Double {
        switch curve {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .spring(_, let damping):
            // Simplified spring model
            let omega = 2 * Double.pi / 0.35
            let decay = exp(-damping * omega * t * 0.35)
            return 1 - decay * cos(omega * t * (1 - damping))
        case .interactiveSpring(_, let damping, _):
            let omega = 2 * Double.pi / 0.35
            let decay = exp(-damping * omega * t * 0.35)
            return 1 - decay * cos(omega * t * (1 - damping))
        case .none:
            return t >= 1 ? 1 : 0
        }
    }
}

public struct AnimationCurveData: Sendable {
    public let curve: AnimationCurve
    public let trigger: String
    public let properties: [String]
    public let duration: Double
    public let samples: [Double]

    public init(curve: AnimationCurve, trigger: String, properties: [String], duration: Double, samples: [Double]) {
        self.curve = curve
        self.trigger = trigger
        self.properties = properties
        self.duration = duration
        self.samples = samples
    }

    public var hasOvershoot: Bool {
        samples.contains(where: { $0 > 1.01 })
    }
}
