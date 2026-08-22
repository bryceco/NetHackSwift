import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: NetHackController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI finishes building its menu bar synchronously before this point,
        // but AppKit (NSFontManager) may append Format/View items on the same
        // run-loop pass. Defer one cycle to ensure we run last.
        DispatchQueue.main.async {
            Self.removeUnwantedMenus()
        }
    }

    private static func removeUnwantedMenus() {
        guard let menu = NSApp.mainMenu else { return }
        // NOTE: These titles are English-only. SwiftUI and AppKit don't expose a
        // locale-independent handle for the Format (NSFontManager) and View menus,
        // so title matching is the simplest reliable option for now.
        for title in ["Format", "View"] {
            if let item = menu.items.first(where: { $0.title == title }) {
                menu.removeItem(item)
            }
        }
    }

	// Called when the user presses Cmd-Q or closes the window.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard
			let controller,
			controller.isInitialized
		else {
			return .terminateNow
		}

		switch controller.runningState {
		case .nethackPreGame:
			// User quit during character selection
			return .terminateNow
		case .nethackGameRunning:
			// User requested to quit.
			// This will tell nethack to save, and we will not allow the quit until it finishes
			controller.runningState = .nethackExitingAfterUserRequestedSave
			controller.saveAndQuit()
			// Don't exit until nethack has finished saving and calls exitWindows()
			return .terminateLater
		case .nethackExitingAfterUserRequestedSave:
			// already waiting for nethack to finish saving
			return .terminateLater
		case .nethackExitedAfterPlayerDied:
			// nethack terminated, and then user requested to quit
			return .terminateNow
		}
    }
}

@main
struct NetHackSwiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
		
		// Restore display mode from saved preferences.
		let storedAsciiMode = UserDefaults.standard.bool(forKey: "mapUsesAsciiDisplay")
		gameState.mapUsesAsciiDisplay = storedAsciiMode
		if storedAsciiMode {
			TileSet.shared = nil
		} else {
			let storedName = UserDefaults.standard.string(forKey: "selectedTileSetName") ?? TileSetDescriptor.default.resourceName
			let desc = TileSetDescriptor.available.first(where: { $0.resourceName == storedName }) ?? TileSetDescriptor.default
			TileSet.shared = desc.load()
		}

        let c = NetHackController()
        c.gameState = gameState
        c.start(playgroundURL: playgroundURL,
				resourcesURL: resourcesURL)
        controller = c
        appDelegate.controller = c
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
        .commands {
            DefaultMenuRemovals()
            GameCommands(controller: controller)
        }
    }
}
