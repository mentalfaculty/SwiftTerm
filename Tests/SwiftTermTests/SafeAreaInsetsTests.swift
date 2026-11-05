//
//  SafeAreaInsetsTests.swift
//  SwiftTermTests
//
//  `automaticallyAdjustsContentInsets`: the Mac view adds its safe area
//  (an ancestor's `additionalSafeAreaInsets`, a full-size content view's
//  title bar) to `contentInsets`, the way NSScrollView does.
//

#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import SwiftTerm

@MainActor
@Suite("SafeAreaInsets", .serialized)
struct SafeAreaInsetsTests {
    static let frame = CGRect(x: 0, y: 0, width: 200, height: 160)

    /// A terminal filling a container whose safe area is `safeTop` deep at
    /// the top, the way a host's bar extends the safe area.
    static func makeHosted(safeTop: CGFloat, adjusts: Bool,
                           contentTop: CGFloat = 0) throws -> (container: NSView, view: TerminalView) {
        let font = try #require(NSFont(name: "Monaco", size: 12))
        let container = NSView(frame: frame)
        container.additionalSafeAreaInsets = NSEdgeInsets(top: safeTop, left: 0, bottom: 0, right: 0)
        let view = TerminalView(frame: frame, font: font)
        view.nativeBackgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        view.nativeForegroundColor = .white
        container.addSubview(view)
        view.contentInsets = NSEdgeInsets(top: contentTop, left: 0, bottom: 0, right: 0)
        view.automaticallyAdjustsContentInsets = adjusts
        container.layoutSubtreeIfNeeded()
        return (container, view)
    }

    private func rows(_ view: TerminalView) -> Int {
        view.withTerminal { $0.rows }
    }

    @Test func theSafeAreaIsIgnoredByDefault() throws {
        let hosted = try Self.makeHosted(safeTop: 40, adjusts: false)
        let view = hosted.view
        #expect(view.automaticallyAdjustsContentInsets == false)
        #expect(view.safeAreaInsets.top == 40)
        #expect(view.frameContentInsets == .zero)
        #expect(rows(view) == Int(Self.frame.height / view.cellDimension.height))
    }

    @Test func theSafeAreaIsAddedToTheContentInsets() throws {
        let hosted = try Self.makeHosted(safeTop: 40, adjusts: true, contentTop: 6)
        let view = hosted.view
        let cell = view.cellDimension!
        #expect(view.frameContentInsets.top == 46)
        #expect(rows(view) == Int((Self.frame.height - 46) / cell.height))
        // contentInsets keeps the user's own margin.
        #expect(view.contentInsets.top == 6)

        view.feed(text: "ab")
        view.updateCursorPosition()
        #expect(view.caretFrame.origin.y == Self.frame.height - 46 - cell.height)
        let hit = view.calculateMouseHit(at: CGPoint(x: 1, y: Self.frame.height - 46 - cell.height / 2))
        #expect(hit.grid.row == view.withTerminal { $0.displayBuffer.yDisp })

        view.automaticallyAdjustsContentInsets = false
        #expect(view.frameContentInsets.top == 6)
        #expect(rows(view) == Int((Self.frame.height - 6) / cell.height))
    }

    @Test func aSafeAreaChangeRelaysTheGridOut() throws {
        let hosted = try Self.makeHosted(safeTop: 0, adjusts: true)
        let view = hosted.view
        let cell = view.cellDimension!
        let before = rows(view)
        #expect(before == Int(Self.frame.height / cell.height))

        hosted.container.additionalSafeAreaInsets = NSEdgeInsets(top: 30, left: 0, bottom: 0, right: 0)
        hosted.container.layoutSubtreeIfNeeded()
        #expect(view.frameContentInsets.top == 30)
        #expect(rows(view) == Int((Self.frame.height - 30) / cell.height))

        hosted.container.additionalSafeAreaInsets = NSEdgeInsetsZero
        hosted.container.layoutSubtreeIfNeeded()
        #expect(view.frameContentInsets == .zero)
        #expect(rows(view) == before)
    }

    /// A titled window with a full-size content view puts its title bar in
    /// the safe area of a view that fills the content view. The window is
    /// never ordered in, and it is placed off every screen.
    @Test func aFullSizeContentViewsTitleBarIsInTheSafeArea() throws {
        let font = try #require(NSFont(name: "Monaco", size: 12))
        let window = NSWindow(contentRect: CGRect(x: -6000, y: -6000, width: 300, height: 200),
                              styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        let content = try #require(window.contentView)
        let view = TerminalView(frame: content.bounds, font: font)
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        view.automaticallyAdjustsContentInsets = true
        content.layoutSubtreeIfNeeded()
        let titleBar = view.safeAreaInsets.top
        #expect(titleBar > 0)
        #expect(view.frameContentInsets.top == (titleBar * view.backingScaleFactor()).rounded()
                / view.backingScaleFactor())
        #expect(rows(view) == Int((content.bounds.height - view.frameContentInsets.top)
                                  / view.cellDimension.height))
        window.close()
    }

    /// Showing and hiding a toolbar changes the safe area of a view under a
    /// full-size content view; the grid follows, and leaving the window does
    /// not resize it.
    @Test func aToolbarToggleRelaysTheGridOut() throws {
        let font = try #require(NSFont(name: "Monaco", size: 12))
        let window = NSWindow(contentRect: CGRect(x: -6000, y: -6000, width: 300, height: 300),
                              styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let toolbar = NSToolbar(identifier: "SafeAreaInsetsTests")
        window.toolbar = toolbar
        let content = try #require(window.contentView)
        let view = TerminalView(frame: content.bounds, font: font)
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        view.automaticallyAdjustsContentInsets = true
        content.layoutSubtreeIfNeeded()
        let withToolbar = view.frameContentInsets.top
        let rowsWithToolbar = rows(view)

        toolbar.isVisible = false
        window.layoutIfNeeded()
        content.layoutSubtreeIfNeeded()
        let without = view.frameContentInsets.top
        #expect(without < withToolbar, "with \(withToolbar) without \(without) safe \(view.safeAreaInsets.top)")
        #expect(rows(view) >= rowsWithToolbar)
        #expect(rows(view) == Int((content.bounds.height - without) / view.cellDimension.height))

        let beforeRemoval = rows(view)
        view.removeFromSuperview()
        #expect(rows(view) == beforeRemoval)
        window.close()
    }

    // MARK: - Pixels

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

    /// Red and green channels at a point, `yFromTop` points below the top.
    private func redGreen(_ image: (pixels: [UInt8], width: Int), y yFromTop: CGFloat) -> (Int, Int) {
        let offset = (Int(yFromTop) * image.width + 50) * 4
        return (Int(image.pixels[offset]), Int(image.pixels[offset + 1]))
    }

    @Test func coreGraphicsDrawsRowZeroBelowTheSafeAreaAndScrollbackInIt() throws {
        let hosted = try Self.makeHosted(safeTop: 24, adjusts: true, contentTop: 6)
        let view = hosted.view
        ContentInsetsTests.feedScrollback(view)
        let cell = view.cellDimension!
        let image = coreGraphicsPixels(view)
        let rowZero = redGreen(image, y: 30 + cell.height / 2)
        #expect(rowZero.0 > 100 && rowZero.1 < 60, "row 0 \(rowZero)")
        let scrollback = redGreen(image, y: 30 - cell.height / 2)
        #expect(scrollback.1 > 100 && scrollback.0 < 60, "scrollback \(scrollback)")
    }

    /// The fade covers the whole combined top inset, safe area included.
    @Test func coreGraphicsFadesTheCombinedTopInset() throws {
        let hosted = try Self.makeHosted(safeTop: 26, adjusts: true, contentTop: 6)
        let view = hosted.view
        view.topInsetContentAlpha = 0.5
        view.topInsetFadeLength = 6
        #expect(view.frameTopInsetFade.length == 6)
        ContentInsetsTests.feedRed(view)
        let image = coreGraphicsPixels(view)
        let full = Double(redGreen(image, y: 34).0)
        let top = Double(redGreen(image, y: 2).0)
        let band = Double(redGreen(image, y: 29).0)
        #expect(full > 150)
        #expect(abs(top - full * 0.5) <= 4, "top \(top) vs \(full)")
        #expect(band > top + 10 && band < full - 10, "band \(band)")
    }

    @Test func flagOffDrawsExactlyAsWithoutASafeArea() throws {
        let hosted = try Self.makeHosted(safeTop: 40, adjusts: false, contentTop: 20)
        let font = try #require(NSFont(name: "Monaco", size: 12))
        let plain = TerminalView(frame: Self.frame, font: font)
        plain.nativeBackgroundColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        plain.nativeForegroundColor = .white
        plain.contentInsets = NSEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        ContentInsetsTests.feedScrollback(hosted.view)
        ContentInsetsTests.feedScrollback(plain)
        #expect(coreGraphicsPixels(hosted.view).pixels == coreGraphicsPixels(plain).pixels)
    }
}

#if canImport(MetalKit)
import Metal
import MetalKit

@MainActor
@Suite("SafeAreaInsetsMetal", .serialized)
struct SafeAreaInsetsMetalTests {
    private func metalPixels(_ view: TerminalView) -> (pixels: [UInt8], width: Int, scale: CGFloat)? {
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

    /// BGRA: red and green at a point `yFromTop` points below the top.
    private func redGreen(_ image: (pixels: [UInt8], width: Int, scale: CGFloat),
                          y yFromTop: CGFloat) -> (Int, Int) {
        let offset = (Int(yFromTop * image.scale) * image.width + Int(50 * image.scale)) * 4
        return (Int(image.pixels[offset + 2]), Int(image.pixels[offset + 1]))
    }

    @Test func metalDrawsRowZeroBelowTheSafeAreaAndScrollbackInIt() throws {
        let hosted = try SafeAreaInsetsTests.makeHosted(safeTop: 24, adjusts: true, contentTop: 6)
        let view = hosted.view
        ContentInsetsTests.feedScrollback(view)
        let cell = view.cellDimension!
        let image = try #require(metalPixels(view))
        let rowZero = redGreen(image, y: 30 + cell.height / 2)
        #expect(rowZero.0 > 100 && rowZero.1 < 60, "row 0 \(rowZero)")
        let scrollback = redGreen(image, y: 30 - cell.height / 2)
        #expect(scrollback.1 > 100 && scrollback.0 < 60, "scrollback \(scrollback)")
    }

    @Test func metalFadesTheCombinedTopInset() throws {
        let hosted = try SafeAreaInsetsTests.makeHosted(safeTop: 26, adjusts: true, contentTop: 6)
        let view = hosted.view
        view.topInsetContentAlpha = 0.5
        view.topInsetFadeLength = 6
        ContentInsetsTests.feedRed(view)
        let image = try #require(metalPixels(view))
        let full = Double(redGreen(image, y: 34).0)
        let top = Double(redGreen(image, y: 2).0)
        #expect(full > 150)
        #expect(abs(top - full * 0.5) <= 4, "top \(top) vs \(full)")
    }
}
#endif
#endif
