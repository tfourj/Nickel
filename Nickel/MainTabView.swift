//
//  NickelApp.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct MainTabView: View {
    @AppStorage("enableConsole") var enableConsole: Bool = false
    @AppStorage("autoOpenHome") private var autoOpenHome: Bool = false
    @Environment(\.scenePhase) var scenePhase

    @State private var selectedTab = 0 // 0 = Home, 1 = Settings, 2 = Console
    @State private var showUpdateAvailable = false
    @State private var latestVersion: String = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0) // Home tab
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(1) // Settings tab
            
            if enableConsole {
                ConsoleView()
                    .tabItem {
                        Label("Console", systemImage: "terminal.fill")
                    }
                    .tag(2) // Console tab
            }
        }
        .onOpenURL { url in
            if selectedTab != 0 {
                selectedTab = 0 // Switch to Home tab if it's not already selected
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active && autoOpenHome {
                if selectedTab != 0 {
                    selectedTab = 0 // Switch to Home tab if it's not already selected
                }
            }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
