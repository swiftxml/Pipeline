import Testing
import PipelineCore
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import Localization

@Suite(.serialized) struct LoggingTests {
    
    let metadata = MyMetaData(
        applicationName: "myapp",
        processID: "precess123",
        workItemInfo: "item123"
    )
    
    @Test func testExecutionPath() throws {
        
        func step1(during execution: Execution) {
            execution.effectuate("doing something in step1", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                step2(during: execution)
            }
        }
        
        func step2(during execution: Execution) {
            execution.effectuate("doing something in step2", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                execution.log(.info, "hello")
                #expect(execution.executionPath == "step step1(during:)@\(#file.firstPathPart) -> step step2(during:)@\(#file.firstPathPart)")
                execution.dispensable(named: "we might dispense with step 3") {
                    #expect(execution.executionPath == "step step1(during:)@\(#file.firstPathPart) -> step step2(during:)@\(#file.firstPathPart) -> dispensable part \"we might dispense with step 3\"")
                    step3(during: execution)
                }
            }
        }
        
        func step3(during execution: Execution) {
            execution.effectuate("doing something in step3", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                execution.force {
                    execution.log(.info, "hello again")
                }
            }
        }
        
        let logger = CollectingLogger()
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(withMetaDataInfo: metadata.description, logger: logger, excutionInfoFormat: ExecutionInfoFormat(addIndentation: true, addType: true, addExecutionPath: true))
        
        let execution = Execution(executionEventProcessor: myExecutionEventProcessor)
        
        step1(during: execution)
        
        #expect(logger.messages.joined(separator: "\n") == """
            {progress} beginning step step1(during:)@PipelineCoreTests (doing something in step1)
                {progress} beginning step step2(during:)@PipelineCoreTests (doing something in step2) [@@ step step1(during:)@PipelineCoreTests -> ]
                    {info} hello [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests]
                    {progress} beginning dispensible part "we might dispense with step 3" [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests -> ]
                        {progress} beginning step step3(during:)@PipelineCoreTests (doing something in step3) [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests -> dispensable part "we might dispense with step 3" -> ]
                            {progress} beginning forcing steps [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests -> dispensable part "we might dispense with step 3" -> step step3(during:)@PipelineCoreTests -> ]
                                {info} hello again [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests -> dispensable part "we might dispense with step 3" -> step step3(during:)@PipelineCoreTests -> forcing]
                            {progress} ending forcing steps [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests -> dispensable part "we might dispense with step 3" -> step step3(during:)@PipelineCoreTests -> ]
                        {progress} ending step step3(during:)@PipelineCoreTests (doing something in step3) [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests -> dispensable part "we might dispense with step 3" -> ]
                    {progress} ending dispensible part "we might dispense with step 3" [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests -> ]
                {progress} ending step step2(during:)@PipelineCoreTests (doing something in step2) [@@ step step1(during:)@PipelineCoreTests -> ]
            {progress} ending step step1(during:)@PipelineCoreTests (doing something in step1)
            """
        )
    }
    
    @Test func testMessage1() throws {
        
        let logger = CollectingLogger()
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(withMetaDataInfo: metadata.description, logger: logger)
        
        let execution = Execution(executionEventProcessor: myExecutionEventProcessor)
        
        let message = Message(
            id: "values not OK",
            type: .info,
            fact: [
                Language.en: #""$0" and "$1" are not OK"#,
                Language.de: #""$0" und "$1" sind nicht OK"#,
            ]
        )
        
        execution.log(message, "A", "B")
        
        // e.g. `2025-09-18 09:09:55 +0000: myapp: precess123/item123: {info} [values not OK]: "A" and "B" are not OK`:
        #expect(logger.messages.joined(separator: "\n").contains(#/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \+\d{4}: myapp: precess123\/item123: {info} \[values not OK\]: "A" and "B" are not OK$/#))
    }
    
    @Test func testMessage2() throws {
        
        let logger = CollectingLogger()
        
        // NOTE: `excutionInfoFormat: .bareIndented` added:
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(withMetaDataInfo: metadata.description, logger: logger, excutionInfoFormat: ExecutionInfoFormat(addIndentation: true))
        
        // NOTE: `language: .de` added:
        let execution = Execution(language: .de, executionEventProcessor: myExecutionEventProcessor)
        
        let message = Message(
            id: "values not OK",
            type: .info,
            fact: [
                Language.en: #""$0" and "$1" are not OK"#,
                Language.de: #""$0" und "$1" sind nicht OK"#,
            ],
            solution: [
                Language.en: #"change "$0" and "$1""#,
                Language.de: #"ändere "$0" und "$1""#,
            ]
        )
        
        execution.log(message, "A", "B")
        
        #expect(logger.messages.joined(separator: "\n") == #"[values not OK]: "A" und "B" sind nicht OK → ändere "A" und "B""#)
        
    }
    
    @Test func testAppeasement() throws {
        
        let logger = CollectingLogger()
        
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(
            withMetaDataInfo: metadata.description,
            logger: logger,
            withMinimalInfoType: .info,
            excutionInfoFormat: ExecutionInfoFormat(addType: true)
        )
        
        // NOTE: `language: .de` added:
        let execution = Execution(executionEventProcessor: myExecutionEventProcessor)
        
        execution.appease(to: .warning) {
            execution.log(.error, "this was an error")
            execution.appease(to: .info) {
                execution.log(.warning, "this was a warning")
            }
        }
        
        // default is the appeasement to `error`:
        execution.appease {
            execution.log(.fatal, "this was a fatal error")
        }
        
        execution.log(.fatal, "this is still a fatal error")
        
        #expect(logger.messages.joined(separator: "\n") == """
            {warning} this was an error
            {info} this was a warning
            {error} this was a fatal error
            {fatal} this is still a fatal error
            """)
    }
    
    @Test func testAppeasementAsync() async throws {
        
        let logger = CollectingLogger()
        
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(
            withMetaDataInfo: metadata.description,
            logger: logger,
            withMinimalInfoType: .info,
            excutionInfoFormat: ExecutionInfoFormat(addType: true)
        )
        
        // NOTE: `language: .de` added:
        let execution = AsyncExecution(executionEventProcessor: myExecutionEventProcessor)
        
        await execution.appease(to: .warning) {
            await execution.log(.error, "this was an error")
            await execution.appease(to: .info) {
                await execution.log(.warning, "this was a warning")
            }
        }
        
        // default is the appeasement to `error`:
        await execution.appease {
            await execution.log(.fatal, "this was a fatal error")
        }
        
        await execution.log(.fatal, "this is still a fatal error")
        
        #expect(logger.messages.joined(separator: "\n") == """
            {warning} this was an error
            {info} this was a warning
            {error} this was a fatal error
            {fatal} this is still a fatal error
            """)
    }
    
    @Test func testStructuralIDs() throws {
        
        func step1(during execution: Execution) {
            execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                step2(during: execution)
            }
        }
        
        func step2(during execution: Execution) {
            execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                execution.log(.info, "hello")
                execution.dispensable(named: "calling step 3") {
                    step3(during: execution)
                    step3(during: execution)
                    execution.force {
                        step3(during: execution)
                    }
                }
                execution.dispensable(named: "dispensable message") {
                    execution.log(.info, "dispensed?")
                }
                execution.optional(named: "option 1") {
                    execution.log(.info, "option 1?")
                }
                execution.optional(named: "option 2") {
                    execution.log(.info, "option 2?")
                }
            }
        }
        
        func step3(during execution: Execution) {
            execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                execution.force {
                    execution.log(.info, "hello again")
                }
            }
        }
        
        let logger = CollectingLogger()
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(
            withMetaDataInfo: metadata.description,
            logger: logger,
            excutionInfoFormat: ExecutionInfoFormat(
                addIndentation: true,
                addType: true,
                addStructuralID: true
            )
        )
        
        let execution = Execution(executionEventProcessor: myExecutionEventProcessor, withOptions: ["option 2"], dispensingWith: ["dispensable message"])
        
        step1(during: execution)
        
        var uuidReplacements = UUIDReplacements()
        
        #expect(uuidReplacements.doReplacements(in: logger.messages.joined(separator: "\n")) == """
            {progress} beginning step step1(during:)@PipelineCoreTests <#1>
                {progress} beginning step step2(during:)@PipelineCoreTests <#2>
                    {info} hello <>
                    {progress} beginning dispensible part "calling step 3" <#3>
                        {progress} beginning step step3(during:)@PipelineCoreTests <#4>
                            {progress} beginning forcing steps <#5>
                                {info} hello again <>
                            {progress} ending forcing steps <#5>
                        {progress} ending step step3(during:)@PipelineCoreTests <#4>
                        {progress} skipping previously executed step step3(during:)@PipelineCoreTests <>
                        {progress} beginning forcing steps <#6>
                            {progress} beginning forced step step3(during:)@PipelineCoreTests <#7>
                                {progress} beginning forcing steps <#8>
                                    {info} hello again <>
                                {progress} ending forcing steps <#8>
                            {progress} ending forced step step3(during:)@PipelineCoreTests <#7>
                        {progress} ending forcing steps <#6>
                    {progress} ending dispensible part "calling step 3" <#3>
                    {progress} skipping dispensible part "dispensable message" <>
                    {progress} skipping optional part "option 1" <>
                    {progress} beginning optional part "option 2" <#9>
                        {info} option 2? <>
                    {progress} ending optional part "option 2" <#9>
                {progress} ending step step2(during:)@PipelineCoreTests <#2>
            {progress} ending step step1(during:)@PipelineCoreTests <#1>
            """
        )
    }
    
    @Test func testStructuralIDsWithStop() throws {
        
        func step1(during execution: Execution) {
            execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                step2(during: execution)
            }
        }
        
        func step2(during execution: Execution) {
            execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                execution.dispensable(named: "calling step 3") {
                    execution.stop(reason: "not calling step 3")
                    step3(during: execution)
                }
                execution.log(.info, "hello again")
            }
        }
        
        func step3(during execution: Execution) {
            execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                execution.force {
                    execution.log(.info, "hello")
                }
            }
        }
        
        let logger = CollectingLogger()
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(
            withMetaDataInfo: metadata.description,
            logger: logger,
            excutionInfoFormat: ExecutionInfoFormat(
                addIndentation: true,
                addType: true,
                addStructuralID: true
            )
        )
        
        let execution = Execution(executionEventProcessor: myExecutionEventProcessor, withOptions: ["option 2"], dispensingWith: ["dispensable message"])
        
        step1(during: execution)
        
        struct UUIDReplacements {
            var count = 0
            var mapped = [String:String]()
            
            mutating func replacement(for token: String) -> String {
                if let existing = mapped[token] {
                    return existing
                } else {
                    count += 1
                    let replacement = "#\(count)"
                    mapped[token] = replacement
                    return replacement
                }
            }
            
            mutating func doReplacements(in text: String) -> String {
                var parts = [Substring]()
                var rest = Substring(text)
                while let match = rest.firstMatch(of: /[0-9A-Z]{8}-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{12}/) {
                    parts.append(rest[..<match.range.lowerBound])
                    parts.append(Substring(replacement(for: String(rest[match.range.lowerBound..<match.range.upperBound]))))
                    rest = rest[match.range.upperBound...]
                }
                parts.append(rest)
                return parts.joined()
            }
                    
        }
        
        var uuidReplacements = UUIDReplacements()
        
        #expect(uuidReplacements.doReplacements(in: logger.messages.joined(separator: "\n")) == """
            {progress} beginning step step1(during:)@PipelineCoreTests <#1>
                {progress} beginning step step2(during:)@PipelineCoreTests <#2>
                    {progress} beginning dispensible part "calling step 3" <#3>
                        {progress} stopping execution: not calling step 3 <>
                        {progress} skipping in an stopped environment step step3(during:)@PipelineCoreTests <>
                    {progress} ending dispensible part "calling step 3" <#3>
                    {info} hello again <>
                {progress} stopped step step2(during:)@PipelineCoreTests <#2>
            {progress} stopped step step1(during:)@PipelineCoreTests <#1>
            """
        )
    }
    
}
