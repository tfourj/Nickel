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
    @AppStorage("customAPIURL") private var customAPIURL: String = ""
    @AppStorage("authMethod") private var authMethod: String = ""
    @Environment(\.scenePhase) var scenePhase

    @State private var selectedTab = 0 // 0 = Home, 1 = Settings, 2 = Console
    @State private var showUpdateAvailable = false
    @State private var latestVersion: String = ""
    @State private var showURLSetAlert = false
    private let currentLandingPageVersion = 1
    @State private var completedLandingPageVersion = UserDefaults.standard.integer(forKey: "landingPageVersion")

    var body: some View {
        ZStack {
            // Main app content
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
            if completedLandingPageVersion != currentLandingPageVersion {
                LandingPageView(completedVersion: $completedLandingPageVersion, currentVersion: currentLandingPageVersion)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onOpenURL { url in
            if url.scheme == "nickel", url.host == "setapiurl",
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let instanceURL = queryItems.first(where: { $0.name == "url" })?.value {
                customAPIURL = instanceURL // Save to AppStorage
                authMethod = "Nickel-Auth" // Update authMethod
                logOutput("Updated customAPIURL to: \(instanceURL) and authMethod to: Nickel-Auth")
                showURLSetAlert = true
            }
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
        .alert("URL Set", isPresented: $showURLSetAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The API URL has been updated to: \(customAPIURL) and authMethod to: Nickel-Auth")
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
