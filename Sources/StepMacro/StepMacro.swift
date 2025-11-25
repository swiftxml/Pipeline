@attached(body)
public macro Step(_ description: String? = nil) = #externalMacro(module: "StepMacros", type: "StepMacro")
