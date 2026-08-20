#if os(macOS) && canImport(MetalKit)
import AppKit
import MetalKit
import Testing

@testable import SwiftTerm

@MainActor
struct MetalRendererToggleTests {
    @Test("Metal view can be reinserted after the caret leaves the view hierarchy")
    func reinsertMetalViewWithoutCaretSuperview() {
        guard MTLCreateSystemDefaultDevice() != nil else { return }

        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        view.caretView.removeFromSuperview()
        let metalView = MTKView(frame: view.bounds)
        view.insertMetalView(metalView, replacing: nil)

        #expect(metalView.superview === view)
    }
}
#endif
