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

    // MARK: - Top inset fade

    /// Every line, scrollback and screen, carries the same white text.
    static let textLine = String(repeating: "M", count: 20)

    static func feedText(_ view: TerminalView) {
        let rows = view.withTerminal { $0.rows }
        view.feed(text: String(repeating: textLine + "\r\n", count: rows + 10))
    }

    /// The summed ink of one channel over the pixel rows between `from` and
    /// `to` points below the top edge.
    static func ink(_ pixels: [UInt8], width: Int, scale: CGFloat, channel: Int,
                    from: CGFloat, to: CGFloat) -> Int {
        var total = 0
        let first = max(0, Int((from * scale).rounded()))
        let last = min(pixels.count / (width * 4), Int((to * scale).rounded()))
        for y in first..<last {
            for x in 0..<width {
                total += Int(pixels[(y * width + x) * 4 + channel])
            }
        }
        return total
    }

    static let fadeTop: CGFloat = 32

    static func fadedView(alpha: CGFloat, fade: CGFloat) throws -> TerminalView {
        let font = try #require(NSFont(name: "Monaco", size: 12))
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 200, height: 160), font: font)
        view.nativeBackgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        view.nativeForegroundColor = .white
        view.contentInsets = NSEdgeInsets(top: fadeTop, left: 0, bottom: 0, right: 0)
        view.topInsetContentAlpha = alpha
        view.topInsetFadeLength = fade
        return view
    }

    @Test func fadeDefaultsDrawExactlyAsBefore() throws {
        let plain = try Self.fadedView(alpha: 1, fade: 0)
        let unused = try Self.fadedView(alpha: 1, fade: 6)
        #expect(plain.topInsetContentAlpha == 1 && plain.topInsetFadeLength == 0)
        #expect(plain.frameTopInsetFade.isIdentity)
        let fresh = try makePixelView()
        fresh.contentInsets = NSEdgeInsets(top: Self.fadeTop, left: 0, bottom: 0, right: 0)
        for view in [plain, unused, fresh] {
            Self.feedText(view)
        }
        let reference = coreGraphicsPixels(fresh).pixels
        #expect(coreGraphicsPixels(plain).pixels == reference)
        #expect(coreGraphicsPixels(unused).pixels == reference)
    }

    /// Red cell backgrounds on every line: one pixel row at a time, the
    /// opacity follows the ramp (pixel centers, so 2.5 points above row 0 is
    /// 1 - 0.5 * 2.5 / 6).
    static func feedRed(_ view: TerminalView) {
        let rows = view.withTerminal { $0.rows }
        view.feed(text: String(repeating: coloredLine(41), count: rows + 10))
    }

    static func expectedFadeRed(full: Double, above: CGFloat) -> Double {
        full * Double(FrameTopInsetFade(alpha: 0.5, length: 6).opacity(above: above))
    }

    @Test func coreGraphicsFadeRampsPerPixelRow() throws {
        let view = try Self.fadedView(alpha: 0.5, fade: 6)
        Self.feedRed(view)
        let image = coreGraphicsPixels(view)
        func red(_ y: Int) -> Double { Double(image.pixels[(y * image.width + 50) * 4]) }
        let full = red(Int(Self.fadeTop) + 2)
        #expect(full > 150)
        for y in [2, 20, 26, 28, 29, 31] {
            let above = Self.fadeTop - (CGFloat(y) + 0.5)
            let expected = Self.expectedFadeRed(full: full, above: above)
            #expect(abs(red(y) - expected) <= 4, "y \(y): \(red(y)) vs \(expected)")
        }
    }

    /// Setting the alpha after a frame was drawn shows in the next draw,
    /// with no new output and no frame prepared in between.
    @Test func coreGraphicsShowsAnAlphaSetAfterADraw() throws {
        let view = try Self.fadedView(alpha: 1, fade: 0)
        Self.feedRed(view)
        let before = coreGraphicsPixels(view)
        view.topInsetContentAlpha = 0.5
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        var pixels = [UInt8](repeating: 0, count: before.width * Int(view.bounds.height) * 4)
        pixels.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: before.width,
                                    height: Int(view.bounds.height), bitsPerComponent: 8,
                                    bytesPerRow: before.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let bounds = CGRect(origin: .zero, size: view.bounds.size)
            if let background = view.layer?.backgroundColor {
                context.setFillColor(background)
                context.fill(bounds)
            }
            context.draw(rep.cgImage!, in: bounds)
        }
        let full = Double(before.pixels[(2 * before.width + 50) * 4])
        let faded = Double(pixels[(2 * before.width + 50) * 4])
        #expect(full > 150)
        #expect(abs(faded - full * 0.5) <= 4, "\(faded) vs \(full)")
    }

    /// With translucent cell backgrounds a faded cell mixes back towards the
    /// default background, as it does over an opaque one; it does not punch
    /// a hole through it.
    @Test func coreGraphicsFadesTranslucentCellBackgroundsTowardsTheDefault() throws {
        let view = try Self.fadedView(alpha: 0.5, fade: 6)
        view.backgroundOpacity = 0.4
        view.translucentCellBackgrounds = true
        Self.feedRed(view)
        let image = coreGraphicsPixels(view)
        let inset = Array(image.pixels[((2 * image.width) + 50) * 4..<((2 * image.width) + 50) * 4 + 4])
        // Red at 0.4 replaced the default black at 0.4: half of it is left,
        // over the same 0.4 alpha.
        #expect(abs(Int(inset[3]) - 102) <= 2, "alpha \(inset)")
    }

    @Test func fadeLengthIsLimitedToTheInset() throws {
        let view = try Self.fadedView(alpha: 0.5, fade: 100)
        #expect(view.frameTopInsetFade.length == Self.fadeTop)
        #expect(view.frameTopInsetFade.opacity(above: Self.fadeTop) == 0.5)
        view.topInsetContentAlpha = 3
        #expect(view.frameTopInsetFade.alpha == 1)
    }

    /// Alpha 0.5 with a 6 point fade on a 32 point inset: the row whole in
    /// the inset's upper part shows at half its ink, the row in the fade band
    /// at more, and row 0 at full.
    @Test func coreGraphicsFadesTheTopInset() throws {
        let view = try Self.fadedView(alpha: 0.5, fade: 6)
        Self.feedText(view)
        let reference = try Self.fadedView(alpha: 1, fade: 0)
        Self.feedText(reference)
        let cell = view.cellDimension!
        let top = Self.fadeTop
        let faded = coreGraphicsPixels(view)
        let full = coreGraphicsPixels(reference)
        func ink(_ image: (pixels: [UInt8], width: Int), _ from: CGFloat, _ to: CGFloat) -> Double {
            Double(Self.ink(image.pixels, width: image.width, scale: 1, channel: 0,
                            from: from, to: to))
        }
        // Row 0 is untouched, pixel for pixel.
        let rowZero = (top, top + cell.height)
        #expect(ink(faded, rowZero.0, rowZero.1) == ink(full, rowZero.0, rowZero.1))
        #expect(ink(full, rowZero.0, rowZero.1) > 0)
        // Above the fade band: half.
        let upper = ink(faded, 0, top - 6) / ink(full, 0, top - 6)
        #expect(abs(upper - 0.5) < 0.05, "upper ratio \(upper)")
        // In the band: between half and full.
        let band = ink(faded, top - 6, top) / max(1, ink(full, top - 6, top))
        #expect(band > upper + 0.02 && band < 1, "band ratio \(band)")
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

    @Test func metalWithoutInsetsDrawsRowZeroAtTheTop() throws {
        let view = try makePixelView()
        ContentInsetsTests.feedScrollback(view)
        let cell = view.cellDimension!
        let image = try #require(metalPixels(view))
        #expect(shadeAt(x: 50, yFromTop: cell.height / 2, in: image) == .red)
    }

    @Test func metalFadesTheTopInset() throws {
        let view = try ContentInsetsTests.fadedView(alpha: 0.5, fade: 6)
        ContentInsetsTests.feedText(view)
        let reference = try ContentInsetsTests.fadedView(alpha: 1, fade: 0)
        ContentInsetsTests.feedText(reference)
        let cell = view.cellDimension!
        let top = ContentInsetsTests.fadeTop
        let faded = try #require(metalPixels(view))
        let full = try #require(metalPixels(reference))
        func ink(_ image: (pixels: [UInt8], width: Int, scale: CGFloat),
                 _ from: CGFloat, _ to: CGFloat) -> Double {
            Double(ContentInsetsTests.ink(image.pixels, width: image.width, scale: image.scale,
                                          channel: 2, from: from, to: to))
        }
        #expect(ink(faded, top, top + cell.height) == ink(full, top, top + cell.height))
        #expect(ink(full, top, top + cell.height) > 0)
        let upper = ink(faded, 0, top - 6) / ink(full, 0, top - 6)
        #expect(abs(upper - 0.5) < 0.05, "upper ratio \(upper)")
        let band = ink(faded, top - 6, top) / max(1, ink(full, top - 6, top))
        #expect(band > upper + 0.02 && band < 1, "band ratio \(band)")
    }

    @Test func metalFadeRampsPerPixelRow() throws {
        let view = try ContentInsetsTests.fadedView(alpha: 0.5, fade: 6)
        ContentInsetsTests.feedRed(view)
        let image = try #require(metalPixels(view))
        let scale = image.scale
        func red(_ y: CGFloat) -> Double {
            Double(image.pixels[(Int(y * scale) * image.width + Int(50 * scale)) * 4 + 2])
        }
        let full = red(ContentInsetsTests.fadeTop + 2)
        #expect(full > 150)
        for y: CGFloat in [2, 20, 26, 28, 29, 31] {
            // The pixel row starting at y; its center is half a pixel lower.
            let above = ContentInsetsTests.fadeTop - (y + 0.5 / scale)
            let expected = ContentInsetsTests.expectedFadeRed(full: full, above: above)
            #expect(abs(red(y) - expected) <= 4, "y \(y): \(red(y)) vs \(expected)")
        }
    }

    @Test func metalFadesTranslucentCellBackgroundsTowardsTheDefault() throws {
        let view = try ContentInsetsTests.fadedView(alpha: 0.5, fade: 6)
        view.backgroundOpacity = 0.4
        view.translucentCellBackgrounds = true
        ContentInsetsTests.feedRed(view)
        let image = try #require(metalPixels(view))
        let offset = (Int(2 * image.scale) * image.width + Int(50 * image.scale)) * 4
        let bgra = Array(image.pixels[offset..<(offset + 4)])
        // Alpha stays the default background's 0.4; red is half of the
        // cell's premultiplied 0.4.
        #expect(abs(Int(bgra[3]) - 102) <= 2, "\(bgra)")
        let fullOffset = (Int((ContentInsetsTests.fadeTop + 2) * image.scale) * image.width
                          + Int(50 * image.scale)) * 4
        let fullRed = Int(image.pixels[fullOffset + 2])
        #expect(abs(Int(bgra[2]) - fullRed / 2) <= 2, "\(bgra) vs \(fullRed)")
    }

    @Test func metalFadeDefaultsDrawExactlyAsBefore() throws {
        let plain = try ContentInsetsTests.fadedView(alpha: 1, fade: 0)
        let unused = try ContentInsetsTests.fadedView(alpha: 1, fade: 6)
        ContentInsetsTests.feedText(plain)
        ContentInsetsTests.feedText(unused)
        let a = try #require(metalPixels(plain))
        let b = try #require(metalPixels(unused))
        #expect(a.pixels == b.pixels)
    }

}
#endif
#endif
