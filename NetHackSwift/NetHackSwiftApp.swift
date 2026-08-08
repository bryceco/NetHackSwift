//
//  NetHackSwiftApp.swift
//  NetHackSwift
//
//  Created by Bryce Cogswell on 8/6/26.
//

import SwiftUI

@main
struct NetHackSwiftApp: App {
    private let gameState = GameState()
    private let controller = NetHackController()

    init() {
        let resourcesURL = Bundle.main.resourceURL!
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
												  in: .userDomainMask)[0]
        let playgroundURL = appSupport.appendingPathComponent("NetHack", isDirectory: true)
#if true
        try? FileManager.default.removeItem(at: playgroundURL)
#endif
        try? FileManager.default.createDirectory(at: playgroundURL,
												 withIntermediateDirectories: true)
        controller.gameState = gameState
        controller.start(playgroundURL: playgroundURL, resourcesURL: resourcesURL)
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(gameState)
                .environment(controller)
        }
    }
}
