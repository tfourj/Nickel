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
        
        if UserDefaults.standard.object(forKey: "landingPageVersion") == nil {
            UserDefaults.standard.set(0, forKey: "landingPageVersion")
            logOutput("First launch detected, landing page version initialized to 0")
        }
        
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
    
    TestNotification()
    
    #else
    
    logOutput("Running on device - tests skipped")
    
    #endif
}
