import Testing
import PipelineCore
import Foundation

@Suite(.serialized) struct PauseTests {
    
    let metadata = MyMetaData(
        applicationName: "myapp",
        processID: "precess123",
        workItemInfo: "item123"
    )
    
    @Test func pauseTest() async throws {
        
        /// The semaphore for pausing the processing.
        let semaphoreForPause = DispatchSemaphore(value: 1)

        /// Pausing the processing.
        func pause() {
            semaphoreForPause.wait()
        }

        /// Proceeding a paused processing.
        func proceed() {
            semaphoreForPause.signal()
        }
        
        /// Wait until the processing is not paused.
        @Sendable func waitNotPaused() {
            semaphoreForPause.wait(); semaphoreForPause.signal()
        }
        
        let waitTimeStep1: Double = 1
        
        #expect(waitTimeStep1 > 0)
        let waitTimeBeforePausingProcessing = waitTimeStep1 / 2
        let waitTimeBeforeContinuingProcessing = waitTimeBeforePausingProcessing + waitTimeStep1
        
        @Sendable func step1(during execution: Execution) {
            execution.effectuate("doing something in step1", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                print("PROCESSING: starting step1")
                print("PROCESSING: waiting \(waitTimeStep1) seconds in step1...")
                Thread.sleep(forTimeInterval: waitTimeStep1)
                print("PROCESSING: continuing...")
                print("PROCESSING: calling step1")
                step2(during: execution)
                print("PROCESSING: step1 DONE.")
            }
        }
        
        @Sendable func step2(during execution: Execution) {
            execution.effectuate("doing something in step1", checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                print("PROCESSING: in step2")
            }
        }
        
        let expectedProcessing = """
                beginning step step1(during:)@PipelineCoreTests (doing something in step1)
                    beginning step step2(during:)@PipelineCoreTests (doing something in step1)
                    ending step step2(during:)@PipelineCoreTests (doing something in step1)
                ending step step1(during:)@PipelineCoreTests (doing something in step1)
                """
        
        print("------------------------------------")
        
        do {
            let logger = CollectingLogger()
            let myExecutionEventProcessor = ExecutionEventProcessorForLogger(withMetaDataInfo: metadata.description, logger: logger, excutionInfoFormat: ExecutionInfoFormat(addIndentation: true))
            
            let time = elapsedTime {
                step1(during: Execution(executionEventProcessor: myExecutionEventProcessor))
            }
            
            #expect(logger.messages.joined(separator: "\n") == expectedProcessing)
            
            print("time 1: \(time)")
        }
        
        print("------------------------------------")
        
        let task = Task {
            
            let logger = CollectingLogger()
            let myExecutionEventProcessor = ExecutionEventProcessorForLogger(withMetaDataInfo: metadata.description, logger: logger, excutionInfoFormat: ExecutionInfoFormat(addIndentation: true))
            
            let time = elapsedTime {
                // the `waitNotPausedFunction` is given to the excution:
                step1(during: Execution(executionEventProcessor: myExecutionEventProcessor, waitNotPausedFunction: waitNotPaused))
            }
            
            #expect(logger.messages.joined(separator: "\n") == expectedProcessing)
            
            print("time 2: \(time)")
            
            let expectedTime = waitTimeStep1 * 2
            print("expected time: \(expectedTime)")
            
            let deviationPercent = (time - expectedTime) * 100 / expectedTime
            print("deviation from expected time: \(String(format: "%.1f", deviationPercent)) %")
            
            #expect(deviationPercent < 20) // 10 % percent should suffice, but we do not want a test to fail for external reasons
        }
        
        print("CONTROLLER: waiting \(waitTimeBeforePausingProcessing) seconds...")
        try await Task.sleep(for: .seconds(waitTimeBeforePausingProcessing))
        print("CONTROLLER: pausing the processing...")
        pause()
        print("CONTROLLER: waiting \(waitTimeBeforeContinuingProcessing) seconds...")
        try await Task.sleep(for: .seconds(waitTimeBeforeContinuingProcessing))
        print("CONTROLLER: continuing...")
        proceed()
        print("CONTROLLER: waiting for the processing to finish...")
        _ = await task.result
        print("CONTROLLER: DONE.")
        
        print("------------------------------------")
        
    }
    
}
