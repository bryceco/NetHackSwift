import AppKit
import NetHackBridge

// MARK: - TileSetDescriptor

/// Describes one available tile-set resource without loading it.
struct TileSetDescriptor {
    /// Display name shown in menus and preferences.
    let name: String
    /// PNG filename (without extension) as it appears in the app bundle's Resources.
    let resourceName: String
    /// Native size of a single tile in the sprite sheet, in pixels. Used for cropping.
    let tileSize: CGSize
    /// Size at which each tile is rendered on screen. Defaults to tileSize.
    let displaySize: CGSize

    init(name: String, resourceName: String, tileSize: CGSize, displaySize: CGSize? = nil) {
        self.name = name
        self.resourceName = resourceName
        self.tileSize = tileSize
        self.displaySize = displaySize ?? tileSize
    }

    /// Loads and returns a ready-to-use TileSet, or nil if the resource is missing.
    func load() -> TileSet? {
        guard let url   = Bundle.main.url(forResource: resourceName, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        return TileSet(image: image, tileSize: tileSize, displaySize: displaySize)
    }

    // MARK: Catalog

    /// All tile sets that ship with the app, in the order they should appear in menus.
    static let available: [TileSetDescriptor] = [
        TileSetDescriptor(name: "NetHack Default (32x32)",
                          resourceName: "nhtiles16x16",
                          tileSize: CGSize(width: 16, height: 16),
                          displaySize: CGSize(width: 32, height: 32)),
        TileSetDescriptor(name: "PixelHack (32x32)",
                          resourceName: "PixelHack500_32x32",
                          tileSize: CGSize(width: 32, height: 32)),
		TileSetDescriptor(name: "Nevanda (32x32)",
						  resourceName: "Nevanda_5.0.0_32x32",
						  tileSize: CGSize(width: 32, height: 32)),
    ]

	static var `default`: TileSetDescriptor {
		return Self.available[0]
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
	let displaySize: CGSize
	let rows: Int
	let columns: Int

	static var shared: TileSet?

	private let cgSource: CGImage
	/// Lazily populated crop cache: tile index → CGImage sub-region.
	private var cgImageCache: [Int: CGImage] = [:]

	init(image: NSImage, tileSize: CGSize, displaySize: CGSize? = nil) {
		self.image = image
		self.tileSize = tileSize
		self.displaySize = displaySize ?? tileSize
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
		let rect = cgRect(forTile: tile)
		guard let cropped = cgSource.cropping(to: rect) else { return nil }
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
		if tile < 0 {
			return nil
		}
		return cgImage(forTile: tile)
	}

	func image(forGlyph glyph: Int) -> NSImage? {
		guard let cg = cgImage(forGlyph: glyph) else { return nil }
		return NSImage(cgImage: cg, size: tileSize)
	}
}

// MARK: - NHColor -> NSColor

extension NHColor {
    /// Maps a NetHack CLR_* color value to its nearest NSColor equivalent.
    /// The palette approximates the classic 16-color ANSI terminal palette.
    /// NHColorNone (NO_COLOR) returns nil — let the caller apply its default.
    func nsColor() -> NSColor? {
        switch self {
        case .black:         return NSColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1)
        case .red:           return NSColor(red: 0.72, green: 0.07, blue: 0.07, alpha: 1)
        case .green:         return NSColor(red: 0.07, green: 0.55, blue: 0.07, alpha: 1)
        case .brown:         return NSColor(red: 0.60, green: 0.35, blue: 0.07, alpha: 1)
        case .blue:          return NSColor(red: 0.07, green: 0.07, blue: 0.72, alpha: 1)
        case .magenta:       return NSColor(red: 0.60, green: 0.07, blue: 0.60, alpha: 1)
        case .cyan:          return NSColor(red: 0.07, green: 0.55, blue: 0.55, alpha: 1)
        case .gray:          return NSColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
        case .none:          return nil
        case .orange:        return NSColor(red: 1.00, green: 0.55, blue: 0.00, alpha: 1)
        case .brightGreen:   return NSColor(red: 0.00, green: 0.80, blue: 0.00, alpha: 1)
        case .yellow:        return NSColor(red: 0.80, green: 0.80, blue: 0.00, alpha: 1)
        case .brightBlue:    return NSColor(red: 0.30, green: 0.30, blue: 1.00, alpha: 1)
        case .brightMagenta: return NSColor(red: 0.90, green: 0.10, blue: 0.90, alpha: 1)
        case .brightCyan:    return NSColor(red: 0.00, green: 0.85, blue: 0.85, alpha: 1)
        case .white:         return .white
        @unknown default:    return nil
        }
    }
}

