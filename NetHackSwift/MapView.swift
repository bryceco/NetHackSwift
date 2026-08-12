import AppKit
import NetHackBridge
import SwiftUI

struct MapView: View {
    @Environment(GameState.self) private var gameState
    @Environment(NetHackController.self) private var controller

    var body: some View {
        // Capture all game-state reads here so @Observable tracks them and
        // re-evaluates body (and therefore re-draws the Canvas) on changes.
        let tileSet      = TileSet.shared
        let tileW        = tileSet?.tileSize.width  ?? 16
        let tileH        = tileSet?.tileSize.height ?? 16
        let _            = gameState.mapVersion   // observed; triggers re-render each display
        let glyphs       = gameState.mapGlyphs
        let bkGlyphs     = gameState.mapBkGlyphs
        let (cursorX, cursorY) = gameState.mapCursor
        let (clipX, clipY)     = gameState.clipAround
        let clipVersion  = gameState.clipAroundVersion
        let hpPercent    = gameState.maxHp > 0 ? gameState.hp * 100 / gameState.maxHp : 100
        let useText      = gameState.mapUsesTextDisplay
        let mapWidth     = CGFloat(GameState.mapCols) * tileW
        let mapHeight    = CGFloat(GameState.mapRows) * tileH

        ScrollView([.horizontal, .vertical]) {
            Canvas { context, _ in
                for row in 0..<GameState.mapRows {
                    for col in 0..<GameState.mapCols {
                        let idx = row * GameState.mapCols + col
                        guard idx < glyphs.count else { continue }
                        let glyph   = glyphs[idx]
                        let bkGlyph = bkGlyphs[idx]
                        guard glyph.glyph >= 0 else { continue }

                        let dest = CGRect(x: CGFloat(col) * tileW,
                                         y: CGFloat(row) * tileH,
                                         width: tileW, height: tileH)

                        if useText {
                            if let scalar = Unicode.Scalar(UInt32(glyph.ttychar)), scalar.value > 0 {
                                let ch = Text(String(scalar))
                                    .font(.system(size: tileH * 0.75).monospaced())
                                    .foregroundStyle(.white)
                                context.draw(ch, in: dest)
                            }
                        } else if let tileSet {
                            // Draw background tile first, then foreground on top.
                            if bkGlyph.glyph >= 0,
                               let bkTile = tileSet.image(forGlyph: bkGlyph)
                            {
                                context.draw(Image(nsImage: bkTile), in: dest)
                            }
                            if let tile = tileSet.image(forGlyph: glyph) {
                                context.draw(Image(nsImage: tile), in: dest)
                            }
                        }
                    }
                }

                // Cursor rectangle, color-coded by remaining HP.
                let cursorRect = CGRect(x: CGFloat(cursorX) * tileW,
                                        y: CGFloat(cursorY) * tileH,
                                        width: tileW, height: tileH)
                let cursorColor: Color = hpPercent > 75
                    ? .green.opacity(0.9)
                    : hpPercent > 50
                        ? Color(red: 0.8, green: 0.8, blue: 0).opacity(0.9)
                        : Color(red: 0.8, green: 0,   blue: 0).opacity(0.9)
                context.stroke(Path(cursorRect), with: .color(cursorColor))
            }
            .background(.black)
            .frame(width: mapWidth, height: mapHeight)
            .overlay(
                MouseClickOverlay { location, button in
                    let col = Int32(location.x / tileW)
                    let row = Int32(location.y / tileH)
                    controller.sendMouseClick(x: col, y: row, mod: button.rawValue)
                }
            )
            // Invisible view that triggers NSScrollView scrolling when clipAroundVersion changes.
            .background(
                ClipAroundScroller(
                    version: clipVersion,
                    tileX: clipX, tileY: clipY,
                    tileW: tileW, tileH: tileH
                )
            )
        }
        .background(Color(white: 0.21)) // charcoal gray for excess space
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Transparent overlay that captures left- and right-click events and reports
/// the click location in its own coordinate space.
private struct MouseClickOverlay: NSViewRepresentable {
    let onClick: (CGPoint, NHMouseButton) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ClickView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ClickView)?.onClick = onClick
    }

    private class ClickView: NSView {
        var onClick: ((CGPoint, NHMouseButton) -> Void)?

        private func flipped(_ event: NSEvent) -> CGPoint {
            let loc = convert(event.locationInWindow, from: nil)
            // Flip from AppKit (origin bottom-left) to SwiftUI (origin top-left).
            return CGPoint(x: loc.x, y: bounds.height - loc.y)
        }

        override func mouseUp(with event: NSEvent) {
            onClick?(flipped(event), .left)
        }

        override func rightMouseUp(with event: NSEvent) {
            onClick?(flipped(event), .right)
        }
    }
}

/// Invisible NSViewRepresentable that scrolls the enclosing NSScrollView so that
/// the tile at (tileX, tileY) is visible, centered if possible. It walks up the
/// view hierarchy to find the NSScrollView, avoiding SwiftUI ScrollViewProxy
/// reliability issues on macOS.
private struct ClipAroundScroller: NSViewRepresentable {
    let version: Int
    let tileX: Int32
    let tileY: Int32
    let tileW: CGFloat
    let tileH: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = ScrollTriggerView()
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let trigger = nsView as? ScrollTriggerView,
              trigger.lastVersion != version else { return }
        trigger.lastVersion = version

        // Walk up the hierarchy to find the NSScrollView.
        var current: NSView? = nsView
        while let v = current {
            if let scrollView = v as? NSScrollView {
                let rect = CGRect(
                    x: CGFloat(tileX) * tileW,
                    y: CGFloat(tileY) * tileH,
                    width: tileW,
                    height: tileH
                )
                // Center the target rect in the visible area.
                let visible = scrollView.contentView.bounds.size
                let centeredOrigin = CGPoint(
                    x: rect.midX - visible.width  / 2,
                    y: rect.midY - visible.height / 2
                )
                let contentSize = scrollView.documentView?.bounds.size ?? .zero
                let clampedX = max(0, min(centeredOrigin.x, contentSize.width  - visible.width))
                let clampedY = max(0, min(centeredOrigin.y, contentSize.height - visible.height))
                scrollView.contentView.scroll(to: CGPoint(x: clampedX, y: clampedY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                return
            }
            current = v.superview
        }
    }

    private class ScrollTriggerView: NSView {
        var lastVersion: Int = -1
    }
}

#Preview {
    MapView()
        .environment(GameState())
        .environment(NetHackController())
        .frame(width: 637, height: 216)
}
