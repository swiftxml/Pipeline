import Testing
import PipelineCore
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite(.serialized) struct ParallelTests {
    
    let metadata = MyMetaData(
        applicationName: "myapp",
        processID: "precess123",
        workItemInfo: "item123"
    )
    
    @Test func SynchronousParallelTest() async throws {
        
        @Sendable func step1(during execution: Execution, number: Int) {
            execution.effectuate("#\(number): doing something in step1", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                let message = "#\(String(format: "%02d", number)): in step1"; print(message); execution.log(.info, message)
                step2(during: execution, number: number)
            }
        }
        
        @Sendable func step2(during execution: Execution, number: Int) {
            execution.effectuate("#\(number): doing something in step1", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                let message = "#\(String(format: "%02d", number)): in step2"; print(message); execution.log(.info, message)
                step3(during: execution, number: number)
            }
        }
        
        @Sendable func step3(during execution: Execution, number: Int) {
            execution.effectuate("#doing something in step2", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                let message = "#\(String(format: "%02d", number)): in step3"; print(message); execution.log(.info, message)
            }
        }
        
        let logger = CollectingLogger()
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(withMetaDataInfo: metadata.description, logger: logger, withMinimalInfoType: .info, excutionInfoFormat: ExecutionInfoFormat(addIndentation: true))
        let execution = Execution(executionEventProcessor: myExecutionEventProcessor)
        
        let numbers = Array(1...20)
        let threads = 5
        
        let executionState = execution.state
        executeInParallel(batch: numbers, threads: threads) { number in
            
            let parallelExecution = Execution(withExecutionState: executionState)
            step1(during: parallelExecution, number: number)
            
        }
        
        logger.wait() // because this is a concurrent logger, wait until all logging is done!
        
        let expectedSorted = """
            #01: in step1
            #01: in step2
            #01: in step3
            #02: in step1
            #02: in step2
            #02: in step3
            #03: in step1
            #03: in step2
            #03: in step3
            #04: in step1
            #04: in step2
            #04: in step3
            #05: in step1
            #05: in step2
            #05: in step3
            #06: in step1
            #06: in step2
            #06: in step3
            #07: in step1
            #07: in step2
            #07: in step3
            #08: in step1
            #08: in step2
            #08: in step3
            #09: in step1
            #09: in step2
            #09: in step3
            #10: in step1
            #10: in step2
            #10: in step3
            #11: in step1
            #11: in step2
            #11: in step3
            #12: in step1
            #12: in step2
            #12: in step3
            #13: in step1
            #13: in step2
            #13: in step3
            #14: in step1
            #14: in step2
            #14: in step3
            #15: in step1
            #15: in step2
            #15: in step3
            #16: in step1
            #16: in step2
            #16: in step3
            #17: in step1
            #17: in step2
            #17: in step3
            #18: in step1
            #18: in step2
            #18: in step3
            #19: in step1
            #19: in step2
            #19: in step3
            #20: in step1
            #20: in step2
            #20: in step3
            """
        
        let actualResult = logger.messages.map{ $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
        print(actualResult)
        let actualResultSorted = logger.messages.map{ $0.trimmingCharacters(in: .whitespacesAndNewlines) }.sorted().joined(separator: "\n")
        
        // we can only compare the sorted messages:
        #expect(actualResultSorted == expectedSorted)
        
        // it is highly improbable that this is the actual order:
        #expect(actualResult != expectedSorted)
    }
    
    @Test func AsynchronousParallelTest() async throws {
        
        @Sendable func step1(during execution: AsyncExecution, number: Int) async {
            await execution.effectuate("#\(number): doing something in step1", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                let message = "#\(String(format: "%02d", number)): in step1"; print(message); await execution.log(.info, message)
                let synchronousExecution = Execution(withExecutionState: await execution.state)
                step2(during: synchronousExecution, number: number)
            }
        }
        
        @Sendable func step2(during execution: Execution, number: Int) {
            execution.effectuate("#\(number): doing something in step1", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                let message = "#\(String(format: "%02d", number)): in step2"; print(message); execution.log(.info, message)
                step3(during: execution, number: number)
            }
        }
        
        @Sendable func step3(during execution: Execution, number: Int) {
            execution.effectuate("#doing something in step2", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                let message = "#\(String(format: "%02d", number)): in step3"; print(message); execution.log(.info, message)
            }
        }
        
        let logger = CollectingLogger()
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(withMetaDataInfo: metadata.description, logger: logger, withMinimalInfoType: .info, excutionInfoFormat: ExecutionInfoFormat(addIndentation: true))
        let execution = AsyncExecution(executionEventProcessor: myExecutionEventProcessor)
        
        let numbers = Array(1...20)
        let threads = 5
        
        let executionState = await execution.state
        executeInParallel(batch: numbers, threads: threads) { number in
            
            let parallelExecution = AsyncExecution(withExecutionState: executionState)
            await step1(during: parallelExecution, number: number)
            
        }
        
        logger.wait() // because this is a concurrent logger, wait until all logging is done!
        
        let expectedSorted = """
            #01: in step1
            #01: in step2
            #01: in step3
            #02: in step1
            #02: in step2
            #02: in step3
            #03: in step1
            #03: in step2
            #03: in step3
            #04: in step1
            #04: in step2
            #04: in step3
            #05: in step1
            #05: in step2
            #05: in step3
            #06: in step1
            #06: in step2
            #06: in step3
            #07: in step1
            #07: in step2
            #07: in step3
            #08: in step1
            #08: in step2
            #08: in step3
            #09: in step1
            #09: in step2
            #09: in step3
            #10: in step1
            #10: in step2
            #10: in step3
            #11: in step1
            #11: in step2
            #11: in step3
            #12: in step1
            #12: in step2
            #12: in step3
            #13: in step1
            #13: in step2
            #13: in step3
            #14: in step1
            #14: in step2
            #14: in step3
            #15: in step1
            #15: in step2
            #15: in step3
            #16: in step1
            #16: in step2
            #16: in step3
            #17: in step1
            #17: in step2
            #17: in step3
            #18: in step1
            #18: in step2
            #18: in step3
            #19: in step1
            #19: in step2
            #19: in step3
            #20: in step1
            #20: in step2
            #20: in step3
            """
        
        let actualResult = logger.messages.map{ $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
        print(actualResult)
        let actualResultSorted = logger.messages.map{ $0.trimmingCharacters(in: .whitespacesAndNewlines) }.sorted().joined(separator: "\n")
        
        // we can only compare the sorted messages:
        #expect(actualResultSorted == expectedSorted)
        
        // it is highly improbable that this is the actual order:
        #expect(actualResult != expectedSorted)
    }
    
}
