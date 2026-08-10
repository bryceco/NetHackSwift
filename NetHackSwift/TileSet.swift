import AppKit
import NetHackBridge

/// Manages the NetHack tile sprite sheet and vends per-tile images.
///
/// The sprite sheet uses a bottom-up row convention: tile 0 is in the last
/// row of the image (highest y-coordinate in AppKit's flipped coordinates),
/// so rows are indexed as `rows - 1 - tile/columns`.
final class TileSet {
    let image: NSImage
    let tileSize: NSSize
    let rows: Int
    let columns: Int

    static var shared: TileSet?

    init(image: NSImage, tileSize: NSSize) {
        self.image = image
        self.tileSize = tileSize
        rows    = Int(image.size.height / tileSize.height)
        columns = Int(image.size.width  / tileSize.width)
    }

    // MARK: - Source rects

    /// Returns the source rectangle in the sprite sheet for a flat tile index.
    func sourceRect(forTile tile: Int) -> NSRect {
        let row = rows - 1 - tile / columns
        let col = tile % columns
        return NSRect(
            x: CGFloat(col) * tileSize.width,
            y: CGFloat(row) * tileSize.height,
            width:  tileSize.width,
            height: tileSize.height
        )
    }

    /// Returns the source rectangle for the tile described by a glyph struct,
    /// or nil when the glyph has no tile (tileidx < 0).
    func sourceRect(forGlyph glyph: nhswift_glyph) -> NSRect? {
        guard glyph.tileidx >= 0 else { return nil }
        return sourceRect(forTile: Int(glyph.tileidx))
    }

    // MARK: - Image extraction

    /// Extracts a single tile from the sprite sheet.
    /// Pass `enabled: false` to render at 50% opacity (greyed-out appearance).
    func image(forTile tile: Int, enabled: Bool = true) -> NSImage {
        let srcRect = sourceRect(forTile: tile)
        let opacity: CGFloat = enabled ? 1.0 : 0.5
        return NSImage(size: tileSize, flipped: false) { dstRect in
            self.image.draw(in: dstRect, from: srcRect, operation: .copy, fraction: opacity)
            return true
        }
    }

    /// Extracts the tile image for a glyph, or returns nil if it has no tile.
    func image(forGlyph glyph: nhswift_glyph, enabled: Bool = true) -> NSImage? {
        guard glyph.tileidx >= 0 else { return nil }
        return image(forTile: Int(glyph.tileidx), enabled: enabled)
    }
}
