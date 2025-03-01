//
//  NickelApp.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

@main
struct NickelApp: App {
    init() {
        logOutput("Nickel started!")
        NotificationManager.requestPermission()
    }
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
