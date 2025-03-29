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
        runAppTests()
    }
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}

func runAppTests() {
    // Only run tests when in the simulator
    #if targetEnvironment(simulator)
    logOutput("Running in simulator - executing tests")
    
    testVersionComparisons()
    TestNotification()
    
    #else
    
    logOutput("Running on device - tests skipped")
    
    #endif
}
