#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import Metal
import os

enum MetalDiagnosticEvent: Sendable, Equatable {
    case transientGlyphFailure
    case commandBufferError(code: Int?)
    case completionDelayed(seconds: TimeInterval)
    case idleWaitTimedOut(seconds: TimeInterval)

    fileprivate var kind: Int {
        switch self {
        case .transientGlyphFailure: 0
        case .commandBufferError: 1
        case .completionDelayed: 2
        case .idleWaitTimedOut: 3
        }
    }
}

final class MetalDiagnosticLog: Sendable {
    static let shared = MetalDiagnosticLog()
    private static let logger = Logger(subsystem: "org.tirania.SwiftTerm", category: "MetalDiagnostics")
    private let counts = Locked([0, 0, 0, 0])
    private let write: @Sendable (MetalDiagnosticEvent) -> Void

    init(write: @escaping @Sendable (MetalDiagnosticEvent) -> Void = MetalDiagnosticLog.writeLog) {
        self.write = write
    }

    func record(_ event: MetalDiagnosticEvent) {
        let allowed = counts.withLock { counts in
            guard counts[event.kind] < 5 else { return false }
            counts[event.kind] += 1
            return true
        }
        if allowed { write(event) }
    }

    private static func writeLog(_ event: MetalDiagnosticEvent) {
        switch event {
        case .transientGlyphFailure:
            logger.warning("event=transient_glyph_rasterization_failure")
        case .commandBufferError(let code):
            let codeText = code.map(String.init) ?? "unavailable"
            logger.error("event=command_buffer_error code=\(codeText, privacy: .public)")
        case .completionDelayed(let seconds):
            logger.warning("event=completion_callback_not_observed elapsed_seconds=\(seconds, privacy: .public); GPU failure is not established")
        case .idleWaitTimedOut(let seconds):
            logger.warning("event=renderer_idle_wait_timed_out timeout_seconds=\(seconds, privacy: .public)")
        }
    }
}

final class MetalRendererDiagnostics: Sendable {
    let log: MetalDiagnosticLog
    private let submittedAt = Locked<UInt64?>(nil)

    init(log: MetalDiagnosticLog = .shared) {
        self.log = log
    }

    func submitted(at now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        submittedAt.withLock { $0 = now }
    }

    // Clear before releasing the frame permit, so an old completion cannot
    // erase the timestamp published by the next frame.
    func completed() {
        submittedAt.withLock { $0 = nil }
    }

    func reportCommandResult(status: MTLCommandBufferStatus, errorCode: Int?) {
        if status == .error {
            log.record(.commandBufferError(code: errorCode))
        }
    }

    // Observe only on an existing refusal/timeout path; there is no watchdog
    // and a completely idle pending frame is not detected automatically.
    func reportDelayedCompletion(at now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        let elapsed = submittedAt.withLock { start -> TimeInterval? in
            guard let start, now >= start else { return nil }
            return Double(now - start) / 1_000_000_000
        }
        if let elapsed, elapsed >= 5 {
            log.record(.completionDelayed(seconds: elapsed))
        }
    }
}
#endif
