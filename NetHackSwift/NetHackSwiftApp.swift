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
					// Point to NetHack's data files inside the app bundle
					if let dataPath = Bundle.main.resourcePath {
						controller.start(dataPath: dataPath)
					}
				}
        }
    }
}
