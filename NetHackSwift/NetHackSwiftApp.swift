import AppKit
import SwiftUI

@main
struct NetHackSwiftApp: App {
    private let gameState = GameState()
    private let controller: NetHackController?


	static private func copyTo(playgroundURL: URL, from fromURL: URL) {
		let fm = FileManager.default
		let items = try! fm.contentsOfDirectory(at: fromURL,
												includingPropertiesForKeys: nil,
												options: [.skipsHiddenFiles])
		for item in items {
			let dest = playgroundURL.appendingPathComponent(item.lastPathComponent)
			guard !fm.fileExists(atPath: dest.path) else { continue }
			try! fm.copyItem(at: item, to: dest)
		}
	}
	
    init() {
        // Previews run the full app, but NetHackBridge's ObjC classes are not
        // available in the JIT preview context. Skip bridge creation entirely.
        // Use raw C getenv rather than ProcessInfo — Swift's ObjC bridging of
        // NSProcessInfo generates a dynamic selector that isn't registered in
        // the Xcode JIT preview context.
        let isPreview = getenv("XCODE_RUNNING_FOR_PLAYGROUNDS").map { String(cString: $0) == "1" } ?? false
        guard !isPreview else {
            controller = nil
            return
        }
        let resourcesURL = Bundle.main.resourceURL!
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask)[0]
        let playgroundURL = appSupport.appendingPathComponent("NetHack", isDirectory: true)
        let isNewPlayground = !FileManager.default.fileExists(atPath: playgroundURL.path)
        try? FileManager.default.createDirectory(at: playgroundURL, withIntermediateDirectories: true)
        if isNewPlayground {
            // Copy initial writable game files (livelog, logfile, perm, etc.) on first run.
            // nhdat and sysconf live in Resources/ and are never copied — NetHack
            // reads them read-only directly from the app bundle.
            Self.copyTo(playgroundURL: playgroundURL,
                        from: resourcesURL.appendingPathComponent("Playground"))
        }
		FileManager.default.changeCurrentDirectoryPath(resourcesURL.path)

        if let tilesURL = Bundle.main.url(forResource: "nhtiles", withExtension: "png"),
           let tilesImage = NSImage(contentsOf: tilesURL)
		{
            TileSet.shared = TileSet(image: tilesImage, tileSize: NSSize(width: 16, height: 16))
        }

        let c = NetHackController()
        c.gameState = gameState
        c.start(playgroundURL: playgroundURL,
				resourcesURL: resourcesURL)
        controller = c
    }

    var body: some Scene {
        WindowGroup {
            if let controller {
                MainWindowView()
                    .environment(gameState)
                    .environment(controller)
            } else {
                EmptyView()
            }
        }
    }
}
