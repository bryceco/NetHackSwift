import AppKit
import NetHackBridge
import SwiftUI

/// Provides a scrollable viewport over MapView with custom scroll indicators
/// and clipAround-based auto-scrolling.
struct MapContainerView: View {
    @Environment(GameState.self) private var gameState
    @Environment(NetHackController.self) private var controller

    // Stored scroll position for manual scrolling. When needsClipSync is true
    // the view centers on the game's clipAround tile instead.
    @State private var scrollX: CGFloat = 0
    @State private var scrollY: CGFloat = 0
    @State private var needsClipSync = true

    var body: some View {
        let tileSet     = TileSet.shared
        let tileSize    = tileSet?.displaySize ?? CGSize(width: 32, height: 32)
        let clip        = gameState.clipAround
        let clipVersion = gameState.clipAroundVersion

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

            // MapView is full-map sized; offset it into the viewport and clip.
            ZStack(alignment: .topLeading) {
                Color.black
                MapView()
                    .offset(x: -originX, y: -originY)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
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
