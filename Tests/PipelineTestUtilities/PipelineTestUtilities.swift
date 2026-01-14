import Foundation
import PipelineCore

public protocol Logger: Sendable {
    func log(_ message: String)
    func close()
}

// from README:
public class PrintingLogger: @unchecked Sendable, Logger {
    
    public func log(_ message: String) {
        print(message)
    }
    
    public func close() {
        // -
    }
    
}

public final class CollectingLogger: @unchecked Sendable, Logger {
    
    public var _messages = [String]()
    
    public init() {}
    
    /// Gets the current messages.
    public var messages: [String] {
        wait()
        return _messages
    }
    
    internal let group = DispatchGroup()
    internal let queue = DispatchQueue(label: "CollectingLogger", qos: .background)
    
    public func log(_ message: String) {
        group.enter()
        self.queue.sync {
            self._messages.append(message)
            self.group.leave()
        }
    }
    
    /// Wait until all logging is done.
    public func wait() {
        group.wait()
    }
    
    public func close() {
        wait()
    }
    
}

/// Keeps track of the severity i.e. the worst message type.
public final class SeverityTracker: @unchecked Sendable {
    
    private var _severity = InfoType.allCases.min()!
    
    /// Gets the current severity.
    var value: InfoType {
        wait()
        return _severity
    }
    
    internal let group = DispatchGroup()
    internal let queue = DispatchQueue(label: "CollectingLogger", qos: .background)
    
    public func process(_ newSeverity: InfoType) {
        group.enter()
        self.queue.sync {
            if newSeverity > _severity {
                _severity = newSeverity
            }
            self.group.leave()
        }
    }
    
    /// Wait until all logging is done.
    public func wait() {
        group.wait()
    }
    
}

public struct ExecutionEventProcessorForLogger: ExecutionEventProcessor {
    
    public let metadataInfo: String
    public let metadataInfoForUserInteraction: String
    
    private let logger: Logger
    private let severityTracker = SeverityTracker()
    private let minimalInfoType: InfoType?
    private let excutionInfoFormat: ExecutionInfoFormat?
    
    /// The the severity i.e. the worst message type.
    public var severity: InfoType { severityTracker.value }
    
    /// This closes all logging.
    public func closeEventProcessing() throws {
        logger.close()
    }
    
    public init(
        withMetaDataInfo metadataInfo: String,
        withMetaDataInfoForUserInteraction metadataInfoForUserInteraction: String? = nil,
        logger: Logger,
        withMinimalInfoType minimalInfoType: InfoType? = nil,
        excutionInfoFormat: ExecutionInfoFormat? = nil
    ) {
        self.metadataInfo = metadataInfo
        self.metadataInfoForUserInteraction = metadataInfoForUserInteraction ?? metadataInfo
        self.logger = logger
        self.minimalInfoType = minimalInfoType
        self.excutionInfoFormat = excutionInfoFormat
    }
    
    public func process(_ executionEvent: ExecutionEvent) {
        severityTracker.process(executionEvent.type)
        if let minimalInfoType, executionEvent.type < minimalInfoType {
            return
        }
        if let excutionInfoFormat {
            logger.log(executionEvent.description(format: excutionInfoFormat, withMetaDataInfo: metadataInfo))
        } else {
            logger.log(executionEvent.description(withMetaDataInfo: metadataInfo))
        }
    }
    
}

public struct MyMetaData: CustomStringConvertible, Sendable {
    
    let applicationName: String
    let processID: String
    let workItemInfo: String
    
    public init(applicationName: String, processID: String, workItemInfo: String) {
        self.applicationName = applicationName
        self.processID = processID
        self.workItemInfo = workItemInfo
    }
    
    public var description: String {
        "\(applicationName): \(processID)/\(workItemInfo)"
    }
}

/// Process the items in `batch` in parallel by the function `worker`
/// (only a subset of the items might actually be processed simultaneously).
public func parallel<T: Sendable>(batch: Array<T>, worker: @escaping @Sendable (T) async -> ()) async {
    await withTaskGroup(of: Void.self) { taskGroup in
        for work in batch {
            taskGroup.addTask {
                await worker(work)
            }
        }
    }
}

/// Process the items in `batch` in parallel by the function `worker`,
/// but no more than`maximalSimultaneousOperations` at the same time
/// (the number of items actually being processed simultaneously could be lower).
public func parallel<T: Sendable>(batch: Array<T>, maximalSimultaneousOperations: Int, worker: @escaping @Sendable (T) async -> ()) async {
    await withTaskGroup(of: Void.self) { taskGroup in
        for (index,work) in batch.enumerated() {
            if index >= maximalSimultaneousOperations {
                _ = await taskGroup.next()
            }
            taskGroup.addTask {
                await worker(work)
            }
        }
    }
}

public extension String {
    var firstPathPart: Substring {
        self.split(separator: "/", omittingEmptySubsequences: false).first!
    }
}

/// Get the ellapsed seconds since `start`.
/// The time to compare to is either the current time or the value of the argument `reference`.
public func elapsedSeconds(start: ContinuousClock.Instant, reference: ContinuousClock.Instant = ContinuousClock.now) -> Double {
    let duration = start.duration(to: reference)
    return Double(duration.attoseconds) / 1e18
}

public func elapsedTime(of f: () -> Void) -> Double {
    let startTime = ContinuousClock.now
    f()
    return elapsedSeconds(start: startTime)
}

public func elapsedTime(of f: () async -> Void) async -> Double {
    let startTime = ContinuousClock.now
    await f()
    return elapsedSeconds(start: startTime)
}

public struct TestError: Error, CustomStringConvertible  {
    
    public let description: String
    
    public var localizedDescription: String { description }
    
    public init(_ description: String) {
        self.description = description
    }
}

public struct UUIDReplacements {
    
    var count = 0
    var mapped = [String:String]()
    
    public init() {}
    
    public mutating func replacement(for token: String) -> String {
        if let existing = mapped[token] {
            return existing
        } else {
            count += 1
            let replacement = "#\(count)"
            mapped[token] = replacement
            return replacement
        }
    }
    
    public mutating func doReplacements(in text: String) -> String {
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
