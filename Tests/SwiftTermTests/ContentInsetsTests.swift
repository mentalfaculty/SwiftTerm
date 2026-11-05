//
//  ContentInsetsTests.swift
//  SwiftTermTests
//
//  The Mac view's `contentInsets`: the grid is computed from and drawn inside
//  the bounds less the insets, points map to cells relative to the inset grid,
//  and the top inset shows the scrollback just above the first visible row.
//

#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import SwiftTerm

@MainActor
@Suite("ContentInsets", .serialized)
struct ContentInsetsTests {
    static let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
    static let insets = NSEdgeInsets(top: 30, left: 10, bottom: 6, right: 12)

    private func makeView(frame: CGRect = ContentInsetsTests.frame) throws -> TerminalView {
        let font = try #require(NSFont(name: "Monaco", size: 12))
        return TerminalView(frame: frame, font: font)
    }

    private func gridSize(_ view: TerminalView) -> (cols: Int, rows: Int) {
        view.withTerminal { ($0.cols, $0.rows) }
    }

    // MARK: - Grid size

    @Test func zeroInsetsAreTheDefaultAndChangeNothing() throws {
        let view = try makeView()
        #expect(NSEdgeInsetsEqual(view.contentInsets, NSEdgeInsetsZero))
        #expect(view.frameContentInsets == .zero)
        let size = gridSize(view)
        #expect(size.cols == Int(Self.frame.width / view.cellDimension.width))
        #expect(size.rows == Int(Self.frame.height / view.cellDimension.height))
        #expect(view.getOptimalFrameSize().size ==
                CGSize(width: CGFloat(size.cols) * view.cellDimension.width,
                       height: CGFloat(size.rows) * view.cellDimension.height))
    }

    @Test func insetsShrinkTheGridAndResizeTheTerminal() throws {
        let view = try makeView()
        let before = gridSize(view)
        view.contentInsets = Self.insets
        let cell = view.cellDimension!
        let size = gridSize(view)
        #expect(size.cols == Int((Self.frame.width - 22) / cell.width))
        #expect(size.rows == Int((Self.frame.height - 36) / cell.height))
        #expect(size.rows < before.rows)

        view.contentInsets = NSEdgeInsetsZero
        #expect(gridSize(view) == before)
    }

    @Test func frameChangesKeepTheInsets() throws {
        let view = try makeView()
        view.contentInsets = Self.insets
        view.setFrameSize(CGSize(width: 500, height: 400))
        let cell = view.cellDimension!
        let size = gridSize(view)
        #expect(size.cols == Int((500 - 22) / cell.width))
        #expect(size.rows == Int((400 - 36) / cell.height))
    }

    @Test func optimalFrameSizeIncludesTheInsets() throws {
        let view = try makeView()
        view.contentInsets = Self.insets
        let cell = view.cellDimension!
        let size = gridSize(view)
        #expect(view.getOptimalFrameSize().size ==
                CGSize(width: CGFloat(size.cols) * cell.width + 22,
                       height: CGFloat(size.rows) * cell.height + 36))
    }

    @Test func negativeInsetsCountAsZero() throws {
        let view = try makeView()
        let before = gridSize(view)
        view.contentInsets = NSEdgeInsets(top: -10, left: -4, bottom: -1, right: -2)
        #expect(view.frameContentInsets == .zero)
        #expect(gridSize(view) == before)
    }

    // MARK: - Points to cells

    /// The view is not flipped: y grows upwards from the bottom edge.
    private func point(col: CGFloat, row: CGFloat, in view: TerminalView) -> CGPoint {
        let cell = view.cellDimension!
        let insets = view.frameContentInsets
        return CGPoint(x: insets.left + col * cell.width,
                       y: view.frame.height - insets.top - row * cell.height)
    }

    @Test func mouseHitIsMeasuredFromTheInsetGrid() throws {
        let view = try makeView()
        view.contentInsets = Self.insets
        let hit = view.calculateMouseHit(at: point(col: 2.5, row: 1.5, in: view))
        #expect(hit.grid == Position(col: 2, row: 1))

        // Without the insets the same point is another cell.
        let plain = try makeView()
        let plainHit = plain.calculateMouseHit(at: point(col: 2.5, row: 1.5, in: view))
        #expect(plainHit.grid != hit.grid)
    }

    @Test func pointsInTheInsetsGoToTheNearestCell() throws {
        let view = try makeView()
        view.contentInsets = Self.insets
        let size = gridSize(view)
        // Feed enough lines that there is scrollback above the screen.
        view.feed(text: String(repeating: "line\r\n", count: size.rows * 2))
        let yDisp = view.withTerminal { $0.displayBuffer.yDisp }
        #expect(yDisp > 0)

        // Near the top edge of the view, well inside the 30 point top inset.
        let top = view.calculateMouseHit(at: CGPoint(x: 50, y: Self.frame.height - 2))
        #expect(top.grid.row == yDisp)
        #expect(top.pixels.row == 0)

        let left = view.calculateMouseHit(at: point(col: -0.5, row: 0.5, in: view))
        #expect(left.grid.col == 0)

        let bottom = view.calculateMouseHit(at: CGPoint(x: 50, y: 1))
        #expect(bottom.grid.row == yDisp + size.rows - 1)

        // Scrolled back, the bottom inset still goes to the last row on
        // screen, not to the line below it.
        view.scrollUp(lines: 5)
        let scrolled = view.withTerminal { $0.displayBuffer.yDisp }
        #expect(scrolled == yDisp - 5)
        let bottomScrolled = view.calculateMouseHit(at: CGPoint(x: 50, y: 1))
        #expect(bottomScrolled.grid.row == scrolled + size.rows - 1)
    }

    @Test func characterIndexUsesTheInsetGrid() throws {
        let view = try makeView()
        view.contentInsets = Self.insets
        // Outside a window, view and window coordinates are the same.
        let local = point(col: 3.5, row: 2.5, in: view)
        let index = view.characterIndex(for: local)
        #expect(index == 2 * gridSize(view).cols + 3)
    }

    // MARK: - Caret

    @Test func caretIsPlacedInsideTheInsets() throws {
        let view = try makeView()
        view.contentInsets = Self.insets
        view.feed(text: "abc\r\nde")
        view.updateCursorPosition()
        let cell = view.cellDimension!
        let caret = view.caretFrame
        #expect(caret.origin.x == 10 + 2 * cell.width)
        #expect(caret.origin.y == Self.frame.height - 30 - 2 * cell.height)
    }

    // MARK: - Dirty region

    @Test func scrollingRedrawsTheTopInset() throws {
        let view = try makeView()
        view.contentInsets = Self.insets
        let rows = gridSize(view).rows
        if let state = view.captureFrameViewState() {
            _ = view.prepareFrame(viewState: state)
        }
        view.feed(text: String(repeating: "line\r\n", count: rows + 3))
        let state = try #require(view.captureFrameViewState())
        let region = try #require(view.prepareFrame(viewState: state)?.region)
        #expect(region.maxY >= Self.frame.height)
    }

    // MARK: - Pixels (Core Graphics)

    /// A full line with a background color, using erase-in-line so the line
    /// is filled whatever the column count.
    static func coloredLine(_ sgr: Int) -> String {
        "\u{1b}[\(sgr)m\u{1b}[K\u{1b}[0m\r\n"
    }

    /// Feeds `count` lines so the line just above the visible screen is green
    /// (SGR 42) and the first visible line is red (SGR 41).
    static func feedScrollback(_ view: TerminalView) {
        let rows = view.withTerminal { $0.rows }
        let count = rows + 10
        // `count` lines and a final empty one: the screen starts at line
        // `count + 1 - rows`.
        let firstVisible = count + 1 - rows
        var text = ""
        for line in 0..<count {
            if line == firstVisible - 1 {
                text += coloredLine(42)
            } else if line == firstVisible {
                text += coloredLine(41)
            } else {
                text += "\r\n"
            }
        }
        view.feed(text: text)
    }

    /// The view drawn by the Core Graphics renderer over its layer background,
    /// as RGBA rows from the top edge down, one pixel per point.
    private func coreGraphicsPixels(_ view: TerminalView) -> (pixels: [UInt8], width: Int) {
        let width = Int(view.bounds.width)
        let height = Int(view.bounds.height)
        if let state = view.captureFrameViewState() {
            _ = view.prepareFrame(viewState: state)
        }
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            if let background = view.layer?.backgroundColor {
                context.setFillColor(background)
                context.fill(bounds)
            }
            context.draw(rep.cgImage!, in: bounds)
        }
        return (pixels, width)
    }

    private enum Shade { case red, green, background }

    private func shade(_ rgba: ArraySlice<UInt8>) -> Shade {
        let r = Int(rgba[rgba.startIndex]), g = Int(rgba[rgba.startIndex + 1])
        if r > 100 && g < 60 { return .red }
        if g > 100 && r < 60 { return .green }
        return .background
    }

    private func shadeAt(x: CGFloat, yFromTop: CGFloat,
                         in image: (pixels: [UInt8], width: Int)) -> Shade {
        let offset = (Int(yFromTop) * image.width + Int(x)) * 4
        return shade(image.pixels[offset..<(offset + 4)])
    }

    private func makePixelView() throws -> TerminalView {
        let view = try makeView(frame: CGRect(x: 0, y: 0, width: 200, height: 160))
        view.nativeBackgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        view.nativeForegroundColor = .white
        return view
    }

    @Test func coreGraphicsDrawsRowZeroBelowTheTopInset() throws {
        let view = try makePixelView()
        view.contentInsets = NSEdgeInsets(top: 30, left: 10, bottom: 0, right: 0)
        view.feed(text: Self.coloredLine(41))
        let cell = view.cellDimension!
        let image = coreGraphicsPixels(view)
        #expect(shadeAt(x: 50, yFromTop: 30 + cell.height / 2, in: image) == .red)
        // No scrollback: the inset shows the default background.
        #expect(shadeAt(x: 50, yFromTop: 30 - cell.height / 2, in: image) == .background)
        #expect(shadeAt(x: 50, yFromTop: 2, in: image) == .background)
        // The left inset is not part of the row.
        #expect(shadeAt(x: 4, yFromTop: 30 + cell.height / 2, in: image) == .background)
        #expect(shadeAt(x: 14, yFromTop: 30 + cell.height / 2, in: image) == .red)
    }

    @Test func coreGraphicsDrawsScrollbackInsideTheTopInset() throws {
        let view = try makePixelView()
        view.contentInsets = NSEdgeInsets(top: 30, left: 0, bottom: 0, right: 0)
        Self.feedScrollback(view)
        let cell = view.cellDimension!
        let image = coreGraphicsPixels(view)
        #expect(shadeAt(x: 50, yFromTop: 30 + cell.height / 2, in: image) == .red)
        #expect(shadeAt(x: 50, yFromTop: 30 - cell.height / 2, in: image) == .green)
    }

    /// A top inset smaller than a row: the scrollback row just above the
    /// screen shows only its lower part, cut off at the view's top edge.
    @Test func coreGraphicsCutsTheScrollbackAtTheTopEdge() throws {
        let view = try makePixelView()
        let cell = view.cellDimension!
        let top = (cell.height * 0.5).rounded()
        view.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        Self.feedScrollback(view)
        let image = coreGraphicsPixels(view)
        #expect(shadeAt(x: 50, yFromTop: top + 2, in: image) == .red)
        #expect(shadeAt(x: 50, yFromTop: 1, in: image) == .green)
        #expect(shadeAt(x: 50, yFromTop: top - 1, in: image) == .green)
    }

    /// A 37 point top inset is not a whole number of rows: two scrollback
    /// rows show, the upper one cut off at the top edge.
    @Test func coreGraphicsShowsAPartRowAtTheTopEdge() throws {
        let view = try makePixelView()
        let cell = view.cellDimension!
        let top: CGFloat = 37
        #expect(top.truncatingRemainder(dividingBy: cell.height) != 0)
        view.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        // Red on screen row 0, green on the two scrollback rows above it.
        let rows = view.withTerminal { $0.rows }
        let count = rows + 10
        let firstVisible = count + 1 - rows
        var text = ""
        for line in 0..<count {
            if line == firstVisible - 1 || line == firstVisible - 2 {
                text += Self.coloredLine(42)
            } else if line == firstVisible {
                text += Self.coloredLine(41)
            } else {
                text += "\r\n"
            }
        }
        view.feed(text: text)
        let image = coreGraphicsPixels(view)
        #expect(shadeAt(x: 50, yFromTop: top + 2, in: image) == .red)
        #expect(shadeAt(x: 50, yFromTop: top - 2, in: image) == .green)
        if top > 2 * cell.height {
            // A third row would show at the edge; it is plain.
            #expect(shadeAt(x: 50, yFromTop: 1, in: image) == .background)
        } else {
            // The second row up reaches the edge, cut off there.
            #expect(shadeAt(x: 50, yFromTop: 1, in: image) == .green)
        }
    }

    /// Clearing the scrollback (CSI 3J) on its own repaints the top inset.
    @Test func clearingScrollbackRedrawsTheTopInset() throws {
        let view = try makePixelView()
        view.contentInsets = NSEdgeInsets(top: 30, left: 0, bottom: 0, right: 0)
        Self.feedScrollback(view)
        if let state = view.captureFrameViewState() {
            _ = view.prepareFrame(viewState: state)
        }
        view.feed(text: "\u{1b}[3J")
        let state = try #require(view.captureFrameViewState())
        let region = try #require(view.prepareFrame(viewState: state)?.region)
        #expect(region.maxY >= view.bounds.height)
        let cell = view.cellDimension!
        let image = coreGraphicsPixels(view)
        #expect(shadeAt(x: 50, yFromTop: 30 - cell.height / 2, in: image) == .background)
    }

    @Test func coreGraphicsLeavesTheBottomInsetEmpty() throws {
        let view = try makePixelView()
        view.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        let rows = view.withTerminal { $0.rows }
        // Every screen row red, the cursor on the last one.
        view.feed(text: String(repeating: Self.coloredLine(41), count: rows - 1)
                  + "\u{1b}[41m\u{1b}[K\u{1b}[0m")
        let image = coreGraphicsPixels(view)
        let cell = view.cellDimension!
        let lastRowMid = CGFloat(rows) * cell.height - cell.height / 2
        #expect(shadeAt(x: 50, yFromTop: lastRowMid, in: image) == .red)
        #expect(shadeAt(x: 50, yFromTop: view.bounds.height - 2, in: image) == .background)
    }

    @Test func coreGraphicsWithoutInsetsDrawsRowZeroAtTheTop() throws {
        let view = try makePixelView()
        Self.feedScrollback(view)
        let cell = view.cellDimension!
        let image = coreGraphicsPixels(view)
        #expect(shadeAt(x: 50, yFromTop: cell.height / 2, in: image) == .red)
        #expect(shadeAt(x: 50, yFromTop: 1, in: image) == .red)
    }
}

#if canImport(MetalKit)
import Metal
import MetalKit

@MainActor
@Suite("ContentInsetsMetal", .serialized)
struct ContentInsetsMetalTests {
    /// One frame through the Metal renderer, as BGRA rows from the top edge
    /// down, at the view's rendering scale; nil without a usable GPU surface.
    private func metalPixels(_ view: TerminalView)
        -> (pixels: [UInt8], width: Int, scale: CGFloat)?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let scale = view.metalRenderingScaleFactor()
        let target = TerminalMetalLayerView(frame: view.bounds)
        target.renderDevice = device
        target.metalLayer.framebufferOnly = false
        target.renderContentsScale = scale
        target.renderDrawableSize = CGSize(width: view.bounds.width * scale,
                                           height: view.bounds.height * scale)
        guard let renderer = try? MetalTerminalRenderer(target: target) else { return nil }
        renderer.waitForCompletionAfterCommit = true
        renderer.capturesRenderedTexture = true
        guard view.renderSnapshotForMetal(renderer: renderer, target: target),
              let texture = renderer.lastRenderedTexture,
              texture.width > 0, texture.height > 0 else { return nil }
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        bytes.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!, bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                             mipmapLevel: 0)
        }
        return (bytes, texture.width, scale)
    }

    private enum Shade { case red, green, background }

    private func shadeAt(x: CGFloat, yFromTop: CGFloat,
                         in image: (pixels: [UInt8], width: Int, scale: CGFloat)) -> Shade {
        let px = Int(x * image.scale), py = Int(yFromTop * image.scale)
        let offset = (py * image.width + px) * 4
        let b = Int(image.pixels[offset]), g = Int(image.pixels[offset + 1])
        let r = Int(image.pixels[offset + 2])
        if r > 100 && g < 60 && b < 60 { return .red }
        if g > 100 && r < 60 && b < 60 { return .green }
        return .background
    }

    private func makePixelView() throws -> TerminalView {
        let font = try #require(NSFont(name: "Monaco", size: 12))
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 200, height: 160), font: font)
        view.nativeBackgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        view.nativeForegroundColor = .white
        return view
    }

    @Test func metalDrawsRowZeroBelowTheTopInset() throws {
        let view = try makePixelView()
        view.contentInsets = NSEdgeInsets(top: 30, left: 10, bottom: 0, right: 0)
        view.feed(text: ContentInsetsTests.coloredLine(41))
        let cell = view.cellDimension!
        let image = try #require(metalPixels(view))
        #expect(shadeAt(x: 50, yFromTop: 30 + cell.height / 2, in: image) == .red)
        #expect(shadeAt(x: 50, yFromTop: 30 - cell.height / 2, in: image) == .background)
        #expect(shadeAt(x: 4, yFromTop: 30 + cell.height / 2, in: image) == .background)
        #expect(shadeAt(x: 14, yFromTop: 30 + cell.height / 2, in: image) == .red)
    }

    @Test func metalDrawsScrollbackInsideTheTopInset() throws {
        let view = try makePixelView()
        view.contentInsets = NSEdgeInsets(top: 30, left: 0, bottom: 0, right: 0)
        ContentInsetsTests.feedScrollback(view)
        let cell = view.cellDimension!
        let image = try #require(metalPixels(view))
        #expect(shadeAt(x: 50, yFromTop: 30 + cell.height / 2, in: image) == .red)
        #expect(shadeAt(x: 50, yFromTop: 30 - cell.height / 2, in: image) == .green)
    }

    /// A library built from an older copy of the shaders, as an app's own
    /// default library can be, lacks the layout marker and is passed over
    /// for the embedded source, whose `viewport` layout the renderer feeds.
    @Test func aStaleShaderLibraryIsRejected() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let current = try device.makeLibrary(source: swiftTermMetalShaderSource, options: nil)
        #expect(MetalTerminalRenderer.libraryHasRequiredFunctions(current))

        let marker = "kernel void swiftterm_viewport_layout_2() {}"
        #expect(swiftTermMetalShaderSource.contains(marker))
        let staleSource = swiftTermMetalShaderSource.replacingOccurrences(of: marker, with: "")
        let stale = try device.makeLibrary(source: staleSource, options: nil)
        #expect(stale.makeFunction(name: "terminal_text_vertex") != nil)
        #expect(!MetalTerminalRenderer.libraryHasRequiredFunctions(stale))
    }

    /// The embedded copy of the shaders is kept in step with Shaders.metal
    /// by hand; a layout change in one but not the other would be missed.
    @Test func theEmbeddedShaderSourceMatchesShadersMetal() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let shaders = testFile.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftTerm/Apple/Metal/Shaders.metal")
        let file = try String(contentsOf: shaders, encoding: .utf8)
        #expect(file.trimmingCharacters(in: .whitespacesAndNewlines) ==
                swiftTermMetalShaderSource.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func metalWithoutInsetsDrawsRowZeroAtTheTop() throws {
        let view = try makePixelView()
        ContentInsetsTests.feedScrollback(view)
        let cell = view.cellDimension!
        let image = try #require(metalPixels(view))
        #expect(shadeAt(x: 50, yFromTop: cell.height / 2, in: image) == .red)
    }
}
#endif
#endif
