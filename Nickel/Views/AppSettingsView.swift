//
//  AppSettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var showRestart = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("General")) {
                    NavigationLink(destination: DownloadBehaviorSettingsView()) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Download Behavior")
                        }
                    }
                    
                    NavigationLink(destination: UserInterfaceSettingsView()) {
                        HStack {
                            Image(systemName: "app.badge.fill")
                                .foregroundColor(.purple)
                                .frame(width: 24)
                            Text("User Interface")
                        }
                    }
                    
                    NavigationLink(destination: NotificationsSettingsView()) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            Text("Notifications")
                        }
                    }
                }
                
                Section(header: Text("Advanced")) {
                    NavigationLink(destination: ProcessingSettingsView()) {
                        HStack {
                            Image(systemName: "gearshape.2.fill")
                                .foregroundColor(.green)
                                .frame(width: 24)
                            Text("Processing")
                        }
                    }
                    
                    NavigationLink(destination: RequestConfigurationSettingsView()) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.red)
                                .frame(width: 24)
                            Text("Request Configuration")
                        }
                    }
                }
            }
        }
        .alert("Restart Required", isPresented: $showRestart) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please restart the app for changes to take effect.")
        }
        .onChange(of: settings.disableNotifications || settings.disableBGDownloads || settings.rememberPickerDownloadOption) { oldValue, newValue in
            showRestart = true
        }
    }
}

#Preview {
    AppSettingsView()
        .environmentObject(SettingsModel())
} 
