#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import Localization

public struct ExecutionState: Sendable {
    let language: Language
    let executionEventProcessor: any ExecutionEventProcessor
    let stopAtFatalError: Bool
    let activatedOptions: Set<String>?
    let dispenseWith: Set<String>?
    var executedSteps = Set<StepID>()
    let effectuationStack: [Effectuation]
    let waitNotPausedFunction: (@Sendable () -> ())?
    let forceValues: [Bool]
    let appeaseTypes: [InfoType]
    let stopped: Bool
}

/// Manages the execution of steps. In particular
/// - prevents double execution of steps
/// - keeps global information for logging
public final class Execution {
    
    public var state: ExecutionState {
        ExecutionState(
            language: language,
            executionEventProcessor: executionEventProcessor,
            stopAtFatalError: stopAtFatalError,
            activatedOptions: activatedOptions,
            dispenseWith: dispenseWith,
            effectuationStack: effectuationStack,
            waitNotPausedFunction: waitNotPausedFunction,
            forceValues: forceValues,
            appeaseTypes: appeaseTypes,
            stopped: stopped
        )
    }
    
    let language: Language
    
    let executionEventProcessor: any ExecutionEventProcessor
    
    /// This closes all logging.
    public func closeEventProcessing() throws {
        try executionEventProcessor.closeEventProcessing()
    }
    
    public var metadataInfo: String { executionEventProcessor.metadataInfo }
    public var metadataInfoForUserInteraction: String { executionEventProcessor.metadataInfoForUserInteraction }
    
    public let stopAtFatalError: Bool
    
    let dispenseWith: Set<String>?
    let activatedOptions: Set<String>?
    
    var executedSteps = Set<StepID>()
    
    var _effectuationStack: [Effectuation]
    
    public var effectuationStack: [Effectuation] {
        _effectuationStack
    }
    
    public var waitNotPausedFunction: (@Sendable () -> ())?
    
    public func setting(
        waitNotPausedFunction: (@Sendable () -> ())? = nil
    ) -> Self {
        if let waitNotPausedFunction {
            self.waitNotPausedFunction = waitNotPausedFunction
        }
        return self
    }
    
    public var parallel: Execution {
        let execution = Execution(
            language: language,
            executionEventProcessor: executionEventProcessor,
            stopAtFatalError: stopAtFatalError,
            effectuationStack: effectuationStack,
            withOptions: activatedOptions,
            dispensingWith: dispenseWith,
            waitNotPausedFunction: waitNotPausedFunction,
        )
        execution.executedSteps = executedSteps
        execution._stopped = _stopped
        return execution
    }
    
    public init(
        language: Language = .en,
        executionEventProcessor: any ExecutionEventProcessor,
        stopAtFatalError: Bool = true,
        effectuationStack: [Effectuation] = [Effectuation](),
        withOptions activatedOptions: Set<String>? = nil,
        dispensingWith dispensedWith: Set<String>? = nil,
        waitNotPausedFunction: (@Sendable () -> ())? = nil,
    ) {
        self.language = language
        self.executionEventProcessor = executionEventProcessor
        self.stopAtFatalError = stopAtFatalError
        self._effectuationStack = effectuationStack
        self.activatedOptions = activatedOptions
        self.dispenseWith = dispensedWith
        self.waitNotPausedFunction = waitNotPausedFunction
    }
    
    public init(withExecutionState executionState: ExecutionState) {
        self.language = executionState.language
        self.executionEventProcessor = executionState.executionEventProcessor
        self.stopAtFatalError = executionState.stopAtFatalError
        self.activatedOptions = executionState.activatedOptions
        self.dispenseWith = executionState.dispenseWith
        self._effectuationStack = executionState.effectuationStack
        self.waitNotPausedFunction = executionState.waitNotPausedFunction
        self.forceValues = executionState.forceValues
        self.appeaseTypes = executionState.appeaseTypes
        self._stopped = executionState.stopped
    }
    
    public var level: Int { _effectuationStack.count }
    
    public var executionPath: String { _effectuationStack.executionPath }
    
    var _stopped = false
    
    public var stopped: Bool { _stopped }
    
    public func stop(reason: String) {
        executionEventProcessor.process(
            ExecutionEvent(
                type: .progress,
                level: level,
                structuralID: nil, // is a leave, no structural ID necessary
                coreEvent: .stoppingExecution(
                    reason: reason
                ),
                effectuationStack: effectuationStack
            )
        )
        _stopped = true
    }
    
    var forceValues = [Bool]()
    var appeaseTypes = [InfoType]()
    
    func waitNotPaused() {
        waitNotPausedFunction?() // wait if the execution is paused
    }
    
    /// Force all contained work to be executed, even if already executed before.
    fileprivate func execute<T>(
        step: StepID?,
        description: String?,
        force: Bool,
        appeaseTo appeaseType: InfoType? = nil,
        work: () throws -> T
    ) rethrows -> T {
        waitNotPaused() // wait if the execution is paused
        forceValues.append(force)
        if let appeaseType {
            appeaseTypes.append(appeaseType)
        }
        if let step {
            _effectuationStack.append(.step(step: step, description: description))
        }
        
        defer {
            if step != nil {
                _effectuationStack.removeLast()
            }
            forceValues.removeLast()
            if appeaseType != nil {
                appeaseTypes.removeLast()
            }
        }
        
        return try work()
    }
    
    /// Executes always.
    public func force<T>(work: () throws -> T) rethrows -> T? {
        let structuralID = UUID()
        executionEventProcessor.process(
            ExecutionEvent(
                type: .progress,
                level: level,
                structuralID: structuralID,
                coreEvent: .beginningForcingSteps,
                effectuationStack: effectuationStack
            )
        )
        _effectuationStack.append(.forcing)
        
        defer {
            _effectuationStack.removeLast()
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: structuralID,
                    coreEvent: .endingForcingSteps,
                    effectuationStack: effectuationStack
                )
            )
        }
        
        return try execute(step: nil, description: nil, force: true, work: work)
    }
    
    /// After execution, disremember what has been executed.
    public func disremember<T>(work: () throws -> T) rethrows -> T? {
        let oldExecutedSteps = executedSteps
        let result = try execute(step: nil, description: nil, force: false, work: work)
        executedSteps = oldExecutedSteps
        return result
    }
    
    /// Executes always if in a forced context.
    public func inheritForced<T>(work: () throws -> T) rethrows -> T? {
        try execute(step: nil, description: nil, force: forceValues.last == true, work: work)
    }
    
    /// Something that does not run in the normal case but ca be activated. Should use module name as prefix.
    public func optional<T>(named partName: String, description: String? = nil, work: () throws -> T) rethrows -> T? {
        if activatedOptions?.contains(partName) != true || dispenseWith?.contains(partName) == true {
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: nil, // is a leave, no structural ID necessary
                    coreEvent: .skippingOptionalPart(
                        name: partName,
                        description: description
                    ),
                    effectuationStack: effectuationStack
                )
            )
            return nil
        } else {
            let structuralID = UUID()
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: structuralID,
                    coreEvent: .beginningOptionalPart(
                        name: partName,
                        description: description
                    ),
                    effectuationStack: effectuationStack
                )
            )
            _effectuationStack.append(.optionalPart(name: partName, description: description))
            
            defer {
                _effectuationStack.removeLast()
                executionEventProcessor.process(
                    ExecutionEvent(
                        type: .progress,
                        level: level,
                        structuralID: structuralID,
                        coreEvent: .endingOptionalPart(
                            name: partName,
                            description: description
                        ),
                        effectuationStack: effectuationStack
                    )
                )
            }
    
            return try execute(step: nil, description: nil, force: false, work: work)
        }
    }
    
    /// Something that runs in the normal case but ca be dispensed with. Should use module name as prefix.
    public func dispensable<T>(named partName: String, description: String? = nil, work: () throws -> T) rethrows -> T? {
        if dispenseWith?.contains(partName) == true {
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: nil, // is a leave, no structural ID necessary
                    coreEvent: .skippingDispensablePart(
                        name: partName,
                        description: description
                    ),
                    effectuationStack: effectuationStack
                )
            )
            return nil
        } else {
            let structuralID = UUID()
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: structuralID,
                    coreEvent: .beginningDispensablePart(
                        name: partName,
                        description: description
                    ),
                    effectuationStack: effectuationStack
                )
            )
            _effectuationStack.append(.dispensablePart(name: partName, description: description))
            
            defer {
                _effectuationStack.removeLast()
                executionEventProcessor.process(
                    ExecutionEvent(
                        type: .progress,
                        level: level,
                        structuralID: structuralID,
                        coreEvent: .endingDispensablePart(
                            name: partName,
                            description: description
                        ),
                        effectuationStack: effectuationStack
                    )
                )
            }
            
            return try execute(step: nil, description: description, force: false, work: work)
        }
    }
    
    /// Make worse message type than `Error` to type `Error` in contained calls.
    public func appease<T>(to appeaseType: InfoType? = .error, work: () throws -> T) rethrows -> T? {
        try execute(step: nil, description: nil, force: false, appeaseTo: appeaseType, work: work)
    }
    
    private func effectuateTest(forStep step: StepID, withDescription description: String?) -> (execute: Bool, forced: Bool, structuralID: UUID?) {
        if _stopped {
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: nil, // is a leave, no structural ID necessary
                    coreEvent: .skippingStepInStoppedExecution(
                        id: step,
                        description: description
                    ),
                    effectuationStack: effectuationStack
                )
            )
            return (execute: false, forced: false, structuralID: nil)
        } else if !executedSteps.contains(step) {
            let structuralID = UUID()
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: structuralID,
                        coreEvent: .beginningStep(
                        id: step,
                        description: description,
                        forced: false
                    ),
                    effectuationStack: effectuationStack
                )
            )
            executedSteps.insert(step)
            return (execute: true, forced: false, structuralID: structuralID)
        } else if forceValues.last == true {
            let structuralID = UUID()
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: structuralID,
                    coreEvent: .beginningStep(
                        id: step,
                        description: description,
                        forced: true
                    ),
                    effectuationStack: effectuationStack
                )
            )
            executedSteps.insert(step)
            return (execute: true, forced: true, structuralID: structuralID)
        } else {
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: nil, // is a leave, no structural ID necessary
                    coreEvent: .skippingPreviouslyExecutedStep(
                        id: step,
                        description: description
                    ),
                    effectuationStack: effectuationStack
                )
            )
            return (execute: false, forced: false, structuralID: nil)
        }
    }
    
    /// Logging some work (that is not a step) as progress.
    public func doing<T>(withID id: String? = nil, _ description: String, work: () throws -> T) rethrows -> T? {
        let structuralID = UUID()
        executionEventProcessor.process(
            ExecutionEvent(
                type: .progress,
                level: level,
                structuralID: structuralID,
                coreEvent: .beginningDescribedPart(
                    description: description
                ),
                effectuationStack: effectuationStack
            )
        )
        _effectuationStack.append(.describedPart(description: description))
        
        defer {
            _effectuationStack.removeLast()
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: structuralID,
                    coreEvent: .endingDescribedPart(
                        description: description
                    ),
                    effectuationStack: effectuationStack
                )
            )
        }
        
        return try work()
    }
    
    private func after(step: StepID, structuralID: UUID?, description: String?, forced: Bool, secondsElapsed: Double) {
        if _stopped {
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: structuralID,
                    coreEvent: .stoppedStep(
                        id: step,
                        description: description
                    ),
                    effectuationStack: effectuationStack
                )
            )
        } else {
            executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: level,
                    structuralID: structuralID,
                    coreEvent: .endingStep(
                        id: step,
                        description: description,
                        forced: forced
                    ),
                    effectuationStack: effectuationStack
                )
            )
        }
    }
    
    /// Executes only if the step did not execute before.
    public func effectuate<T>(_ description: String? = nil, checking step: StepID, work: () throws -> T) rethrows -> T? {
        let (execute: toBeExecuted, forced: forced, structuralID: structuralID) = effectuateTest(forStep: step, withDescription: description)
        if toBeExecuted {
            let start = ContinuousClock.now
            let result = try execute(step: step, description: description, force: false, work: work)
            after(step: step, structuralID: structuralID, description: description, forced: forced, secondsElapsed: elapsedSeconds(start: start))
            return result
        } else {
            return nil
        }
    }
    
}
