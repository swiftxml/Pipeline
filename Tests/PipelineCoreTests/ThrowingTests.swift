import Testing
import PipelineCore
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite(.serialized) struct ThrowingTests {
    
    let metadata = MyMetaData(
        applicationName: "myapp",
        processID: "precess123",
        workItemInfo: "item123"
    )
    
    @Test func throwing() throws {
        
        func step1(during execution: Execution) throws {
            try execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                try step2(during: execution)
            }
        }
        
        func step2(during execution: Execution) throws {
            try execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                throw TestError("error in step 2!")
            }
        }
        
        let logger = CollectingLogger()
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(
            withMetaDataInfo: metadata.description,
            logger: logger,
            excutionInfoFormat: ExecutionInfoFormat(
                addIndentation: true,
                addType: true,
                addExecutionPath: true,
                addStructuralID: true,
            )
        )
        
        var uuidReplacements = UUIDReplacements()
        
        do {
            try step1(during: Execution(executionEventProcessor: myExecutionEventProcessor))
        } catch {
            logger.log("THROWN ERROR: \(String(describing: error))")
        }
        
        #expect(uuidReplacements.doReplacements(in: logger.messages.joined(separator: "\n")) == """
            {progress} beginning step step1(during:)@PipelineCoreTests <#1>
                {progress} beginning step step2(during:)@PipelineCoreTests [@@ step step1(during:)@PipelineCoreTests -> ] <#2>
            THROWN ERROR: error in step 2!
            """)
        
    }
    
    @Test func throwingAndCatching() throws {
        
        func step1(during execution: Execution)  {
            execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                step2(during: execution)
            }
        }
        
        func step2(during execution: Execution)  {
            execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                do {
                    try step3(during: execution)
                } catch {
                    execution.log(.error, "catched the following error in in step 2: \(String(describing: error))")
                }
            }
        }
        
        func step3(during execution: Execution) throws {
            try execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                try step4(during: execution)
            }
        }
        
        func step4(during execution: Execution) throws {
            try execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
                throw TestError("error in step 4!")
            }
        }
        
        let logger = CollectingLogger()
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(
            withMetaDataInfo: metadata.description,
            logger: logger,
            excutionInfoFormat: ExecutionInfoFormat(
                addIndentation: true,
                addType: true,
                addExecutionPath: true,
                addStructuralID: true,
            )
        )
        
        var uuidReplacements = UUIDReplacements()
        
        step1(during: Execution(executionEventProcessor: myExecutionEventProcessor))
        
        #expect(uuidReplacements.doReplacements(in: logger.messages.joined(separator: "\n")) == """
            {progress} beginning step step1(during:)@PipelineCoreTests <#1>
                {progress} beginning step step2(during:)@PipelineCoreTests [@@ step step1(during:)@PipelineCoreTests -> ] <#2>
                    {progress} beginning step step3(during:)@PipelineCoreTests [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests -> ] <#3>
                        {progress} beginning step step4(during:)@PipelineCoreTests [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests -> step step3(during:)@PipelineCoreTests -> ] <#4>
                    {error} catched the following error in in step 2: error in step 4! [@@ step step1(during:)@PipelineCoreTests -> step step2(during:)@PipelineCoreTests] <>
                {progress} ending step step2(during:)@PipelineCoreTests [@@ step step1(during:)@PipelineCoreTests -> ] <#2>
            {progress} ending step step1(during:)@PipelineCoreTests <#1>
            """)
        
    }
    
}
