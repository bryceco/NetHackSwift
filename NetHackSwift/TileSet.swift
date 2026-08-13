import AppKit
import NetHackBridge

/// Manages the NetHack tile sprite sheet and vends per-tile CGImages.
///
/// Extraction uses `CGImage.cropping(to:)` directly. CGImage has y=0 at the
/// top of the image, which matches the visual layout of the sprite sheet
/// (tile 0 at top-left), so no coordinate flipping is needed.
final class TileSet {
	let image: NSImage
	let tileSize: NSSize
	let rows: Int
	let columns: Int

	static var shared: TileSet?

	private let cgSource: CGImage
	/// Lazily populated crop cache: tile index → CGImage sub-region.
	private var cgImageCache: [Int: CGImage] = [:]

	init(image: NSImage, tileSize: NSSize) {
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
	func cgImage(forGlyph glyph: nhswift_glyph) -> CGImage? {
		guard glyph.glyph >= 0 else { return nil }
		let tile = Int(glyph.gm.tileidx)
		if let cached = cgImageCache[tile] { return cached }
		guard let cropped = cgSource.cropping(to: cgRect(forTile: tile)) else { return nil }
		cgImageCache[tile] = cropped
		return cropped
	}

	/// Returns an NSImage for the tile — wraps cgImage(forGlyph:) for callers that need NSImage.
	func image(forGlyph glyph: nhswift_glyph) -> NSImage? {
		guard let cg = cgImage(forGlyph: glyph) else { return nil }
		return NSImage(cgImage: cg, size: tileSize)
	}
}
