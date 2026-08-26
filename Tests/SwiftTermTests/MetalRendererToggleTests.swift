#if os(macOS) && canImport(MetalKit)
import AppKit
import MetalKit
import Testing

@testable import SwiftTerm

@MainActor
struct MetalRendererToggleTests {
    @Test("Metal replacement keeps the old surface beneath the new one when the caret is detached")
    func replaceMetalViewWithoutCaretSuperview() throws {
        let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        let oldView = MTKView(frame: view.bounds)
        view.addSubview(oldView)
        view.caretView.removeFromSuperview()
        let newView = MTKView(frame: view.bounds)

        view.insertMetalView(newView, replacing: oldView)

        let oldIndex = try #require(view.subviews.firstIndex { $0 === oldView })
        let newIndex = try #require(view.subviews.firstIndex { $0 === newView })
        #expect(newIndex > oldIndex)
        #expect(view.caretView.isHidden)
    }
}
#endif
