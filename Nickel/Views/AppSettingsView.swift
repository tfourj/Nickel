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
    @State private var showClearCacheAlert = false
    @State private var clearCacheMessage = ""
    @State private var isClearingCache = false
    
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
                
                Section(header: Text("Cache")) {
                    Toggle(isOn: $settings.clearCacheOnStart) {
                        HStack {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Clear Cache on Start")
                                Text("Automatically clear cache when app launches")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Button(action: {
                        clearCache()
                    }) {
                        HStack {
                            Image(systemName: "trash.circle.fill")
                                .foregroundColor(.red)
                                .frame(width: 24)
                            Text("Clear Cache Now")
                            Spacer()
                            if isClearingCache {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isClearingCache)
                }
            }
        }
        .alert("Restart Required", isPresented: $showRestart) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please restart the app for changes to take effect.")
        }
        .alert("Cache Cleared", isPresented: $showClearCacheAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(clearCacheMessage)
        }
        .onChange(of: settings.disableNotifications || settings.disableBGDownloads || settings.rememberPickerDownloadOption) { oldValue, newValue in
            showRestart = true
        }
    }
    
    private func clearCache() {
        isClearingCache = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = FileDownloader.clearAllCache()
            DispatchQueue.main.async {
                isClearingCache = false
                if let error = result.error {
                    var message = "Cache cleared with some errors:\n\(error)\n\n"
                    message += "Removed \(result.tempCount) files from temp folder and \(result.cacheCount) files from caches folder."
                    if result.networkCacheCleared {
                        message += "\nNetwork cache also cleared."
                    }
                    clearCacheMessage = message
                } else {
                    var message = "Cache cleared successfully!\n\n"
                    let totalFiles = result.tempCount + result.cacheCount
                    message += "Removed \(result.tempCount) files from temp folder and \(result.cacheCount) files from caches folder (\(totalFiles) total)."
                    if result.networkCacheCleared {
                        message += "\nNetwork cache also cleared."
                    }
                    clearCacheMessage = message
                }
                showClearCacheAlert = true
            }
        }
    }
}

#Preview {
    AppSettingsView()
        .environmentObject(SettingsModel())
} 
