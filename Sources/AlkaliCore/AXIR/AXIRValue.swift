//
//  AXIRValue.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-04.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public enum AXIRValue: Codable, Hashable, Sendable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)
    case color(AXIRColor)
    case assetReference(catalog: String, name: String)
    case enumCase(type: String, caseName: String)
    case binding(property: String, sourceType: String)
    case environment(key: String)
    case edgeInsets(top: Double, leading: Double, bottom: Double, trailing: Double)
    case size(width: Double, height: Double)
    case point(x: Double, y: Double)
    case array([AXIRValue])
    case null

    enum CodingKeys: String, CodingKey {
        case type, value
    }

    enum ValueType: String, Codable {
        case int, float, string, bool, color, assetReference, enumCase
        case binding, environment, edgeInsets, size, point, array, null
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value))
        case .float:
            self = .float(try container.decode(Double.self, forKey: .value))
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .color:
            self = .color(try container.decode(AXIRColor.self, forKey: .value))
        case .assetReference:
            let ref = try container.decode(AssetRef.self, forKey: .value)
            self = .assetReference(catalog: ref.catalog, name: ref.name)
        case .enumCase:
            let ec = try container.decode(EnumCaseRef.self, forKey: .value)
            self = .enumCase(type: ec.type, caseName: ec.caseName)
        case .binding:
            let b = try container.decode(BindingRef.self, forKey: .value)
            self = .binding(property: b.property, sourceType: b.sourceType)
        case .environment:
            self = .environment(key: try container.decode(String.self, forKey: .value))
        case .edgeInsets:
            let ei = try container.decode(EdgeInsetsRef.self, forKey: .value)
            self = .edgeInsets(top: ei.top, leading: ei.leading, bottom: ei.bottom, trailing: ei.trailing)
        case .size:
            let s = try container.decode(SizeRef.self, forKey: .value)
            self = .size(width: s.width, height: s.height)
        case .point:
            let p = try container.decode(PointRef.self, forKey: .value)
            self = .point(x: p.x, y: p.y)
        case .array:
            self = .array(try container.decode([AXIRValue].self, forKey: .value))
        case .null:
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .int(let v):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(v, forKey: .value)
        case .float(let v):
            try container.encode(ValueType.float, forKey: .type)
            try container.encode(v, forKey: .value)
        case .string(let v):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(v, forKey: .value)
        case .bool(let v):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(v, forKey: .value)
        case .color(let v):
            try container.encode(ValueType.color, forKey: .type)
            try container.encode(v, forKey: .value)
        case .assetReference(let catalog, let name):
            try container.encode(ValueType.assetReference, forKey: .type)
            try container.encode(AssetRef(catalog: catalog, name: name), forKey: .value)
        case .enumCase(let type, let caseName):
            try container.encode(ValueType.enumCase, forKey: .type)
            try container.encode(EnumCaseRef(type: type, caseName: caseName), forKey: .value)
        case .binding(let property, let sourceType):
            try container.encode(ValueType.binding, forKey: .type)
            try container.encode(BindingRef(property: property, sourceType: sourceType), forKey: .value)
        case .environment(let key):
            try container.encode(ValueType.environment, forKey: .type)
            try container.encode(key, forKey: .value)
        case .edgeInsets(let top, let leading, let bottom, let trailing):
            try container.encode(ValueType.edgeInsets, forKey: .type)
            try container.encode(EdgeInsetsRef(top: top, leading: leading, bottom: bottom, trailing: trailing), forKey: .value)
        case .size(let width, let height):
            try container.encode(ValueType.size, forKey: .type)
            try container.encode(SizeRef(width: width, height: height), forKey: .value)
        case .point(let x, let y):
            try container.encode(ValueType.point, forKey: .type)
            try container.encode(PointRef(x: x, y: y), forKey: .value)
        case .array(let values):
            try container.encode(ValueType.array, forKey: .type)
            try container.encode(values, forKey: .value)
        case .null:
            try container.encode(ValueType.null, forKey: .type)
            try container.encode(true, forKey: .value)
        }
    }
}

// Helper types for Codable
private struct AssetRef: Codable { let catalog: String; let name: String }
private struct EnumCaseRef: Codable { let type: String; let caseName: String }
private struct BindingRef: Codable { let property: String; let sourceType: String }
private struct EdgeInsetsRef: Codable { let top: Double; let leading: Double; let bottom: Double; let trailing: Double }
private struct SizeRef: Codable { let width: Double; let height: Double }
private struct PointRef: Codable { let x: Double; let y: Double }

public struct AXIRColor: Codable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    public let colorSpace: String

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0, colorSpace: String = "sRGB") {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.colorSpace = colorSpace
    }

    public var hexString: String {
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
