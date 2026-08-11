import AppKit
import NetHackBridge
import SwiftUI

struct MapView: View {
    @Environment(GameState.self) private var gameState
    @Environment(NetHackController.self) private var controller

    var body: some View {
        // Capture all game-state reads here so @Observable tracks them and
        // re-evaluates body (and therefore re-draws the Canvas) on changes.
        let tileSet   = TileSet.shared
        let tileW     = tileSet?.tileSize.width  ?? 16
        let tileH     = tileSet?.tileSize.height ?? 16
        let _         = gameState.mapVersion   // observed; triggers re-render each display
        let glyphs    = gameState.mapGlyphs
        let bkGlyphs  = gameState.mapBkGlyphs
        let cursorX   = gameState.mapCursorX
        let cursorY   = gameState.mapCursorY
        let hpPercent = gameState.maxHp > 0 ? gameState.hp * 100 / gameState.maxHp : 100
        let useText   = gameState.mapUsesTextDisplay
        let mapWidth  = CGFloat(GameState.mapCols) * tileW
        let mapHeight = CGFloat(GameState.mapRows) * tileH

        ScrollView([.horizontal, .vertical]) {
            Canvas { context, _ in
                for row in 0..<GameState.mapRows {
                    for col in 0..<GameState.mapCols {
                        let idx = row * GameState.mapCols + col
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
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let col = Int32(value.location.x / tileW)
                        let row = Int32(value.location.y / tileH)
                        controller.sendMouseClick(x: col, y: row, mod: 0)
                    }
            )
        }
        .background(Color(white: 0.21)) // charcoal gray for excess space
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MapView()
        .environment(GameState())
        .environment(NetHackController())
        .frame(width: 637, height: 216)
}
