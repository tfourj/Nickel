//
//  NickelApp.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI
import Darwin

@main
struct NickelApp: App {
    @StateObject private var settings = SettingsModel()

    init() {
        SettingsModel.checkSettings()
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
                .environmentObject(settings)
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
    
    #if DEBUG
    if isDebuggerAttached() {
        logOutput("Debugger detected")
        UIPasteboard.general.string = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        logOutput("🎵 Debug mode: URL set to clipboard")
    }
    #endif
}

/// Detects if a debugger is attached to the current process
func isDebuggerAttached() -> Bool {
    var info = kinfo_proc()
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.size
    let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
    assert(junk == 0, "sysctl failed")
    
    return (info.kp_proc.p_flag & P_TRACED) != 0
}

