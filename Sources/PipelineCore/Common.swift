#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public protocol ExecutionEventProcessor: Sendable {
    func process(_ executionEvent: ExecutionEvent)
    func closeEventProcessing() throws
    var metadataInfo: String { get }
    var metadataInfoForUserInteraction: String { get }
}

public struct StepID: Hashable, CustomStringConvertible, Sendable {
    
    public let crossModuleFileDesignation: String
    public let functionSignature: String
    
    public init(crossModuleFileDesignation: String, functionSignature: String) {
        self.crossModuleFileDesignation = crossModuleFileDesignation
        self.functionSignature = functionSignature
    }
    
    public var description: String { "\(functionSignature)@\(crossModuleFileDesignation.split(separator: "/", omittingEmptySubsequences: false).first!)" }
}

public let stepPrefix = "step "
public let dispensablePartPrefix = "dispensable part "
public let optionalPartPrefix = "optional part "
public let describedPartPrefix = "doing "

public enum Effectuation: CustomStringConvertible, Sendable {
    
    case step(step: StepID, description: String?)
    case dispensablePart(name: String, description: String?)
    case optionalPart(name: String, description: String?)
    case describedPart(description: String)
    case forcing
    
    public var description: String {
        description(withDescription: true)
    }
    
    public var short: String {
        description(withDescription: false)
    }
    
    public func description(withDescription: Bool) -> String {
        switch self {
        case .step(step: let step, description: let description):
            return "\(stepPrefix)\(step)\(withDescription && description != nil ? " (\(description!))" : "")"
        case .dispensablePart(name: let id, description: let description):
            return "\(dispensablePartPrefix)\"\(id)\"\(withDescription && description != nil ? " (\(description!))" : "")"
        case .optionalPart(name: let id, description: let description):
            return "\(optionalPartPrefix)\"\(id)\"\(withDescription && description != nil ? " (\(description!))" : "")"
        case .describedPart(description: let description):
            return "\(describedPartPrefix)\"\(description)\""
        case .forcing:
            return "forcing"
        }
    }
    
}

extension Array where Element == Effectuation {
    
    var executionPathForEffectuation: String {
        self.map{ $0.short + " -> " }.joined()
    }
    
    var executionPath: String {
        self.map{ $0.short }.joined(separator: " -> ")
    }
    
}

public struct ExecutionInfoFormat: Sendable {
    
    public let withTime: Bool
    public let addMetaDataInfo: Bool
    public let addIndentation: Bool
    public let addType: Bool
    public let addExecutionPath: Bool
    public let addStructuralID: Bool
    
    public init(
        withTime: Bool = false,
        addMetaDataInfo: Bool = false,
        addIndentation: Bool = false,
        addType: Bool = false,
        addExecutionPath: Bool = false,
        addStructuralID: Bool = false
    ) {
        self.withTime = withTime
        self.addMetaDataInfo = addMetaDataInfo
        self.addIndentation = addIndentation
        self.addType = addType
        self.addExecutionPath = addExecutionPath
        self.addStructuralID = addStructuralID
    }
}

public struct ExecutionEvent: Sendable {
    
    public let type: InfoType
    public let originalType: InfoType? // non-appeased
    public let time: Date
    public let level: Int
    public let structuralID: UUID? // not for leaves
    public let coreEvent: ExecutionCoreEvent
    public let effectuationStack: [Effectuation]
    
    public func isMessage() -> Bool { if case .message = coreEvent { true } else { false } }
    
    internal init(
        type: InfoType,
        originalType: InfoType? = nil,
        time: Date = Date.now,
        level: Int,
        structuralID: UUID?,
        coreEvent: ExecutionCoreEvent,
        effectuationStack: [Effectuation]
    ) {
        self.type = type
        self.originalType = originalType
        self.time = time
        self.level = level
        self.structuralID = structuralID
        self.coreEvent = coreEvent
        self.effectuationStack = effectuationStack
    }
    
    public func description(withMetaDataInfo: String?) -> String {
        return description(
            addTime: true,
            addMetaDataInfo: true,
            addIndentation: true,
            addType: true,
            addExecutionPath: true,
            addStructuralID: false,
            withMetaDataInfo: withMetaDataInfo
        )
    }
    
    public func description(
        addTime: Bool = false,
        addMetaDataInfo: Bool = false,
        addIndentation: Bool = false,
        addType: Bool = false,
        addExecutionPath: Bool = false,
        addStructuralID: Bool = false,
        withMetaDataInfo: String? = nil
    ) -> String {
        [
            addTime ? "\(time.description):" : nil,
            addMetaDataInfo && withMetaDataInfo != nil ? "\(withMetaDataInfo!.description):" : nil,
            addIndentation && level > 0 ? "\(String(repeating: " ", count: level * 4 - 1))" : nil,
            addType ? "{\(type)}" : nil,
            coreEvent.description,
            addExecutionPath && !effectuationStack.isEmpty ? "[@@ \(isMessage() ? effectuationStack.executionPath : effectuationStack.executionPathForEffectuation)]" : nil,
            addStructuralID ? "<\(structuralID?.description ?? "")>" : nil
        ].compactMap({ $0 }).joined(separator: " ")
    }
    
    public func description(format executionInfoFormat: ExecutionInfoFormat, withMetaDataInfo: String?) -> String {
        description(
            addTime: executionInfoFormat.withTime,
            addMetaDataInfo: executionInfoFormat.addMetaDataInfo,
            addIndentation: executionInfoFormat.addIndentation,
            addType: executionInfoFormat.addType,
            addExecutionPath: executionInfoFormat.addExecutionPath,
            addStructuralID: executionInfoFormat.addStructuralID,
            withMetaDataInfo: withMetaDataInfo
        )
    }
    
}

public enum ExecutionCoreEvent: Sendable, CustomStringConvertible {
    
    case beginningStep(id: StepID, description: String?, forced: Bool)
    case endingStep(id: StepID, description: String?, forced: Bool)
    case stoppedStep(id: StepID, description: String?)
    case skippingPreviouslyExecutedStep(id: StepID, description: String?)
    case skippingStepInStoppedExecution(id: StepID, description: String?)
    
    case beginningDispensablePart(name: String, description: String?)
    case endingDispensablePart(name: String, description: String?)
    case skippingDispensablePart(name: String, description: String?)
    
    case beginningOptionalPart(name: String, description: String?)
    case endingOptionalPart(name: String, description: String?)
    case skippingOptionalPart(name: String, description: String?)
    
    case beginningDescribedPart(description: String)
    case endingDescribedPart(description: String)
    
    case stoppingExecution(reason: String)
    
    case beginningForcingSteps
    case endingForcingSteps
    
    case message(message: String)
    
    public var description: String {
        switch self {
        case .stoppingExecution(reason: let reason):
            "stopping execution: \(reason)"
        case .beginningStep(id: let id, description: let description, forced: let forced):
            "beginning \(forced ? "forced " : "")step \(id)\(description != nil ? " (\(description!))" : "")"
        case .endingStep(id: let id, description: let description, forced: let forced):
            "ending \(forced ? "forced " : "")step \(id)\(description != nil ? " (\(description!))" : "")"
        case .skippingPreviouslyExecutedStep(id: let id, description: let description):
            "skipping previously executed step \(id)\(description != nil ? " (\(description!))" : "")"
        case .skippingStepInStoppedExecution(id: let id, description: let description):
            "skipping in an stopped environment step \(id)\(description != nil ? " (\(description!))" : "")"
        case .stoppedStep(id: let id, description: let description):
            "stopped step \(id)\(description != nil ? " (\(description!))" : "")"
        case .beginningDispensablePart(name: let name, description: let description):
            "beginning dispensible part \"\(name)\"\(description != nil ? " (\(description!))" : "")"
        case .endingDispensablePart(name: let name, description: let description):
            "ending dispensible part \"\(name)\"\(description != nil ? " (\(description!))" : "")"
        case .skippingDispensablePart(name: let name, description: let description):
            "skipping dispensible part \"\(name)\"\(description != nil ? " (\(description!))" : "")"
        case .beginningOptionalPart(name: let name, description: let description):
            "beginning optional part \"\(name)\"\(description != nil ? " (\(description!))" : "")"
        case .endingOptionalPart(name: let name, description: let description):
            "ending optional part \"\(name)\"\(description != nil ? " (\(description!))" : "")"
        case .skippingOptionalPart(name: let name, description: let description):
            "skipping optional part \"\(name)\"\(description != nil ? " (\(description!))" : "")"
        case .beginningDescribedPart(description: let description):
            "beginning \"\(description)\""
        case .endingDescribedPart(description: let description):
            "ending \"\(description)\""
        case .beginningForcingSteps:
            "beginning forcing steps"
        case .endingForcingSteps:
            "ending forcing steps"
        case .message(message: let message):
            message
        }
    }
}

/// Get the ellapsed seconds since `start`.
/// The time to compare to is either the current time or the value of the argument `reference`.
func elapsedSeconds(start: ContinuousClock.Instant, reference: ContinuousClock.Instant = ContinuousClock.now) -> Double {
    let duration = start.duration(to: reference)
    return Double(duration.attoseconds) / 1e18
}
