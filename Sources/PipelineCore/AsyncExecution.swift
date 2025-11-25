#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import Localization

/// Manages the execution of steps. In particular
/// - prevents double execution of steps
/// - keeps global information for logging
public final actor AsyncExecution {
    
    let synchronousExecution: Execution
    
    public var state: ExecutionState { get async { synchronousExecution.state } }
    
    /// This closes all logging.
    public func closeEventProcessing() throws {
        try synchronousExecution.executionEventProcessor.closeEventProcessing()
    }
    
    public var metadataInfo: String { synchronousExecution.metadataInfo }
    public var metadataInfoForUserInteraction: String { synchronousExecution.metadataInfoForUserInteraction }
    
    public func synchronous(work: (Execution) -> ()) async {
        let execution = Execution(
            language: synchronousExecution.language,
            executionEventProcessor: synchronousExecution.executionEventProcessor,
            stopAtFatalError: synchronousExecution.stopAtFatalError,
            effectuationStack: synchronousExecution.effectuationStack,
            withOptions: synchronousExecution.activatedOptions,
            dispensingWith: synchronousExecution.dispenseWith,
            waitNotPausedFunction: synchronousExecution.waitNotPausedFunction,
        )
        execution.executedSteps = synchronousExecution.executedSteps
        execution._stopped = synchronousExecution._stopped
        work(execution)
        synchronousExecution.executedSteps = execution.executedSteps
        synchronousExecution._stopped = execution._stopped
    }
    
    public func setting(
        waitNotPausedFunction: (@Sendable () -> ())? = nil
    ) -> Self {
        if let waitNotPausedFunction {
            synchronousExecution.waitNotPausedFunction = waitNotPausedFunction
        }
        return self
    }
    
    public init(
        language: Language = .en,
        processID: String? = nil,
        executionEventProcessor: any ExecutionEventProcessor,
        stopAtFatalError: Bool = true,
        withOptions activatedOptions: Set<String>? = nil,
        dispensingWith dispensedWith: Set<String>? = nil,
        waitNotPausedFunction: (@Sendable () -> ())? = nil,
    ) {
        self.synchronousExecution = Execution(
            language: language,
            executionEventProcessor: executionEventProcessor,
            stopAtFatalError: stopAtFatalError,
            withOptions: activatedOptions,
            dispensingWith: dispensedWith,
            waitNotPausedFunction: waitNotPausedFunction,
        )
    }
    
    public init(withExecutionState executionState: ExecutionState) {
        self.synchronousExecution = Execution(
            language: executionState.language,
            executionEventProcessor: executionState.executionEventProcessor,
            stopAtFatalError: executionState.stopAtFatalError,
            withOptions: executionState.activatedOptions,
            dispensingWith: executionState.dispenseWith,
            waitNotPausedFunction: executionState.waitNotPausedFunction,
        )
        self.synchronousExecution._effectuationStack = executionState.effectuationStack
        self.synchronousExecution.forceValues = executionState.forceValues
        self.synchronousExecution.appeaseTypes = executionState.appeaseTypes
        self.synchronousExecution._stopped = executionState.stopped
    }
    
    public var level: Int {
        get async { synchronousExecution.level }
    }
    
    public var executionPath: String {
        get async { synchronousExecution.executionPath }
    }
    
    public func stop(reason: String) async {
        synchronousExecution.stop(reason: reason)
    }
    
    public var stopped: Bool { synchronousExecution._stopped }
    
    func waitNotPaused() {
        synchronousExecution.waitNotPausedFunction?() // wait if the execution is paused
    }
    
    /// Force all contained work to be executed, even if already executed before.
    fileprivate func execute<T>(
        step: StepID?,
        description: String?,
        force: Bool,
        appeaseTo appeaseType: InfoType? = nil,
        work: () async throws -> T
    ) async rethrows -> T {
        waitNotPaused() // wait if the execution is paused
        synchronousExecution.forceValues.append(force)
        if let appeaseType {
            synchronousExecution.appeaseTypes.append(appeaseType)
        }
        if let step {
            synchronousExecution._effectuationStack.append(.step(step: step, description: description))
        }
        
        defer {
            if step != nil {
                synchronousExecution._effectuationStack.removeLast()
            }
            synchronousExecution.forceValues.removeLast()
            if appeaseType != nil {
                synchronousExecution.appeaseTypes.removeLast()
            }
        }
        
        return try await work()
    }
    
    /// Executes always.
    public func force<T>(work: () async throws -> T) async rethrows -> T? {
        
        let structuralID = UUID()
        synchronousExecution.executionEventProcessor.process(
            ExecutionEvent(
                type: .progress,
                level: synchronousExecution.level,
                structuralID: structuralID,
                coreEvent: .beginningForcingSteps,
                effectuationStack: synchronousExecution.effectuationStack
            )
        )
        synchronousExecution._effectuationStack.append(.forcing)
        
        defer {
            synchronousExecution._effectuationStack.removeLast()
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: structuralID,
                    coreEvent: .endingForcingSteps,
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
        }
        
        return try await execute(step: nil, description: nil, force: true, work: work)
    }
    
    /// After execution, disremember what has been executed.
    public func disremember<T>(work: () async throws -> T) async rethrows -> T? {
        let oldExecutedSteps = synchronousExecution.executedSteps
        let result = try await execute(step: nil, description: nil, force: false, work: work)
        synchronousExecution.executedSteps = oldExecutedSteps
        return result
    }
    
    /// Executes always if in a forced context.
    public func inheritForced<T>(work: () async throws -> T) async rethrows -> T? {
        try await execute(step: nil, description: nil, force: synchronousExecution.forceValues.last == true, work: work)
    }
    
    /// Something that does not run in the normal case but ca be activated. Should use module name as prefix.
    public func optional<T>(named partName: String, description: String? = nil, work: () async throws -> T) async rethrows -> T? {
        if synchronousExecution.activatedOptions?.contains(partName) != true || synchronousExecution.dispenseWith?.contains(partName) == true {
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: nil, // is a leave, no structural ID necessary
                    coreEvent: .skippingOptionalPart(
                        name: partName,
                        description: description
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
            return nil
        } else {
            let structuralID = UUID()
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: structuralID,
                    coreEvent: .beginningOptionalPart(
                        name: partName,
                        description: description
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
            synchronousExecution._effectuationStack.append(.optionalPart(name: partName, description: description))
            
            defer {
                synchronousExecution._effectuationStack.removeLast()
                synchronousExecution.executionEventProcessor.process(
                    ExecutionEvent(
                        type: .progress,
                        level: synchronousExecution.level,
                        structuralID: structuralID,
                        coreEvent: .endingOptionalPart(
                            name: partName,
                            description: description
                        ),
                        effectuationStack: synchronousExecution.effectuationStack
                    )
                )
            }
            
            return  try await execute(step: nil, description: nil, force: false, work: work)
        }
    }
    
    /// Something that runs in the normal case but ca be dispensed with. Should use module name as prefix.
    public func dispensable<T>(named partName: String, description: String? = nil, work: () async throws -> T) async rethrows -> T? {
        if synchronousExecution.dispenseWith?.contains(partName) == true {
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: nil, // is a leave, no structural ID necessary
                    coreEvent: .skippingDispensablePart(
                        name: partName,
                        description: description
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
            return nil
        } else {
            let structuralID = UUID()
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: structuralID,
                    coreEvent: .beginningDispensablePart(
                        name: partName,
                        description: description
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
            synchronousExecution._effectuationStack.append(.dispensablePart(name: partName, description: description))
            
            defer {
                synchronousExecution._effectuationStack.removeLast()
                synchronousExecution.executionEventProcessor.process(
                    ExecutionEvent(
                        type: .progress,
                        level: synchronousExecution.level,
                        structuralID: structuralID,
                        coreEvent: .endingDispensablePart(
                            name: partName,
                            description: description
                        ),
                        effectuationStack: synchronousExecution.effectuationStack
                    )
                )
            }
            
            return try await execute(step: nil, description: description, force: false, work: work)
        }
    }
    
    /// Make worse message type than `Error` to type `Error` in contained calls.
    public func appease<T>(to appeaseType: InfoType? = .error, work: () async throws -> T) async rethrows -> T? {
        try await execute(step: nil, description: nil, force: false, appeaseTo: appeaseType, work: work)
    }
    
    private func effectuateTest(forStep step: StepID, withDescription description: String?) async -> (execute: Bool, forced: Bool, structuralID: UUID?) {
        if synchronousExecution._stopped {
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: nil, // is a leave, no structural ID necessary
                    coreEvent: .skippingStepInStoppedExecution(
                        id: step,
                        description: description
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
            return (execute: false, forced: false, structuralID: nil)
        } else if !synchronousExecution.executedSteps.contains(step) {
            let structuralID = UUID()
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: structuralID,
                        coreEvent: .beginningStep(
                        id: step,
                        description: description,
                        forced: false
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
            synchronousExecution.executedSteps.insert(step)
            return (execute: true, forced: false, structuralID: structuralID)
        } else if synchronousExecution.forceValues.last == true {
            let structuralID = UUID()
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: structuralID,
                    coreEvent: .beginningStep(
                        id: step,
                        description: description,
                        forced: true
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
            synchronousExecution.executedSteps.insert(step)
            return (execute: true, forced: true, structuralID: structuralID)
        } else {
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: nil, // is a leave, no structural ID necessary
                    coreEvent: .skippingPreviouslyExecutedStep(
                        id: step,
                        description: description
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
            return (execute: false, forced: false, structuralID: nil)
        }
    }
    
    /// Logging some work (that is not a step) as progress.
    public func doing<T>(withID id: String? = nil, _ description: String, work: () async throws -> T) async rethrows -> T? {
        let structuralID = UUID()
        synchronousExecution.executionEventProcessor.process(
            ExecutionEvent(
                type: .progress,
                level: synchronousExecution.level,
                structuralID: structuralID,
                coreEvent: .beginningDescribedPart(
                    description: description
                ),
                effectuationStack: synchronousExecution.effectuationStack
            )
        )
        synchronousExecution._effectuationStack.append(.describedPart(description: description))
        
        defer {
            synchronousExecution._effectuationStack.removeLast()
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: structuralID,
                    coreEvent: .endingDescribedPart(
                        description: description
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
        }
        
        return try await work()
    }
    
    private func after(step: StepID, structuralID: UUID?, description: String?, forced: Bool, secondsElapsed: Double) async {
        if synchronousExecution._stopped {
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: structuralID,
                    coreEvent: .stoppedStep(
                        id: step,
                        description: description
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
        } else {
            synchronousExecution.executionEventProcessor.process(
                ExecutionEvent(
                    type: .progress,
                    level: synchronousExecution.level,
                    structuralID: structuralID,
                    coreEvent: .endingStep(
                        id: step,
                        description: description,
                        forced: forced
                    ),
                    effectuationStack: synchronousExecution.effectuationStack
                )
            )
        }
    }
    
    /// Executes only if the step did not execute before.
    public func effectuate<T>(_ description: String? = nil, checking step: StepID, work: () async throws -> T) async rethrows -> T? {
        let (execute: toBeExecuted, forced: forced, structuralID: structuralID) = await effectuateTest(forStep: step, withDescription: description)
        if toBeExecuted {
            let start = ContinuousClock.now
            let result = try await execute(step: step, description: description, force: false, work: work)
            await after(step: step, structuralID: structuralID, description: description, forced: forced, secondsElapsed: elapsedSeconds(start: start))
            return result
        } else {
            return nil
        }
    }
    
}
