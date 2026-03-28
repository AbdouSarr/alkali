//
//  LiveEditor.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-19.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Represents a live edit to a modifier value, ready to be compiled and patched.
public struct LiveEdit: Sendable {
    public let viewID: AlkaliID
    public let modifierType: ModifierType
    public let parameterKey: String
    public let oldValue: AXIRValue
    public let newValue: AXIRValue
    public let sourceLocation: SourceLocation

    public init(viewID: AlkaliID, modifierType: ModifierType, parameterKey: String,
                oldValue: AXIRValue, newValue: AXIRValue, sourceLocation: SourceLocation) {
        self.viewID = viewID
        self.modifierType = modifierType
        self.parameterKey = parameterKey
        self.oldValue = oldValue
        self.newValue = newValue
        self.sourceLocation = sourceLocation
    }

    /// Generate the source text replacement for this edit.
    public var sourceReplacement: (old: String, new: String)? {
        guard let oldText = valueToSourceText(oldValue),
              let newText = valueToSourceText(newValue) else { return nil }
        return (oldText, newText)
    }

    private func valueToSourceText(_ value: AXIRValue) -> String? {
        switch value {
        case .int(let v): return "\(v)"
        case .float(let v):
            if v == v.rounded() { return "\(Int(v))" }
            return "\(v)"
        case .string(let v): return "\"\(v)\""
        case .bool(let v): return "\(v)"
        case .color(let c): return "Color(red: \(c.red), green: \(c.green), blue: \(c.blue))"
        default: return nil
        }
    }
}

/// Applies live edits to source files.
public struct SourceWriteback: Sendable {
    public init() {}

    /// Write a live edit back to the source file.
    public func apply(edit: LiveEdit) throws {
        guard let replacement = edit.sourceReplacement else {
            throw WritebackError.cannotGenerateReplacement
        }

        let filePath = edit.sourceLocation.file
        var source = try String(contentsOfFile: filePath, encoding: .utf8)

        // Find and replace the old value with the new value near the source location
        if let range = source.range(of: replacement.old) {
            source.replaceSubrange(range, with: replacement.new)
            try source.write(toFile: filePath, atomically: true, encoding: .utf8)
        } else {
            throw WritebackError.valueNotFoundInSource
        }
    }
}

public enum WritebackError: Error, LocalizedError {
    case cannotGenerateReplacement
    case valueNotFoundInSource

    public var errorDescription: String? {
        switch self {
        case .cannotGenerateReplacement: return "Cannot generate source replacement for this value type"
        case .valueNotFoundInSource: return "Original value not found in source file"
        }
    }
}
