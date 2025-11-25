#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import Localization

// The message type that informs about the severity a message.
//
// It conforms to `Comparable` so there is an order of severity.
public enum InfoType: Comparable, Codable, Sendable, Hashable, CaseIterable {
    
    /// Debugging information.
    case debug
    
    /// Information about the progress (e.g. the steps being executed).
    case progress
    
    /// Information from the processing.
    case info
    
    /// Information about the execution for a work item, e.g. starting.
    case iteration
    
    /// Warnings from the processing.
    case warning
    
    /// Errors from the processing.
    case error
    
    /// A fatal error, the execution (for the data item being processed) is
    /// then abandoned.
    case fatal
    
    /// The program or process that has been startet to be in charge for
    /// the whole processing of a work item is lost (crashed or hanging).
    case loss
    
    /// A deadly error, i.e. not only the processing for one work item
    /// has to be abandoned, but the whole processing cannot continue.
    case deadly

}

fileprivate extension String {
    
    func withPositionInfo(_ positionInfo: String?) -> String {
        if let positionInfo {
            "\(self) @ \(positionInfo)"
        } else {
            self
        }
    }
    
}

extension Execution {
    
    public func log(_ type: InfoType, _ message: String, at positionInfo: String? = nil) {
        let actualType: InfoType
        let orginalType: InfoType?
        if let appeaseType = appeaseTypes.last, type > appeaseType {
            actualType = appeaseType
            orginalType = type
        } else {
            actualType = type
            orginalType = nil
        }
        executionEventProcessor.process(
            ExecutionEvent(
                type: actualType,
                originalType: orginalType,
                level: level,
                structuralID: nil, // is a leave, no structural ID necessary
                coreEvent: .message(
                    message: message.withPositionInfo(positionInfo)
                ),
                effectuationStack: effectuationStack
            )
        )
        if type >= .fatal, stopAtFatalError {
            stop(reason: "\(type) error occurred")
        }
    }
    
    public func log(_ type: InfoType, _ message: MultiLanguageText, at positionInfo: String? = nil) {
        log(type, message.forLanguage(language).withPositionInfo(positionInfo))
    }
    
    public func log(_ message: Message, at positionInfo: String? = nil, _ arguments: [String]) {
        let core = message.fact.forLanguage(language).filling(withArguments: arguments).withPositionInfo(positionInfo)
        let idPrefix = message.id != nil ? "[\(message.id!)]: " : ""
        let solutionPostfix = message.solution != nil ? " → \(message.solution!.forLanguage(language).filling(withArguments: arguments))" : ""
        log(message.type, "\(idPrefix)\(core)\(solutionPostfix)")
    }
    
    public func log(_ message: Message, at positionInfo: String? = nil, _ arguments: String...) {
        log(message, at: positionInfo, arguments)
    }
    
}

extension AsyncExecution {
    
    public func log(_ type: InfoType, _ message: String, at positionInfo: String? = nil) async {
        let actualType: InfoType
        let orginalType: InfoType?
        if let appeaseType = synchronousExecution.appeaseTypes.last, type > appeaseType {
            actualType = appeaseType
            orginalType = type
        } else {
            actualType = type
            orginalType = nil
        }
        synchronousExecution.executionEventProcessor.process(
            ExecutionEvent(
                type: actualType,
                originalType: orginalType,
                level: synchronousExecution.level,
                structuralID: nil, // is a leave, no structural ID necessary
                coreEvent: .message(
                    message: message.withPositionInfo(positionInfo)
                ),
                effectuationStack: synchronousExecution.effectuationStack
            )
        )
        if type >= .fatal, synchronousExecution.stopAtFatalError {
            synchronousExecution.stop(reason: "\(type) error occurred")
        }
    }
    
    public func log(_ type: InfoType, _ message: MultiLanguageText, at positionInfo: String? = nil) async {
        await log(type, message.forLanguage(synchronousExecution.language).withPositionInfo(positionInfo))
    }
    
    public func log(_ message: Message, at positionInfo: String? = nil, _ arguments: [String]) async {
        let core = message.fact.forLanguage(synchronousExecution.language).filling(withArguments: arguments).withPositionInfo(positionInfo)
        let idPrefix = message.id != nil ? "[\(message.id!)]: " : ""
        let solutionPostfix = message.solution != nil ? " → \(message.solution!.forLanguage(synchronousExecution.language).filling(withArguments: arguments))" : ""
        await log(message.type, "\(idPrefix)\(core)\(solutionPostfix)")
    }
    
    public func log(_ message: Message, at positionInfo: String? = nil, _ arguments: String...) async {
        await log(message, at: positionInfo, arguments)
    }
    
}

/// A message contains a message ID, a message type, and fact and maybe solution as `MultiLanguageText`.
public struct Message {
    
    public let id: String?
    public let type: InfoType
    public let fact: MultiLanguageText
    public let solution: MultiLanguageText?
    
    public init(id: String?, type: InfoType, fact: MultiLanguageText, solution: MultiLanguageText? = nil) {
        self.id = id
        self.type = type
        self.fact = fact
        self.solution = solution
    }
    
    public func setting(type newType: InfoType) -> Message {
        return Message(id: id, type: newType, fact: fact, solution: solution)
    }
    
}

public extension MultiLanguageText {
    
    /// Replaces the placeholders in all message texts of an instance of
    /// `LocalizingMessage` by the accordings arguments.
     func filling(withArguments arguments: [String]?) -> MultiLanguageText {
        guard let arguments = arguments else {
            return self
        }
        var newMessage = [Language:String]()
        self.forEach{ language, text in
            newMessage[language] = text.filling(withArguments: arguments)
        }
        return newMessage
    }
    
    /// Replaces the placeholders in all message texts of an instance of
    /// `LocalizingMessage` by the accordings arguments.
    func filling(withArguments arguments: String...) -> MultiLanguageText {
        filling(withArguments: arguments)
    }
}

extension String {
    
    /// A message text can have placeholders $1, $2, ... which are
    /// replaced by the additional textual arguments of the `log`
    /// method. This function replaces the placeholders by those
    /// arguments.
    func filling(withArguments arguments: [String]) -> String {
        var i = 0
        var s = self
        arguments.forEach { argument in
            s = s.replacing("$\(i)", with: argument)
            i += 1
        }
        return s
    }
    
    /// A message text can have placeholders $1, $2, ... which are
    /// replaced by the additional textual arguments of the `log`
    /// method. This function replaces the placeholders by those
    /// arguments.
    func filling(withArguments arguments: String...) -> String {
        filling(withArguments: arguments)
    }
    
}
