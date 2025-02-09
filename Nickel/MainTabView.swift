//
//  NickelApp.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct MainTabView: View {
    @AppStorage("enableConsole") var enableConsole: Bool = false
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            
            if enableConsole {
                ConsoleView()
                    .tabItem {
                        Label("Console", systemImage: "terminal.fill")
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
