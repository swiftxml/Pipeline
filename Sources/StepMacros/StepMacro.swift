import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

import SwiftSyntax
import SwiftSyntaxMacros

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

fileprivate extension AbstractSourceLocation {
    var fileWithCorrectedStringRepresentation: ExprSyntax {
        var filePath = "\(file)"
        if filePath.contains(/^#+.*"#+$/) {
            filePath.replace(/^#+"/, with: "")
            filePath.replace(/"#+$/, with: "")
            filePath.replace(#"\"#, with: #"\\"#)
            filePath.replace("\"", with: #"\""#)
            return "\(raw: "\"\(filePath)\"")"
        } else {
            return file
        }
    }
}

extension SyntaxStringInterpolation {
    
    mutating func appendInterpolation<Node: SyntaxProtocol>(
        _ node: Node,
        location: AbstractSourceLocation?,
        lineOffset: Int? = nil,
        close: Bool = true
    ) {
        if let location {
            let line = if let lineOffset {
                ExprSyntax("\(literal: Int(location.line.as(IntegerLiteralExprSyntax.self)?.literal.text ?? "0")! + lineOffset)")
            } else {
                location.line
            }
            var block = CodeBlockItemListSyntax {
                "#sourceLocation(file: \(location.fileWithCorrectedStringRepresentation), line: \(line))"
                "\(node)"
            }
            if close {
                block.append("\n#sourceLocation()")
            }
            appendInterpolation(block)
        } else {
            appendInterpolation(node)
        }
    }
}

public struct StepMacro: BodyMacro {
    
    public static var formatMode: FormatMode { .disabled }
    
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        guard let body = declaration.body else { return [] }
        let newBody = CodeIndentingRewriter(style: .unindentSpaces(4)).rewrite(body).as(CodeBlockSyntax.self)
//        let newBody = AutoGuardSelfRewriter().rewrite(body.recursivelyTrimmed).as(CodeBlockSyntax.self)
        if let arguments = node.arguments {
            return [
                """
                execution.effectuate(\(raw: arguments), checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                    \((newBody ?? body).statements, location: context.location(of: declaration.body!.statements, at: .beforeLeadingTrivia, filePathMode: .filePath), lineOffset: 1)
                }
                """
            ]
        } else {
            return [
                """
                execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                    \((newBody ?? body).statements, location: context.location(of: declaration.body!.statements, at: .beforeLeadingTrivia, filePathMode: .filePath), lineOffset: 1)
                }
                """
            ]
        }
    }
    
}
