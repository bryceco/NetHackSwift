//
//  NetHackSwiftApp.swift
//  NetHackSwift
//
//  Created by Bryce Cogswell on 8/6/26.
//

import SwiftUI

@main
struct NetHackSwiftApp: App {
    @State private var gameState = GameState()
    @State private var controller = NetHackController()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
				.environment(gameState)
				.environment(controller)
				.onAppear {
					let resourcesURL = Bundle.main.resourceURL!
					let appSupport = FileManager.default
						.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
					let playgroundURL = appSupport.appendingPathComponent("NetHack", isDirectory: true)
					#if true
					try! FileManager.default.removeItem(at: playgroundURL)
					#endif
					try? FileManager.default.createDirectory(at: playgroundURL,
						withIntermediateDirectories: true)
					controller.gameState = gameState
					controller.start(playgroundURL: playgroundURL,
					                 resourcesURL: resourcesURL)
				}
        }
    }
}
