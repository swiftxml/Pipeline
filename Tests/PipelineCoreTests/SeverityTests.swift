import Testing
import PipelineCore
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite(.serialized) struct SeverityTests {
    
    let metadata = MyMetaData(
        applicationName: "myapp",
        processID: "precess123",
        workItemInfo: "item123"
    )
    
    @Test func test1() async throws {
        
        @Sendable func step1(during execution: Execution, number: Int, infoTypeForSeven: InfoType) {
            execution.effectuate("#\(number): doing something in step1", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                step2(during: execution, number: number, infoTypeForSeven: infoTypeForSeven)
            }
        }
        
        @Sendable func step2(during execution: Execution, number: Int, infoTypeForSeven: InfoType) {
            execution.effectuate("#\(number): doing something in step1", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                if number == 7 {
                    execution.log(infoTypeForSeven, "oh oh, number is 7!")
                }
            }
        }
        
        let logger = CollectingLogger()
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(withMetaDataInfo: metadata.description, logger: logger, withMinimalInfoType: .info, excutionInfoFormat: ExecutionInfoFormat(addIndentation: true))
        let execution = Execution(executionEventProcessor: myExecutionEventProcessor)
        
        let numbers = Array(1...20)
        let threads = 5
        
        let executionState = execution.state
        
        // ----- info type "error": -----
        
        do {
            let infoTypeForSeven = InfoType.error
            
            executeInParallel(batch: numbers, threads: threads) { number in
                
                let parallelExecution = Execution(withExecutionState: executionState)
                step1(during: parallelExecution, number: number, infoTypeForSeven: infoTypeForSeven)
                
            }
            
            #expect(myExecutionEventProcessor.severity == infoTypeForSeven)
        }
        
        // ----- info type "fatal": -----
        
        do {
            let infoTypeForSeven = InfoType.fatal
            
            executeInParallel(batch: numbers, threads: threads) { number in
                
                let parallelExecution = Execution(withExecutionState: executionState)
                step1(during: parallelExecution, number: number, infoTypeForSeven: infoTypeForSeven)
                
            }
            
            #expect(myExecutionEventProcessor.severity == infoTypeForSeven)
        }
    }
    
}
