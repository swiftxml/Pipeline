import Foundation
import PipelineCore

protocol Logger: Sendable {
    func log(_ message: String)
    func close()
}

// from README:
public class PrintingLogger: @unchecked Sendable, Logger {
    
    public func log(_ message: String) {
        print(message)
    }
    
    func close() {
        // -
    }
    
}

public final class CollectingLogger: @unchecked Sendable, Logger {
    
    private var _messages = [String]()
    let messagesSemaphore = DispatchSemaphore(value: 1)
    
    /// Gets the current messages.
    var messages: [String] {
        messagesSemaphore.wait()
        let value = _messages
        messagesSemaphore.signal()
        return value
    }
    
    internal let group = DispatchGroup()
    internal let queue = DispatchQueue(label: "CollectingLogger", qos: .background)
    
    public func log(_ message: String) {
        group.enter()
        self.queue.sync {
            messagesSemaphore.wait()
            self._messages.append(message)
            messagesSemaphore.signal()
            self.group.leave()
        }
    }
    
    /// Wait until all logging is done.
    public func wait() {
        group.wait()
    }
    
    func close() {
        wait()
    }
    
}

/// Keeps track of the severity i.e. the worst message type.
public final class SeverityTracker: @unchecked Sendable {
    
    private var _severity = InfoType.allCases.min()!
    let messagesSemaphore = DispatchSemaphore(value: 1)
    
    /// Gets the current severity.
    var value: InfoType {
        messagesSemaphore.wait()
        wait()
        let value = _severity
        messagesSemaphore.signal()
        return value
    }
    
    internal let group = DispatchGroup()
    internal let queue = DispatchQueue(label: "CollectingLogger", qos: .background)
    
    public func process(_ newSeverity: InfoType) {
        group.enter()
        self.queue.sync {
            messagesSemaphore.wait()
            if newSeverity > _severity {
                _severity = newSeverity
            }
            messagesSemaphore.signal()
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
    var severity: InfoType { severityTracker.value }
    
    /// This closes all logging.
    public func closeEventProcessing() throws {
        logger.close()
    }
    
    init(
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

struct MyMetaData: CustomStringConvertible {
    
    let applicationName: String
    let processID: String
    let workItemInfo: String
    
    var description: String {
        "\(applicationName): \(processID)/\(workItemInfo)"
    }
}

/// Process the items in `batch` in parallel by the function `worker` using `threads` number of threads.
public func executeInParallel<T: Sendable>(batch: any Sequence<T>, threads: Int, worker: @escaping @Sendable (T) -> ()) {
    let queue = DispatchQueue(label: "executeInParallel", attributes: .concurrent)
    let group = DispatchGroup()
    let semaphore = DispatchSemaphore(value: threads)
    
    for item in batch {
        group.enter()
        semaphore.wait()
        queue.async {
            worker(item)
            semaphore.signal()
            group.leave()
        }
    }
    
    group.wait()
}

/// Process the items in `batch` in parallel by the function `worker` using `threads` number of threads.
public func executeInParallel<T: Sendable>(batch: any Sequence<T>, threads: Int, worker: @escaping @Sendable (T) async -> ()) {
    let group = DispatchGroup()
    let semaphore = DispatchSemaphore(value: threads)
    
    for item in batch {
        group.enter()
        semaphore.wait()
        Task {
            await worker(item)
            semaphore.signal()
            group.leave()
        }
    }
    
    group.wait()
}

extension String {
    var firstPathPart: Substring {
        self.split(separator: "/", omittingEmptySubsequences: false).first!
    }
}

/// Get the ellapsed seconds since `start`.
/// The time to compare to is either the current time or the value of the argument `reference`.
func elapsedSeconds(start: ContinuousClock.Instant, reference: ContinuousClock.Instant = ContinuousClock.now) -> Double {
    let duration = start.duration(to: reference)
    return Double(duration.attoseconds) / 1e18
}

func elapsedTime(of f: () -> Void) -> Double {
    let startTime = ContinuousClock.now
    f()
    return elapsedSeconds(start: startTime)
}

func elapsedTime(of f: () async -> Void) async -> Double {
    let startTime = ContinuousClock.now
    await f()
    return elapsedSeconds(start: startTime)
}

public struct TestError: Error, CustomStringConvertible  {
    public let description: String
    
    var localizedDescription: String { description }
    
    public init(_ description: String) {
        self.description = description
    }
}

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
