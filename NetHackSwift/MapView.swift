import AppKit
import NetHackBridge
import SwiftUI

/// Renders the complete NetHack map at its natural tile size.
/// Scroll-viewport management lives in MapContainerView.
struct MapView: View {
    @Environment(GameState.self) private var gameState

    var body: some View {
        let tileSet   = TileSet.shared
        let tileSize  = tileSet?.displaySize ?? CGSize(width: 32, height: 32)
        let _         = gameState.mapVersion
        let glyphs    = gameState.mapGlyphs
        let bkGlyphs  = gameState.mapBkGlyphs
        let cursor    = gameState.mapCursor
        let hpPercent = gameState.maxHp > 0 ? gameState.hp * 100 / gameState.maxHp : 100
        let useText   = gameState.mapUsesAsciiDisplay

        Canvas { context, size in
            if useText {
                for row in 0..<GameState.mapRows {
                    for col in 0..<GameState.mapCols {
                        let idx = row * GameState.mapCols + col
                        guard idx < glyphs.count else { continue }
                        let glyph = glyphs[idx]
                        guard glyph.glyph >= 0 else { continue }
                        let dest = CGRect(x: CGFloat(col) * tileSize.width,
                                         y: CGFloat(row) * tileSize.height,
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
                context.withCGContext { cgCtx in
                    // SwiftUI Canvas provides a CGContext with y=0 at the top (y
                    // increases downward). CGContext.draw(_:in:) maps CGImage row 0
                    // to the bottom of the dest rect in the context's coordinate
                    // space, which in a top-down context is the visual top — so
                    // every tile appears upside-down without correction.
                    // Flip y once for the whole batch; adjust the row->y formula below.
                    cgCtx.translateBy(x: 0, y: size.height)
                    cgCtx.scaleBy(x: 1, y: -1)

                    for row in 0..<GameState.mapRows {
                        for col in 0..<GameState.mapCols {
                            let idx = row * GameState.mapCols + col
                            guard idx < glyphs.count else { continue }
                            let fg = glyphs[idx]
                            let bk = bkGlyphs[idx]
                            guard fg.glyph >= 0 else { continue }
                            // After the flip the context has y=0 at the bottom.
                            // Invert the row index so row 0 lands at the visual top.
                            let dest = CGRect(
                                x: CGFloat(col) * tileSize.width,
                                y: CGFloat(GameState.mapRows - 1 - row) * tileSize.height,
                                width: tileSize.width, height: tileSize.height
                            )
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
            let cursorRect = CGRect(x: CGFloat(cursor.x) * tileSize.width,
                                    y: CGFloat(cursor.y) * tileSize.height,
                                    width: tileSize.width, height: tileSize.height)
            let cursorColor: Color = hpPercent > 75
                ? .green.opacity(0.9)
                : hpPercent > 50
                    ? Color(red: 0.8, green: 0.8, blue: 0).opacity(0.9)
                    : Color(red: 0.8, green: 0,   blue: 0).opacity(0.9)
            context.stroke(Path(cursorRect), with: .color(cursorColor))
        }
        .background(.black)
        .frame(
            width:  CGFloat(GameState.mapCols) * tileSize.width,
            height: CGFloat(GameState.mapRows) * tileSize.height
        )
    }
}

#Preview {
    MapView()
        .environment(GameState())
        .frame(width: 637, height: 216)
}
