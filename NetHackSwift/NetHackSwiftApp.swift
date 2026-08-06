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

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(gameState)
        }
    }
}
