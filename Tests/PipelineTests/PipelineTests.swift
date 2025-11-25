import Testing
import Pipeline

@Suite(.serialized) struct PipelineTests {
    
    @Test func pipelineTest1() throws {
        
        // The public parts of PipelineCore + StepMacro should
        // be reachable by the above Pipeline import alone.
        
        // The following sample is from teh README, describing
        // how to use optional return values of steps:
        
        @Step
        func optionalHello_step(during execution: Execution, condition: Bool) -> String?? {
            if condition {
                return "hello 1"
            } else {
                return nil
            }
        }
        
        @Step
        func hello_step(during execution: Execution, condition: Bool) -> String? {
            if let executionResult = optionalHello_step(during: execution, condition: condition),
               let value = executionResult {
                return value
            } else {
                return "hello 2"
            }
        }
        
    }
    
}
