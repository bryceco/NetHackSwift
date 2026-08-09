import SwiftUI

@main
struct NetHackSwiftApp: App {
    private let gameState = GameState()
    private let controller: NetHackController?

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
#if true
        try? FileManager.default.removeItem(at: playgroundURL)
#endif
        try? FileManager.default.createDirectory(at: playgroundURL,
                                                 withIntermediateDirectories: true)
        let c = NetHackController()
        c.gameState = gameState
        c.start(playgroundURL: playgroundURL, resourcesURL: resourcesURL)
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
