//
//  SettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct RequestBodyItem: Identifiable {
    let id = UUID()
    var key: String
    var value: String
    var type: String
    var order: Int
}

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom Tab Bar
                HStack(spacing: 0) {
                    TabButton(
                        title: "Instance",
                        icon: "server.rack",
                        isSelected: selectedTab == 0
                    ) {
                        selectedTab = 0
                    }
                    
                    TabButton(
                        title: "Settings",
                        icon: "gearshape",
                        isSelected: selectedTab == 1
                    ) {
                        selectedTab = 1
                    }
                    
                    TabButton(
                        title: "About",
                        icon: "info.circle",
                        isSelected: selectedTab == 2
                    ) {
                        selectedTab = 2
                    }
                }
                .background(Color(.systemBackground))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(.separator)),
                    alignment: .bottom
                )
                
                // Tab Content
                TabView(selection: $selectedTab) {
                    InstanceSettingsView()
                        .tag(0)
                    
                    AppSettingsView()
                        .tag(1)
                    
                    AboutView()
                        .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        Image("Nickel")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 30)
                            .foregroundColor(.primary)
                        Text("Settings")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsModel())
}


