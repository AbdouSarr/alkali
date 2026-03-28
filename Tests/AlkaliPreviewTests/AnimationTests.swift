//
//  AnimationTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-12.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliPreview
@testable import AlkaliCore

@Suite("Animation Capture Tests")
struct AnimationCaptureTests {

    let capture = AnimationCapture()

    @Test("Linear animation produces correct samples")
    func linearAnimation() {
        let anim = AXIRAnimation(
            trigger: "isVisible",
            curve: .linear(duration: 1.0),
            properties: ["opacity"]
        )
        let data = capture.extractCurve(from: anim)
        #expect(data.duration == 1.0)
        #expect(data.samples.count > 1)
        // First sample should be ~0, last should be ~1
        #expect(data.samples.first! < 0.01)
        #expect(data.samples.last! > 0.99)
        // Linear: should be monotonically increasing
        for i in 1..<data.samples.count {
            #expect(data.samples[i] >= data.samples[i-1] - 0.001)
        }
    }

    @Test("Spring animation has overshoot")
    func springOvershoot() {
        let anim = AXIRAnimation(
            trigger: "isExpanded",
            curve: .spring(response: 0.35, dampingFraction: 0.5),
            properties: ["frame.height"]
        )
        let data = capture.extractCurve(from: anim)
        #expect(data.hasOvershoot) // Underdamped spring should overshoot
    }

    @Test("Deterministic samples")
    func deterministic() {
        let anim = AXIRAnimation(
            trigger: "x",
            curve: .easeInOut(duration: 0.5),
            properties: ["opacity"]
        )
        let data1 = capture.extractCurve(from: anim)
        let data2 = capture.extractCurve(from: anim)
        #expect(data1.samples == data2.samples)
    }

    @Test("No animation produces 2 frames")
    func noAnimation() {
        let anim = AXIRAnimation(
            trigger: "x",
            curve: .none,
            properties: ["opacity"]
        )
        let data = capture.extractCurve(from: anim)
        #expect(data.samples.count == 2)
        #expect(data.duration == 0)
    }
}
