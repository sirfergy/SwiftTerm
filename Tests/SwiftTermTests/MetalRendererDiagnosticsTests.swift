#if os(macOS) && canImport(MetalKit)
import AppKit
import Foundation
import Metal
import Testing
@testable import SwiftTerm

@Suite("Metal renderer diagnostic observations")
struct MetalRendererDiagnosticsTests {
    @Test func reportsOnlyActualCommandErrors() {
        let events = Locked<[MetalDiagnosticEvent]>([])
        let log = MetalDiagnosticLog { event in events.withLock { $0.append(event) } }
        let diagnostics = MetalRendererDiagnostics(log: log)
        for status in [MTLCommandBufferStatus.notEnqueued, .enqueued, .committed, .scheduled, .completed] {
            diagnostics.reportCommandResult(status: status, errorCode: 7)
        }
        #expect(events.withLock { $0.isEmpty })
        diagnostics.reportCommandResult(status: .error, errorCode: 7)
        diagnostics.reportCommandResult(status: .error, errorCode: nil)
        #expect(events.withLock { $0 } == [.commandBufferError(code: 7), .commandBufferError(code: nil)])
    }

    @Test func delayRequiresAnOutstandingSubmissionAndTheThreshold() {
        let events = Locked<[MetalDiagnosticEvent]>([])
        let log = MetalDiagnosticLog { event in events.withLock { $0.append(event) } }
        let diagnostics = MetalRendererDiagnostics(log: log)
        diagnostics.reportDelayedCompletion(at: 10_000_000_000)
        diagnostics.submitted(at: 1_000_000_000)
        diagnostics.reportDelayedCompletion(at: 0)
        diagnostics.reportDelayedCompletion(at: 5_999_999_999)
        #expect(events.withLock { $0.isEmpty })
        diagnostics.reportDelayedCompletion(at: 6_000_000_000)
        #expect(events.withLock { $0 } == [.completionDelayed(seconds: 5)])
        diagnostics.completed()
        diagnostics.reportDelayedCompletion(at: 30_000_000_000)
        #expect(events.withLock { $0.count } == 1)
    }

    @Test func clearingBeforeTheNextSubmissionPreservesItsTimestamp() {
        let events = Locked<[MetalDiagnosticEvent]>([])
        let log = MetalDiagnosticLog { event in events.withLock { $0.append(event) } }
        let diagnostics = MetalRendererDiagnostics(log: log)
        diagnostics.submitted(at: 1_000_000_000)
        diagnostics.completed()
        diagnostics.submitted(at: 10_000_000_000)
        diagnostics.reportDelayedCompletion(at: 14_000_000_000)
        #expect(events.withLock { $0.isEmpty })
        diagnostics.reportDelayedCompletion(at: 16_000_000_000)
        #expect(events.withLock { $0 } == [.completionDelayed(seconds: 6)])
    }

    @Test func budgetIsSharedAcrossRendererLifetimesAndConcurrentWriters() {
        let events = Locked<[MetalDiagnosticEvent]>([])
        let log = MetalDiagnosticLog { event in events.withLock { $0.append(event) } }
        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            let diagnostics = MetalRendererDiagnostics(log: log)
            diagnostics.log.record(.transientGlyphFailure)
            diagnostics.reportCommandResult(status: .error, errorCode: 3)
            diagnostics.submitted(at: 0)
            diagnostics.reportDelayedCompletion(at: 6_000_000_000)
            diagnostics.log.record(.idleWaitTimedOut(seconds: 5))
        }
        let recorded = events.withLock { $0 }
        #expect(recorded.count == 20)
        #expect(recorded.filter { $0 == .transientGlyphFailure }.count == 5)
        #expect(recorded.filter { $0 == .commandBufferError(code: 3) }.count == 5)
        #expect(recorded.filter { $0 == .completionDelayed(seconds: 6) }.count == 5)
        #expect(recorded.filter { $0 == .idleWaitTimedOut(seconds: 5) }.count == 5)
    }

    @Test func sinkRunsOutsideTheBudgetLock() {
        let calls = Locked(0)
        let reference = Locked<MetalDiagnosticLog?>(nil)
        let log = MetalDiagnosticLog { _ in
            calls.withLock { $0 += 1 }
            reference.withLock { $0 }?.record(.transientGlyphFailure)
        }
        reference.withLock { $0 = log }
        log.record(.transientGlyphFailure)
        reference.withLock { $0 = nil }
        #expect(calls.withLock { $0 } == 5)
    }
}

#if DEBUG
@MainActor
@Suite(.serialized, .enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct MetalRendererDiagnosticWiringTests {
    @MainActor
    private final class Fixture {
        let view: TerminalView
        let target: TerminalMetalLayerView
        let renderer: MetalTerminalRenderer
        let snapshot = TerminalSnapshot()
        let events = Locked<[MetalDiagnosticEvent]>([])
        let redraws = Locked(0)

        init(mode: MetalBufferingMode, text: String) throws {
            let bounds = CGRect(x: 0, y: 0, width: 240, height: 90)
            view = TerminalView(frame: bounds, font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                                options: TerminalOptions(cols: 12, rows: 3))
            try view.setUseMetal(false)
            view.metalBufferingMode = mode
            view.feed(text: "\u{1b}[?25l" + text)
            target = TerminalMetalLayerView(frame: bounds)
            target.renderContentsScale = view.metalRenderingScaleFactor()
            target.renderDrawableSize = CGSize(width: bounds.width * target.renderContentsScale,
                                                height: bounds.height * target.renderContentsScale)
            let events = events
            renderer = try MetalTerminalRenderer(target: target, diagnosticLog: MetalDiagnosticLog { event in
                events.withLock { $0.append(event) }
            })
            renderer.waitForCompletionAfterCommit = true
            let redraws = redraws
            renderer.requestRedraw = { redraws.withLock { $0 += 1 } }
            let state = FrameViewState(view: view)
            let result = view.withTerminal { terminal in
                snapshot.refresh(terminal: terminal, viewState: state,
                                 selection: SnapshotSelectionState(selection: view.selection))
            }
            try #require(result == .refreshed)
        }

        func render() throws {
            let context = try #require(snapshot.renderContext)
            renderer.prepareSnapshotForImmediateDraw(snapshot: snapshot, context: context)
            let frame = try #require(target.acquireDrawableFrame())
            let before = renderer.completedRenders
            renderer.render(frame: frame)
            try #require(renderer.completedRenders == before + 1)
            try #require(renderer.waitForIdle())
        }
    }

    @Test(arguments: [MetalBufferingMode.perRowPersistent, .perFrameAggregated])
    func observesFailureWithoutRetryOrCacheInvalidation(mode: MetalBufferingMode) throws {
        let fixture = try Fixture(mode: mode, text: "A")
        defer { _ = fixture.view.updateUiClosed() }
        fixture.renderer.forceContextCreationFailureForTesting = true
        try fixture.render()
        let events = fixture.events.withLock { $0 }
        #expect(events.contains(.transientGlyphFailure))
        #expect(fixture.redraws.withLock { $0 } == 0)
        #expect(!fixture.view.isUsingMetalRenderer)

        fixture.renderer.forceContextCreationFailureForTesting = false
        try fixture.render()
        #expect(fixture.renderer.debugRowCacheCounts.rebuilt == 0)
        #expect(fixture.renderer.debugRowCacheCounts.cached == fixture.snapshot.rows.count)
        #expect(fixture.redraws.withLock { $0 } == 0)
        #expect(fixture.events.withLock { $0 } == events)
    }

    @Test(arguments: [MetalBufferingMode.perRowPersistent, .perFrameAggregated])
    func emptyGlyphsAreNotReportedAsFailures(mode: MetalBufferingMode) throws {
        let fixture = try Fixture(mode: mode, text: "   ")
        defer { _ = fixture.view.updateUiClosed() }
        fixture.renderer.forceContextCreationFailureForTesting = true
        try fixture.render()
        #expect(fixture.events.withLock { $0.isEmpty })
        #expect(fixture.redraws.withLock { $0 } == 0)
    }
}
#endif
#endif
