import AppKit
import NetHackBridge
import SwiftUI

struct MapView: View {
    @Environment(GameState.self) private var gameState
    @Environment(NetHackController.self) private var controller

    // Stored scroll position for manual scrolling. When needsClipSync is true
    // the view centers on the game's clipAround tile instead.
    @State private var scrollX: CGFloat = 0
    @State private var scrollY: CGFloat = 0
    @State private var needsClipSync = true

    var body: some View {
        let tileSet   = TileSet.shared
        let tileSize  = tileSet?.tileSize ?? CGSize(width: 16, height: 16)
        let _         = gameState.mapVersion
        let glyphs    = gameState.mapGlyphs
        let bkGlyphs  = gameState.mapBkGlyphs
        let cursor      = gameState.mapCursor
        let clip        = gameState.clipAround
        let clipVersion = gameState.clipAroundVersion
        let hpPercent = gameState.maxHp > 0 ? gameState.hp * 100 / gameState.maxHp : 100
        let useText   = gameState.mapUsesTextDisplay

        GeometryReader { geo in
            let mapW = CGFloat(GameState.mapCols) * tileSize.width
            let mapH = CGFloat(GameState.mapRows) * tileSize.height

            // Game's desired origin: center clipAround tile, clamped to map bounds.
            let cx = CGFloat(clip.x) * tileSize.width  + tileSize.width  / 2
            let cy = CGFloat(clip.y) * tileSize.height + tileSize.height / 2
            let gameOriginX = max(0, min(cx - geo.size.width  / 2, mapW - geo.size.width))
            let gameOriginY = max(0, min(cy - geo.size.height / 2, mapH - geo.size.height))

            // Active origin: game-driven normally, user-driven during manual scroll.
            let maxScrollX = max(0, mapW - geo.size.width)
            let maxScrollY = max(0, mapH - geo.size.height)
            let originX = needsClipSync ? gameOriginX : max(0, min(scrollX, maxScrollX))
            let originY = needsClipSync ? gameOriginY : max(0, min(scrollY, maxScrollY))

            Canvas { context, size in
                // Only draw tiles that intersect the visible area.
                let startCol = max(0, Int(originX / tileSize.width))
                let startRow = max(0, Int(originY / tileSize.height))
                let endCol   = min(GameState.mapCols,
                                   Int(ceil((originX + size.width)  / tileSize.width)))
                let endRow   = min(GameState.mapRows,
                                   Int(ceil((originY + size.height) / tileSize.height)))

                if useText {
                    for row in startRow..<endRow {
                        for col in startCol..<endCol {
                            let idx = row * GameState.mapCols + col
                            guard idx < glyphs.count else { continue }
                            let glyph = glyphs[idx]
                            guard glyph.glyph >= 0 else { continue }
                            let dest = CGRect(x: CGFloat(col) * tileSize.width  - originX,
                                             y: CGFloat(row) * tileSize.height - originY,
                                             width: tileSize.width, height: tileSize.height)
                            if let scalar = Unicode.Scalar(UInt32(glyph.ttychar)),
                               scalar.value > 0 {
                                context.draw(
                                    Text(String(scalar))
                                        .font(.system(size: tileSize.height * 0.75).monospaced())
                                        .foregroundStyle(.white),
                                    in: dest)
                            }
                        }
                    }
                } else if let ts = tileSet {
                    // Tile mode: drop to CGContext for direct bitblt.
                    context.withCGContext { cgCtx in
                        for row in startRow..<endRow {
                            for col in startCol..<endCol {
                                let idx = row * GameState.mapCols + col
                                guard idx < glyphs.count else { continue }
                                let fg = glyphs[idx]
                                let bk = bkGlyphs[idx]
                                guard fg.glyph >= 0 else { continue }
                                let dest = CGRect(x: CGFloat(col) * tileSize.width  - originX,
                                                 y: CGFloat(row) * tileSize.height - originY,
                                                 width: tileSize.width, height: tileSize.height)
                                if let bkCG = ts.cgImage(forGlyph: bk) {
                                    cgCtx.draw(bkCG, in: dest)
                                }
                                if fg.glyph != bk.glyph, let fgCG = ts.cgImage(forGlyph: fg) {
                                    cgCtx.draw(fgCG, in: dest)
                                }
                            }
                        }
                    }
                }

                // Cursor rectangle, color-coded by remaining HP.
                let cursorRect = CGRect(x: CGFloat(cursor.x) * tileSize.width  - originX,
                                        y: CGFloat(cursor.y) * tileSize.height - originY,
                                        width: tileSize.width, height: tileSize.height)
                let cursorColor: Color = hpPercent > 75
                    ? .green.opacity(0.9)
                    : hpPercent > 50
                        ? Color(red: 0.8, green: 0.8, blue: 0).opacity(0.9)
                        : Color(red: 0.8, green: 0,   blue: 0).opacity(0.9)
                context.stroke(Path(cursorRect), with: .color(cursorColor))
            }
            .background(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Vertical scroll indicator. Uses a full-height VStack as the gesture
            // target so the hit area matches the entire track, not just the thumb.
            .overlay(alignment: .topTrailing) {
                if mapH > geo.size.height {
                    let track  = geo.size.height
                    let thumbH = max(20.0, track * geo.size.height / mapH)
                    let pos    = (track - thumbH) * originY / (mapH - geo.size.height)
                    VStack(spacing: 0) {
                        Color.clear.frame(height: pos)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 8, height: thumbH)
                        Spacer()
                    }
                    .frame(width: 12, height: track)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                needsClipSync = false
                                let p = max(0, min(value.location.y - thumbH / 2,
                                                   track - thumbH))
                                scrollY = p / max(1, track - thumbH) * maxScrollY
                            }
                    )
                    .padding(.trailing, 2)
                }
            }
            // Horizontal scroll indicator.
            .overlay(alignment: .bottomLeading) {
                if mapW > geo.size.width {
                    let track  = geo.size.width
                    let thumbW = max(20.0, track * geo.size.width / mapW)
                    let pos    = (track - thumbW) * originX / (mapW - geo.size.width)
                    HStack(spacing: 0) {
                        Color.clear.frame(width: pos)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.4))
                            .frame(width: thumbW, height: 8)
                        Spacer()
                    }
                    .frame(width: track, height: 12)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                needsClipSync = false
                                let p = max(0, min(value.location.x - thumbW / 2,
                                                   track - thumbW))
                                scrollX = p / max(1, track - thumbW) * maxScrollX
                            }
                    )
                    .padding(.bottom, 2)
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let col = Int32((value.location.x + originX) / tileSize.width)
                        let row = Int32((value.location.y + originY) / tileSize.height)
                        let button: NHMouseButton =
                            NSApp.currentEvent?.type == .rightMouseUp ? .right : .left
                        controller.sendMouseClick(x: col, y: row, mod: button.rawValue)
                    }
            )
            // When the game scrolls (clipAround changes), hand control back to the game.
            .onChange(of: clipVersion) { _, _ in
                needsClipSync = true
            }
        }
        .background(.black)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MapView()
        .environment(GameState())
        .environment(NetHackController())
        .frame(width: 637, height: 216)
}
