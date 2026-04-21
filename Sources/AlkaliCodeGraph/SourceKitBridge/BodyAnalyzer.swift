//
//  BodyAnalyzer.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-02.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import SwiftSyntax
import SwiftParser
import AlkaliCore

/// Analyzes SwiftUI view `body` getters using SwiftSyntax to extract
/// view tree structure, modifier chains, and data bindings.
public struct BodyAnalyzer: Sendable {
    public init() {}

    /// Analyze all SwiftUI views in a Swift source file.
    public func analyzeFile(source: String, fileName: String) -> [AnalyzedView] {
        let sourceFile = Parser.parse(source: source)
        var views: [AnalyzedView] = []
        let visitor = ViewFinder(fileName: fileName)
        visitor.walk(sourceFile)
        views = visitor.views
        return views
    }
}

public enum ViewFramework: String, Sendable, Codable, Hashable {
    case swiftUI
    case uiKit
    case interfaceBuilder  // XIB/Storyboard-sourced
}

public struct AnalyzedView: Sendable {
    public let name: String
    public let sourceLocation: AlkaliCore.SourceLocation
    public let bodyAST: ViewBodyAST?
    public let dataBindings: [AXIRDataBinding]
    public let framework: ViewFramework
    /// Direct superclass name (UIKit only) — used for transitive resolution.
    public let superclass: String?

    public init(
        name: String,
        sourceLocation: AlkaliCore.SourceLocation,
        bodyAST: ViewBodyAST?,
        dataBindings: [AXIRDataBinding],
        framework: ViewFramework = .swiftUI,
        superclass: String? = nil
    ) {
        self.name = name
        self.sourceLocation = sourceLocation
        self.bodyAST = bodyAST
        self.dataBindings = dataBindings
        self.framework = framework
        self.superclass = superclass
    }
}

/// Known UIKit base types. Any class directly inheriting one of these is considered a UIKit view/controller.
public let uikitBaseTypes: Set<String> = [
    // Controllers
    "UIViewController", "UITableViewController", "UICollectionViewController",
    "UINavigationController", "UITabBarController", "UIPageViewController",
    "UISplitViewController", "UIAlertController", "UIDocumentPickerViewController",
    "UIImagePickerController", "UIActivityViewController",
    // Views
    "UIView", "UIControl", "UIButton", "UILabel", "UIImageView",
    "UIScrollView", "UITableView", "UICollectionView", "UIStackView",
    "UIVisualEffectView", "UITextField", "UITextView", "UIWindow",
    "UISwitch", "UISlider", "UISegmentedControl", "UIProgressView",
    "UIActivityIndicatorView", "UIPickerView", "UIDatePicker",
    // Cells
    "UITableViewCell", "UICollectionViewCell", "UICollectionReusableView",
    // Gesture
    "UIGestureRecognizer",
    // UIKit-adjacent frameworks commonly used as roots
    "SKView", "SKScene", "MTKView", "MKMapView", "PHPickerViewController",
    "WKWebView", "SCNView", "ARView", "ARSCNView", "ARSKView"
]

public indirect enum ViewBodyAST: Sendable {
    case leaf(viewType: String, sourceLocation: AlkaliCore.SourceLocation, arguments: [String])
    case container(viewType: String, sourceLocation: AlkaliCore.SourceLocation, children: [ViewBodyAST])
    case modified(base: ViewBodyAST, modifier: ModifierCall)
    case conditional(condition: String, trueBranch: ViewBodyAST?, falseBranch: ViewBodyAST?, sourceLocation: AlkaliCore.SourceLocation)
    case forEach(collectionExpr: String, itemType: String?, body: ViewBodyAST?, sourceLocation: AlkaliCore.SourceLocation)
    case viewReference(typeName: String, sourceLocation: AlkaliCore.SourceLocation, arguments: [String])
}

public struct ModifierCall: Sendable {
    public let name: String
    public let arguments: [String: String]
    public let sourceLocation: AlkaliCore.SourceLocation

    public init(name: String, arguments: [String: String] = [:], sourceLocation: AlkaliCore.SourceLocation) {
        self.name = name
        self.arguments = arguments
        self.sourceLocation = sourceLocation
    }
}

// MARK: - SwiftSyntax Visitor

private final class ViewFinder: SyntaxVisitor {
    let fileName: String
    var views: [AnalyzedView] = []
    private var currentSource: String = ""

    init(fileName: String) {
        self.fileName = fileName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if this struct conforms to View
        guard let inheritanceClause = node.inheritanceClause else { return .visitChildren }
        let conformsToView = inheritanceClause.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "View"
        }
        guard conformsToView else { return .visitChildren }

        let structName = node.name.text
        let loc = sourceLocation(of: node)

        // Find data bindings (property wrappers)
        var bindings: [AXIRDataBinding] = []
        for member in node.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                if let binding = extractDataBinding(from: varDecl) {
                    bindings.append(binding)
                }
            }
        }

        // Find body getter
        var bodyAST: ViewBodyAST? = nil
        for member in node.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                let isBody = varDecl.bindings.contains { binding in
                    binding.pattern.trimmedDescription == "body"
                }
                if isBody {
                    if let accessorBlock = varDecl.bindings.first?.accessorBlock {
                        bodyAST = analyzeBody(accessorBlock)
                    }
                }
            }
        }

        views.append(AnalyzedView(
            name: structName,
            sourceLocation: loc,
            bodyAST: bodyAST,
            dataBindings: bindings,
            framework: .swiftUI,
            superclass: nil
        ))

        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // UIKit views/controllers are classes; detect by direct superclass in the inheritance clause.
        // The first inherited identifier in a Swift class decl is always the superclass (if any).
        guard let inheritanceClause = node.inheritanceClause,
              let first = inheritanceClause.inheritedTypes.first else {
            return .visitChildren
        }
        let superName = first.type.trimmedDescription
        let className = node.name.text
        let loc = sourceLocation(of: node)

        // Extract UIKit data bindings (IBOutlet, IBAction, @Published, delegate-conformance, etc.).
        let bindings = extractUIKitBindings(from: node)

        views.append(AnalyzedView(
            name: className,
            sourceLocation: loc,
            bodyAST: nil,
            dataBindings: bindings,
            framework: .uiKit,
            superclass: superName
        ))

        return .visitChildren
    }

    /// Extract UIKit-style data bindings from a class: IBOutlet, IBAction, @Published, etc.
    private func extractUIKitBindings(from node: ClassDeclSyntax) -> [AXIRDataBinding] {
        var bindings: [AXIRDataBinding] = []
        for member in node.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                if let binding = extractUIKitVarBinding(from: varDecl) {
                    bindings.append(binding)
                }
            }
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                if let binding = extractUIKitActionBinding(from: funcDecl) {
                    bindings.append(binding)
                }
            }
        }
        // Delegate / DataSource conformance
        if let clause = node.inheritanceClause {
            for inherited in clause.inheritedTypes {
                let name = inherited.type.trimmedDescription
                if name.hasSuffix("Delegate") || name.hasSuffix("DataSource") {
                    bindings.append(AXIRDataBinding(
                        property: "self",
                        bindingKind: .delegate,
                        sourceType: name
                    ))
                }
            }
        }
        return bindings
    }

    private func extractUIKitVarBinding(from varDecl: VariableDeclSyntax) -> AXIRDataBinding? {
        for attribute in varDecl.attributes {
            guard let attr = attribute.as(AttributeSyntax.self) else { continue }
            let attrName = attr.attributeName.trimmedDescription

            let bindingKind: BindingKind?
            switch attrName {
            case "IBOutlet":      bindingKind = .iboutlet
            case "IBInspectable": bindingKind = .ibinspectable
            case "Published":     bindingKind = .published
            case "Binding":       bindingKind = .binding
            case "State":         bindingKind = .state
            default:              bindingKind = nil
            }
            guard let kind = bindingKind else { continue }

            let propertyName = varDecl.bindings.first?.pattern.trimmedDescription ?? "unknown"
            let typeName = varDecl.bindings.first?.typeAnnotation?.type.trimmedDescription ?? "Unknown"
            return AXIRDataBinding(property: propertyName, bindingKind: kind, sourceType: typeName)
        }
        return nil
    }

    private func extractUIKitActionBinding(from funcDecl: FunctionDeclSyntax) -> AXIRDataBinding? {
        for attribute in funcDecl.attributes {
            guard let attr = attribute.as(AttributeSyntax.self) else { continue }
            let attrName = attr.attributeName.trimmedDescription
            if attrName == "IBAction" {
                return AXIRDataBinding(property: funcDecl.name.text, bindingKind: .ibaction, sourceType: "IBAction")
            }
            if attrName == "objc" && funcDecl.signature.parameterClause.parameters.count <= 2 {
                return AXIRDataBinding(property: funcDecl.name.text, bindingKind: .objcAction, sourceType: "@objc")
            }
        }
        return nil
    }

    private func extractDataBinding(from varDecl: VariableDeclSyntax) -> AXIRDataBinding? {
        for attribute in varDecl.attributes {
            guard let attr = attribute.as(AttributeSyntax.self) else { continue }
            let attrName = attr.attributeName.trimmedDescription

            let bindingKind: BindingKind?
            switch attrName {
            case "State": bindingKind = .state
            case "Binding": bindingKind = .binding
            case "ObservedObject": bindingKind = .observedObject
            case "EnvironmentObject": bindingKind = .environmentObject
            case "Environment": bindingKind = .environment
            case "StateObject": bindingKind = .stateObject
            case "Observable": bindingKind = .observable
            default: bindingKind = nil
            }

            guard let kind = bindingKind else { continue }

            let propertyName = varDecl.bindings.first?.pattern.trimmedDescription ?? "unknown"
            let typeName = varDecl.bindings.first?.typeAnnotation?.type.trimmedDescription ?? "Unknown"

            return AXIRDataBinding(property: propertyName, bindingKind: kind, sourceType: typeName)
        }
        return nil
    }

    private func analyzeBody(_ accessorBlock: AccessorBlockSyntax) -> ViewBodyAST? {
        // The body can be a code block or getter
        switch accessorBlock.accessors {
        case .getter(let codeBlockItemList):
            return analyzeCodeBlock(codeBlockItemList)
        case .accessors(let accessorList):
            for accessor in accessorList {
                if accessor.accessorSpecifier.text == "get" {
                    if let body = accessor.body {
                        return analyzeCodeBlock(body.statements)
                    }
                }
            }
            return nil
        }
    }

    private func analyzeCodeBlock(_ statements: CodeBlockItemListSyntax) -> ViewBodyAST? {
        // Body usually has one expression (the view tree)
        guard let lastStmt = statements.last else { return nil }
        return analyzeExpression(lastStmt.item)
    }

    private func analyzeExpression(_ syntax: CodeBlockItemSyntax.Item) -> ViewBodyAST? {
        switch syntax {
        case .expr(let expr):
            return analyzeExpr(expr)
        case .stmt(let stmt):
            // if/else can appear as either ExpressionStmt or directly
            if let exprStmt = stmt.as(ExpressionStmtSyntax.self) {
                return analyzeExpr(exprStmt.expression)
            }
            if let ifStmt = stmt.as(IfExprSyntax.self) {
                return analyzeIfExpr(ifStmt)
            }
            return nil
        default:
            return nil
        }
    }

    private func analyzeExpr(_ expr: ExprSyntax) -> ViewBodyAST? {
        // Function call: VStack { ... }, Text("hello"), etc.
        if let functionCall = expr.as(FunctionCallExprSyntax.self) {
            return analyzeFunctionCall(functionCall)
        }

        // Member access with call: something.modifier(...)
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            // This could be a modifier chain
            return nil
        }

        // If expression
        if let ifExpr = expr.as(IfExprSyntax.self) {
            return analyzeIfExpr(ifExpr)
        }

        return nil
    }

    private func analyzeFunctionCall(_ call: FunctionCallExprSyntax) -> ViewBodyAST? {
        // Check if this is a modifier call (base.modifier(...))
        if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            if let base = memberAccess.base {
                // This is base.modifier(args)
                let modifierName = memberAccess.declName.baseName.text
                let args = extractArguments(call.arguments)
                let loc = sourceLocation(of: call)

                if let baseAST = analyzeExpr(base) {
                    let modifier = ModifierCall(name: modifierName, arguments: args, sourceLocation: loc)
                    return .modified(base: baseAST, modifier: modifier)
                }
            }
        }

        let calledName = call.calledExpression.trimmedDescription
        let loc = sourceLocation(of: call)
        let args = call.arguments.map { $0.expression.trimmedDescription }

        // Check for container views with trailing closure
        let containerTypes: Set<String> = ["VStack", "HStack", "ZStack", "LazyVStack", "LazyHStack",
                                            "Group", "ScrollView", "List", "NavigationStack",
                                            "NavigationView", "TabView", "Form", "Section"]

        if containerTypes.contains(calledName) {
            var children: [ViewBodyAST] = []
            if let trailingClosure = call.trailingClosure {
                children = extractChildren(from: trailingClosure.statements)
            }
            return .container(viewType: calledName, sourceLocation: loc, children: children)
        }

        // Check for ForEach
        if calledName == "ForEach" {
            let collectionExpr = call.arguments.first?.expression.trimmedDescription ?? ""
            var bodyAST: ViewBodyAST? = nil
            if let trailingClosure = call.trailingClosure {
                bodyAST = analyzeCodeBlock(trailingClosure.statements)
            }
            return .forEach(collectionExpr: collectionExpr, itemType: nil, body: bodyAST, sourceLocation: loc)
        }

        // Known leaf views
        let leafTypes: Set<String> = ["Text", "Image", "Button", "Toggle", "TextField",
                                       "Slider", "Picker", "DatePicker", "Spacer", "Divider",
                                       "Color", "ProgressView", "Label", "Link", "Map",
                                       "NavigationLink"]

        if leafTypes.contains(calledName) {
            return .leaf(viewType: calledName, sourceLocation: loc, arguments: args)
        }

        // Unknown — treat as a view reference (custom view)
        return .viewReference(typeName: calledName, sourceLocation: loc, arguments: args)
    }

    private func analyzeIfExpr(_ ifExpr: IfExprSyntax) -> ViewBodyAST? {
        let condition = ifExpr.conditions.trimmedDescription
        let loc = sourceLocation(of: ifExpr)

        let trueBranch = analyzeCodeBlock(ifExpr.body.statements)
        let falseBranch: ViewBodyAST?
        if let elseBody = ifExpr.elseBody {
            switch elseBody {
            case .codeBlock(let block):
                falseBranch = analyzeCodeBlock(block.statements)
            case .ifExpr(let nestedIf):
                falseBranch = analyzeIfExpr(nestedIf)
            }
        } else {
            falseBranch = nil
        }

        return .conditional(condition: condition, trueBranch: trueBranch, falseBranch: falseBranch, sourceLocation: loc)
    }

    private func extractChildren(from statements: CodeBlockItemListSyntax) -> [ViewBodyAST] {
        var children: [ViewBodyAST] = []
        for stmt in statements {
            if let ast = analyzeExpression(stmt.item) {
                children.append(ast)
            }
        }
        return children
    }

    private func extractArguments(_ args: LabeledExprListSyntax) -> [String: String] {
        var result: [String: String] = [:]
        for (index, arg) in args.enumerated() {
            let key = arg.label?.text ?? "\(index)"
            result[key] = arg.expression.trimmedDescription
        }
        return result
    }

    private func sourceLocation(of node: some SyntaxProtocol) -> AlkaliCore.SourceLocation {
        let position = node.startLocation(converter: SwiftSyntax.SourceLocationConverter(fileName: fileName, tree: node.root))
        return AlkaliCore.SourceLocation(
            file: fileName,
            line: position.line,
            column: position.column
        )
    }
}
