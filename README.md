# Pipeline

This is a simple framework for constructing a pipeline to process a single work item.

```Swift
@Step("...here a description can be added...")
func myWork_step(during execution: Execution) {
    
    // ... some other code...
    
    myOther_step(during: execution)
    
    // ... some other code...
    
}
```

You could skip the following overview and go directly to the tutorial section to get a first impression.

## Logging in the tests

The logging implemented in the tests is not intended for use in production code (although it might work well). Use [PipelineBasicLogging](https://github.com/swiftxml/PipelineBasicLogging) instead, see the section below on logging.

## Overview

The idea behind this framework is that there should be no fixed declarative schema for composing the steps of a processing pipeline for a single work item, as any conceivable schema might not be flexible enough. Instead, the concept is simply “functions calling functions,” with specific functions acting as steps. This gives you everything you need to define, control, and log a processing pipeline with maximum flexibility and efficiency. This also applies to data, which is simple given as arguments to your steps which also can have return values.

The framework is designed to also handle steps defined in other packages. It can reduce errors that occur in called steps to a specific severity level, which is very useful e.g. if a fatal error in another package should be treated as just a normal error in your application.

The problem of prerequisites for a step (things that must be done beforehand) is solved in a simple way: A step can call other steps before completing its own work, but these steps (like all steps in general) will only be executed if they have not been executed previously. (You can change this behavior for a specific section of code by “forcing” execution.)

To facilitate further description, we will already introduce some of the types used. You define a complex processing of one “work item” that can be executed within an `Execution` environment. For each work item a separate `Execution` instance has to be created. So if more than one work item is to be processed, then more than one `Execution` instance has to be used.

This framework does not provide its own logging implementation. However, the logging used by packages should be able to be formulated independently of the actual logging implementation. Log messages can therefore be generated via methods of the `Execution` instance and then must be processed by an `ExecutionEventProcessor` provided by you. The `ExecutionEventProcessor` must also handle information about the execution of the steps. Either is realized as an `ExecutionEvent`, which the `ExecutionEventProcessor` must be able to process. This `ExecutionEvent` contains all parts of the information as separate entities, but a simple textual representation can be easily configured. More granular error types are available than in most actual logging implementations, which you can map to the message types of the logging implementation used by your application.

To easily enable parallel processing and switching from an asynchronous to a synchronous context, an `ExecutionEventProcessor` must be sendable without being an actor. To achieve this, encapsulate its mutatable state inside one or sevaral classes which use the `@unchecked Sendable` notation where concurrent access to that state is controlled without involving actors. Such an `@unchecked Sendable` class might be the `ExecutionEventProcessor` itself, a class directly referenced by it, or an a deeper level, e.g. a logger used by the `ExecutionEventProcessor` might itself encapsulate its mutable state by this method, so it can be a constant sendable value inside the `ExecutionEventProcessor`. For parallel processing, the state of one execution (including the sendable `ExecutionEventProcessor`) can be extracted and used to easily create subsequent executions that further process that state; this state is sendable, even though the execution itself is not.

Potentially concurrently executed steps must be sendable.

When only logging via the `Execution` instance, you can easily build a tree structure from the `ExecutionEvent` instances.

Concerning metadata such as a “process ID”, pipline steps in general and especially pipline steps from other packages should not need to know about it. The `ExecutionEventProcessor` should handle any metadata and add it to the actual log entries if required, the implementation of `ExecutionEvent` facilitates this. Any more precise data you need for your own steps should generally be covered in additional arguments for your steps. (If the metadata information is actually needed during processing in a general form, especially by an external package, it can be requested via the `metadataInfo` or `metadataInfoForUserInteraction` property of the `Execution` which in turn gets the information from the `ExecutionEventProcessor`.)

This documentation contains some motivation. For a quick start, there is a tutorial below. For more details, you might look at the conventions (between horizontal rules) given further below and look at some code samples from the contained tests.

The API documentation is to be created by using DocC, e.g. in Xcode via „Product“ / „Build Documentation“.

The `import PipelineCore` and other imports are being dropped in the code samples.

## How to add the package to your project

The package is to be inlcuded as follows in another package: in `Package.swift` add:

The top-level dependency:

```Swift
.package(url: "https://github.com/swiftxml/Pipeline", from: "...put the minimal version number here..."),
```

(You might reference an exact version by defining e.g. `.exact("1.0.1")` instead.)

As dependency of your product, you then just add `"Pipeline"`.

The Pipeline package will be then usable in a Swift file after adding the following import:

```Swift
import Pipeline
```

## Tutorial

The first thing you need it an instance to process messages from the execution, reporting if a step has beeen begun etc. The processing of these messages always has to be via a simple synchronous methods, no matter if the actual logging used behind the scenes is asynchronous or not. Most logging environment are working with such a synchronous method.

You need an instance conforming to `ExecutionEventProcessor`

```Swift
public protocol ExecutionEventProcessor {
    func process(_ executionEvent: ExecutionEvent)
    var metadataInfo: String { get }
    var metadataInfoForUserInteraction: String { get }
}
```

Note that in the general case the metadata should contain the information about the current work item, so not only a new `Execution` has to be created for each work item, but usually also a new `ExecutionEventProcessor` has to be created.

See the `ExecutionEventProcessorForLogger` example in the test cases.

Then, for each work item that you want to process (whatever your work items might be, maybe you have only one work item so you do not need a for loop), use a new `Execution` object:

```Swift
let logger = PrintingLogger()
let myExecutionEventProcessor = ExecutionEventProcessorForLogger(withMetaDataInfo: metadata.description, logger: logger)

let execution = Execution(executionEventProcessor: myExecutionEventProcessor)
```

The step you call (in the following example: `myWork_step`) might have any other arguments besides the `Execution`, and the postfix `_step` is only for convention. Your step might be implemented as follows:

```Swift
@Step("...here a description can be added...")
func myWork_step(during execution: Execution) {
    
    // ... some other code...
    
    myOther_step(during: execution)
    
    // ... some other code...
    
}
```

The call of this step is then as follows:

```Swift
myWork_step(during: execution)
```

Inside your step you might call other steps. In the example above, `myOther_step` has the same arguments as `myWork_step`, but in the general case, this does not have to be this way. On the contrary, our recommendation is to only give to each step the data that it really needs.

If you call `myOther_step` inside `myWork_step` as in the example above, `myOther_step` (or more precisely, the code inside it that is embraced in a `execution.effectuate` call) will not be executed if `myWork_step` has already been executed before during the same execution (of the work item). This way you can formulate prerequisites that should have been run before, but without getting the prerequisites executed multiple times. If you want to force the execution of `myOther_step` at this point, use the following code:

```Swift
execution.force {
    myOther_step<(during: execution)
}
```

You can also disremember what is executed with the following call:

```Swift
execution.disremember {
    myOther_step(during: execution)
}
```

There are also be named optional parts that can be activated by adding an according value to the `withOptions` value in the initializer of the `Execution` instance:

```Swift
execution.optional(named: "module1:myOther_step", description: "...here a description can be added...") {
        myOther_step(during: execution)
}
```

On the contrary, if you regard a step at a certain point or more generally a certain code block as something dispensable (i.e. the rest of the application does not suffer from inconsistencies if this part does not get executed), use the following code: 

```Swift
execution.dispensable(named: "module1:myOther_step", description: "...here a description can be added...")) {
        myOther_step(during: execution)
}
```

The part can then be deactivated by adding the according name to the `dispensingWith` value in the initializer of the `Execution` instance.

So with `execution.optional(named: ...) { ... }` you define a part that does not run in the normal case but can be activated, and with `execution.dispensable(named: ...) { ... }` you define a part that runs in the normal case but can be deactivated. It is recommended to add the module name to the part name as a prefix in both cases.

An activated option can also be dispensed with („dispensing wins“).

If your function contains `async` code (i.e. `await` is being used in the calls), use `AsyncExecution` instead of `Execution` or `execution.async.force`. Inside an `AsyncExecution`, you get the according `Execution` instance via `myAsyncExecution.synchronous`, so you can asynchronous steps at the outside that are calling  synchronous steps in the inside.

The texts `$0`, `$1`, ... are being replaced by arguments (of type `String`) in their order in the call to `execution.log(...)`.

## The size of step functions

The body of a step function is actually, by expansion of the `@Step` macro, encapsulated as a closure in order to be controlled by the pipeline framework. This means that the compiler may have difficulty applying type inference to complex but erroneous code within a step function, making it harder to generate a helpful error messages in such cases. Furthermore, with very large functions, the corresponding macro expansion could potentially slow down the editing process.

It is generally recommended to avoid very large step functions.

## Logging

When using the Pipeline library, logging in the application code can be formulated independently of the actual logging library. It requires a binding of the logging library to the Pipeline library. This allows the logging library to be switched later without having to replace the logging commands.

So in principle you can use a logging library of your choice. However, if no such logging library is specified or available, or if you simply want to try out the Pipeline library, you can use the [BasicLogging](https://github.com/swiftxml/BasicLogging) library. You then just add the dependency to the [PipelineBasicLogging](https://github.com/swiftxml/PipelineBasicLogging) library which implements the according binding to the Pipeline library and thus allows you to get started quickly.

For another logging, the package [PipelineLoggingBinding](https://github.com/swiftxml/PipelineLoggingBinding) might still be useful which offers a binding to logging according to the [LoggingInterfaces](https://github.com/swiftxml/LoggingInterfaces).

## Motivation

We think of a processing of a work item consisting of several steps, each step fullfilling a certain piece of work. We first see what basic requirements we would like to postulate for those steps, and then how we could realize that in practice.

### Requirements for the execution of steps

The steps comprising the processing might get processed in sequence, or one step contains other steps, so that step A might execute step B, C, and D.

We could make the following requirements for the organization of steps:

- A step might contain other steps, so we can organize the steps in a tree-like structure.
- Some steps might stem from other packages.
- A step might have as precondition that another step has already been executed before it can do some piece of work.
- There should be an environment accessible inside the steps which can be used for logging (or other communication).
- This environment should also have control over the execution of the steps, e.g. when there is a fatal error, no more steps should be executed.

But of course, we do not only have a tree-like structure of steps executing each-other, _somewhere_ real work has to be done. Doing real work should also be done inside a step, we do not want to invent another type of thing, so:

- In each step should be able to do real work besides calling other steps.

We would even go further:

- In each step, there should be no rules of how to mix “real work” and the calling of other steps. This should be completely flexible.

We should elaborate this last point. This mixture of the calling of steps and other code may seem suspicious to some. There are frameworks for organizing the processing which are quite strict in their structure and make a more or less strict separation between the definition of which steps are to be executed and when, and the actual code doing the real work. But seldom this matches reality (or what we want the reality to be). E.g. we might have to decide dynamically during execution which step to be processed at a certain point of the execution. This decision might be complex, so we would like to be able to use complex code to make the decision, and moreover, put the code exactly to where the call of the step is done (or not done).

We now have an idea of how we would like the steps to be organized.

In addition, the steps will operate on some data to be processed, might use some configuration data etc., so we need to be able to hand over some data to the steps, preferably in a strictly typed manner. A step might change this data or create new data and return the data as a result. And we do not want to presuppose what types the data has or how many arguments are used, a different step might have different arguments (or different types of return values).

Note that the described flexibility of the data used by each step is an important requirement for modularization. We do not want to pass around the same data types during our processing; if we did so, we could not extract a part of our processing as a separate, independant package, and we would not be very precise of what data is required for a certain step.

### Realization of steps

When programming, we have a very common concept that fullfills most of the requirements above: the concept of a _function._ But when we think of just using functions as steps, two questions immediately arise:

- How do we fullfill the missing requirements?
- How can we visually make clear in the code where a step gets executed?

So when we use functions as steps, the following requirements are missing:

- A step might have as precondition that another step has already been executed before it can do some piece of work.
- There should be an environment accessible inside the steps which can be used for logging (or other communication).
- This environment should also have control over the execution of the steps, e.g. when there is a fatal error, the execution of the steps should stop.

We will see in the next section how this is resolved. For the second question ("How can we visually make clear in the code where a step gets executed?"): We just use the convenstion that a step i.e. a function that realizes a step always has the postfix "\_step" in its name. Some people do not like relying on conventions, but in practice this convention works out pretty well.

---
**Convention**

In addition to the `@Step` annotation and the argument with the inner-fiunction name `execution`, a function representing a step has the postfix `_step` in its name.

---

## Concept

### An execution

An `Execution` has control over the steps, i.e. it can decide if a step actually executes, and it can inform about what if happening. 

### Formulation of a step

To give an `Execution` control over a function representing a step, its statements are to be wrapped inside a call to `Execution.effectuate`.

---
**Convention**

A function representing a step uses a call to `Execution.effectuate` to wrap all its other statements.

---

We say that a step “gets executed” when we actually mean that the statements inside its call to `effectuate` get executed.

A step fullfilling "task a" is to be formulated as follows. In the example below, `data` is the instance of a class being changed during the execution (of cource, our steps could also return a value, and different interacting steps can have different arguments). The execution keeps track of the steps run by using _a unique identifier for each step._ An instance of `StepID` is used as such an identifier, which contains a) a designation for the file that is unique across modules (using [concise magic file name](https://github.com/apple/swift-evolution/blob/main/proposals/0274-magic-file.md)), and b) using the function signature which is unique when using only top-level functions as steps.

```Swift
@Step
func a_step(
    during execution: Execution,
    data: MyData
) {
    execution.log(.info, "working in step a")
}
```

---
**Convention**

- A function representing a step is a top-level function.

---

Let us see how we call the step `a_step` inside another step `b_step`:

```Swift
@Step
func b_step(
    during execution: Execution,
    data: MyData
) {
    a_step(during: execution, data: data)
    execution.log(.info, "working in step b")
}
```

Here, the call to `a_step` can be seen as the formulation of a requirement for the work done by `b_step`.

Let us take another step `c_step` which first calls `a_step`, and then `b_step`:

```Swift
@Step
func c_step(
    during execution: Execution,
    data: MyData
) {
    a_step(during: execution, data: data)
    b_step(during: execution, data: data)
        
    execution.log(.info, "working in step c")
}
```

Again, `a_step` and `b_step` can be seen here as requirements for the work done by `c_step`.

When using `c_step`, inside `b_step` the step `a_step` is _not_ being executed, because `a_step` has already been excuted at that time. By default it is assumed that a step does some manipulation of the data, and calling a step  says "I want those manipulation done at this point". This is very common in complex processing scenarios and having this behaviour ensures that a step can be called in isolation and not just as part as a fixed, large processing pipeline, because it formulates itself which prerequisites it needs.[^2]

[^2]: Note that a bad formulation of your logic can get you in trouble with the order of the steps: If `a_step` should be executed before `b_step` and not after it, and when calling `c_step`, `b_step` has already been executed but not `a_step` (so, other than in our example, `a_step` is not given as a requirement for `b_step`), you will get the wrong order of execution. In practice, we never encountered such a problem.

---
**Convention**

Requirements for a step are formulated by just calling the accordings steps (i.e. the steps that fullfill the requirements) inside the step. (Those steps will not run again if they already have been run.)

---


But sometimes a certain other step is needed just before a certain point in the processing, no matter if it already has been run before. In that case, you can use the `force` method of the execution:

```Swift
@Step
func b_step(
    during execution: Execution,
    data: MyData
) {
    execution.force {
        a_step(during: execution, data: data)
    }
    
    execution.log(.info, "working in step b")
}
```

Now `a_step` always runs inside `b_step` (if `b_step` gets executed).

Note that any sub-steps of a forced step are _not_ automatically forced. But you can pass a forced execution onto a sub-step by calling it inside `inheritForced`:

```Swift
@Step
func b_step(
    during execution: Execution,
    data: MyData
) {
    execution.inheritForced {
        // this execution of a_step is forced if the current execution of b_step has been forced:
        a_step(during: execution, data: data)
    }
    
    execution.log(.info, "working in step b")
}
```

---
**Convention**

Use the `Execution.force` method if a certain step has to be run at a certain point no matter if it already has been run before.

---

### How to return values

If the step is to return a value, this must to be an optional one:

```Swift
@Step
func my_step(
    during execution: Execution,
    data: MyData
) -> String? {
    return "my result"
}
```

The reason for this is that the body of this function might not be executed, so if you return a `String` inside the function body, then the return type of the function is `String?`. 

And if the function body is itself is meant to return an optional value:

```Swift
@Step
func optionalHello_step(during execution: Execution, condition: Bool) -> String?? {
    if condition {
        return "hello 1"
    } else {
        return nil
    }
}
```

Which can be used as follows:

```swift
@Step
func hello_step(during execution: Execution, condition: Bool) -> String? {
    if let executionResult = optionalHello_step(during: execution, condition: condition),
       let value = executionResult {
        return value
    } else {
        return "hello 2"
    }
}
```

### Outsourcing functionality into a new package

The tree-like pattern of steps that you are able to use in a workflow is a natural starting point to outsource some functionality of your workflow into an external package.

### Organisation of the code in the files

We think it a a sensible thing to use one file for one step. Together with the step data (which includes the error messages, see below), maybe an according library function, or a job function (see below), this "fits" very well a file in many case.

We also prefer to use folders with scripts according to the calling structure as far as possible, and we like to use a prefix `_external_` for the names of folders and source files if the contained steps actually call external steps i.e. library functions as described above.

### Limitations

This approach has as limitation that a library function is a kind of isolated step: From the view of a library function being called, there are no step functions that already have been run. In some cases, this limitation might lead to preparation steps done sevaral times, or certain prerequisites have to be formulated in the documentation of the library function and the according measures then taken in the wrapper of the library function. Conversely, to the outside not all that has been done by the library function might be taken into account in subsequent steps.

In practice we think that this limitation is not a severe one, because usually a library function is a quite encapsulated unit that applies, so to speak, some collected knowledge to a certain problem field and _should not need to know much_ about the outside.

### Jobs

Steps as described should be flexible enough for the definition of a sequence of processing. But in some circumstances you might want to distinguish between a step that reads (and maybe writes) the data that you would like to process, and the steps in between that processes that data. A step that reads (and maybe writes) the data would then be the starting point for a processing. We call such a step a “job” and give its name the postfix `_job` instead of `_step`:

```Swift
@Step
func helloAndBye_job(
    during execution: Execution,
    file: URL
) {
    
    // get the data:
    guard let data = readData_step(during: execution, file: file) else { return }
    
    // start the processing of the data:
    helloAndBye_step(during: execution, data: data)
}
```

So a job is a kind of step that can be called on top-level i.e. not from within another step.

It is a good practice to always create a job for each step even if such a job is not planned for the final product, so one can test each step separately by calling the according job.

### Using an execution just for logging

You might use an `Execution` instance ouside any step just to make the logging streamlined.

### Jobs as starting point for the same kind of data

Let us suppose you have jobs that all share the same arguments and the same data (i.e. the same return values) and you would like to decide by a string value (which could be the value of a command line argument) which job to start.

So a job looks e.g. as follows:

```Swift
typealias Job = (
    Execution,
    URL
) -> ()
```

In this case we like to use a "job registry" as follows (for the step data, see the section below):

```Swift
var jobRegistry: [String:(Job?,StepData)] = [
    "hello-and-bye": JobAndData(job: helloAndBye_job, stepData: HelloAndBye_stepData.instance),
    // ...
]
```

The step data – more on that in the next section – is part of the job registry so that all possible messages can be automatically collected by a `StepDataCollector`, which is great for documentation. (This is why the job in the registry is optional, so you can have messages not related to a step, but nevertheless formulated inside a `StepData`, be registered here under an abstract job name.)

The resolving of a job name and the call of the appropriate job is then done as follows:

```Swift
    if let jobFunction = jobRegistry[job]?.job {
        
        let logger = PrintingLogger()
        let myExecutionEventProcessor = ExecutionEventProcessorForLogger(withMetaDataInfo: metadata.description, logger: logger)
        let execution = Execution(executionEventProcessor: myExecutionEventProcessor)
        
        jobFunction(
            execution,
            URL(fileURLWithPath: path)
        )
    }
    else {
        // error...
    }
```

### Spare usage of step arguments

Generally, a step should only get as data what it really needs in its arguments. E.g. handling over a big collection of configuration data might ease the formulation of the steps, but being more explicit here - i.e. handling over just the parts of the configuration data that the step needs – makes the usage of the data much more transparent and modularization (i.e. the extraction of some step into a separate, independant package) easy.

### Step data

Each step should have an instance of `StepData` in its script with:

- a short description of the step, and
- a collection of message that can be used when logging.

When logging, only the messages declared in the step data should be used.

A message is a collection of texts with the language as keys, so you can define
the message text in different languages. The message also defines the type of the
message, e.g. if it informs about the progress or about a fatal error.

The message types (of type `MessageType`, e.g. `Info` or `Warning`) have a strict order, so you can choose the minimal level for a message to be logged. But the message type `Progress` is special: if progress should be logged is defined by an additional parameter.

See the example project for more details.

### Appeasing log entries

The error class is used when logging represents the point of view of the step or package. This might not coincide with the point of view of the whole application. Example: It is fatal for an image library if the desired image cannot be generated, but for the overall process it may only be a non-fatal error, an image is then simply missing.

So the caller can execute the according code in `execution.appease { … }`. In side this code, any error worse than `Error` is set to `Error`. Instead if this default `Error`, you can also specify the message type to which you want to appease via `execution.appease(to: …) { … }`. The original error type is preserved as field `originalType` of the logging event.

So using an "external" step would actually be formulated as follows in most cases:

```Swift
@Step
func hello_external_step(
    during execution: Execution,
    data: MyData
) {
    execution.appease {
        hello_lib(during: execution, data: data)
    }
}
```

### Getting the worst message type

Tracking the the worst message type should be done by the `ExecutionEventProcessor`. This worst message type could be a value of the actual logging system.

### Throwing errors

If an error occurs during a step, it is naturally propagated until it is caught in the code. There is no special handling of thrown errors by the framework. So step where the error is not catched yet will not be ending (an according message is not being logged), but as soon as the error gets catched inside a step, the following events do have the correct level and execution path.

### Stopping the execution

Usually the execution stops at a fatal or deadly error (you can change this behaviour by setting `stopAtFatalError: false` when initializing the `Execution`). That means that in such a case no new step is started.

The execution can also be informed via the `stop(reason:)` message that the execution should be stopped.

Note that any following code not belonging to any further step is still being executed.

### Working in asynchronous contexts

A step might also be asynchronous, i.e. the caller might get suspended. Let's suppose that for some reason `bye_step` from above is async (maybe we are building a web application and `bye_step` has to fetch data from a database):

```Swift
@Step
func bye_step(
    during execution: AsyncExecution,
    data: MyData
) async {
    ...
```

As mentioned above, you have to use `AsyncExecution`, and you can get call synchronous step with the `Execution` instance `execution.synchronous`.

### The tree view on logging

The `ExecutionEvent` instance can actually seen as part of a tree, e.g. the begin message of a step together with the end message for the same message can be seen as a node containing everything that is logged in-between. Your might want to actually build a tree from it, and the `level` contained in the `ExecutionEvent` is actually all you need for this, but all `ExecutionEvent` instances that do not act as a leave in this tree view have a UUID `structuralID` to help you with that.

Note that when logging by directly using your logging implemention and not the `Execution` instance, you do not get an `ExecutionEvent` and there your log messages are not part of the sdescribed tructure.

### Pause/stop

In order to pause or stop the execution of steps, appropriate methods of `Execution` are available. See the `pauseTest()` function in the tests.

### Parallel execution

To execute steps in parallel, first get the current state of the execution, which is then used to initialize execution with that state in parallel.

See the examples in the `ParallelTests` test suite.

Note that no new state from the parellel execution are put back into the oroginal execution. In particular the parallel steps are not registered in the original execution, and so is any stop not brought to the original execution.
