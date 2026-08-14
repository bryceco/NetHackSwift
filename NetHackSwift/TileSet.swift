import AppKit
import NetHackBridge

// MARK: - TileSetDescriptor

/// Describes one available tile-set resource without loading it.
struct TileSetDescriptor {
    /// Display name shown in menus and preferences.
    let name: String
    /// PNG filename (without extension) as it appears in the app bundle's Resources.
    let resourceName: String
    /// Size of a single tile in the sprite sheet, in points.
    let tileSize: CGSize

    /// Loads and returns a ready-to-use TileSet, or nil if the resource is missing.
    func load() -> TileSet? {
        guard let url   = Bundle.main.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        return TileSet(image: image, tileSize: tileSize)
    }

    // MARK: Catalog

    /// All tile sets that ship with the app, in the order they should appear in menus.
    static let available: [TileSetDescriptor] = [
        TileSetDescriptor(name: "NetHack Default (16x16)",
                          resourceName: "nhtiles",
                          tileSize: CGSize(width: 16, height: 16)),
        TileSetDescriptor(name: "PixelHack (32x32)",
                          resourceName: "PixelHack500_32x32",
                          tileSize: CGSize(width: 32, height: 32)),
		TileSetDescriptor(name: "Nevanda (32x32)",
						  resourceName: "Nevanda_5.0.0_32x32",
						  tileSize: CGSize(width: 32, height: 32)),
    ]

	static var `default`: TileSetDescriptor {
		get {
			return Self.available[1]
		}
	}
}

// MARK: - TileSet

/// Manages the NetHack tile sprite sheet and vends per-tile CGImages.
///
/// Tile extraction uses `CGImage.cropping(to:)`. CGImage has y=0 at the top,
/// which matches the visual layout of the sprite sheet (tile 0 at top-left),
/// so the cropping rect arithmetic needs no y-flip.
/// Note: rendering the extracted CGImages into a SwiftUI Canvas CGContext
/// (which is y-down) requires a coordinate flip at the call site; see MapView.
final class TileSet {
	let image: NSImage
	let tileSize: CGSize
	let rows: Int
	let columns: Int

	static var shared: TileSet?

	private let cgSource: CGImage
	/// Lazily populated crop cache: tile index → CGImage sub-region.
	private var cgImageCache: [Int: CGImage] = [:]

	init(image: NSImage, tileSize: CGSize) {
		self.image = image
		self.tileSize = tileSize
		guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
			fatalError("TileSet: could not obtain CGImage from sprite sheet")
		}
		cgSource = cg
		// Use CGImage pixel dimensions so the math works on Retina images too.
		rows    = cg.height / Int(tileSize.height)
		columns = cg.width  / Int(tileSize.width)
	}

	// MARK: - Image extraction

	/// Returns the pixel rect inside `cgSource` for a flat tile index.
	/// CGImage origin is top-left, matching the visual order of the sprite sheet.
	private func cgRect(forTile tile: Int) -> CGRect {
		let col = tile % columns
		let row = tile / columns
		return CGRect(
			x: CGFloat(col) * tileSize.width,
			y: CGFloat(row) * tileSize.height,
			width:  tileSize.width,
			height: tileSize.height
		)
	}

	/// Returns a cached CGImage for the tile at `tileidx`.
	/// Crops from the sprite sheet on first access and caches the result.
	func cgImage(forTile tile: Int) -> CGImage? {
		if let cached = cgImageCache[tile] { return cached }
		guard let cropped = cgSource.cropping(to: cgRect(forTile: tile)) else { return nil }
		cgImageCache[tile] = cropped
		return cropped
	}

	func cgImage(forGlyph glyph: nhswift_glyph) -> CGImage? {
		guard glyph.glyph >= 0 else { return nil }
		return cgImage(forTile: Int(glyph.gm.tileidx))
	}

	/// Returns an NSImage for the tile — wraps cgImage(forGlyph:) for callers that need NSImage.
	func image(forGlyph glyph: nhswift_glyph) -> NSImage? {
		guard let cg = cgImage(forGlyph: glyph) else { return nil }
		return NSImage(cgImage: cg, size: tileSize)
	}

	func cgImage(forGlyph glyph: Int) -> CGImage? {
		guard glyph >= 0 else { return nil }
		let tile = NetHackBridge.tileIndex(forGlyph: glyph)
		return cgImage(forTile: tile)
	}

	func image(forGlyph glyph: Int) -> NSImage? {
		guard let cg = cgImage(forGlyph: glyph) else { return nil }
		return NSImage(cgImage: cg, size: tileSize)
	}
}
