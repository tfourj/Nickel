//
//  SettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI
import Foundation

struct SettingsView: View {
    @AppStorage("customAPIURL") private var customAPIURL: String = ""
    @AppStorage("customAPIKey") private var customAPIKey: String = ""
    @AppStorage("authMethod") private var authMethod: String = "Api-Key"
    @AppStorage("autoSaveToPhotos") private var autoSaveToPhotos: Bool = true
    @AppStorage("enableConsole") private var enableConsole: Bool = false
    @AppStorage("autoClearErrorMessage") private var autoClearErrorMessage: Bool = false
    @AppStorage("autoOpenHome") private var autoOpenHome: Bool = false
    @AppStorage("disableAutoPasteRun") private var disableAutoPasteRun: Bool = false
    @AppStorage("disableBGDownloads") private var disableBGDownloads: Bool = false
    @AppStorage("disableNotifications") private var disableNotifications: Bool = false
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates: Bool = true
    
    @State private var showAPIKey = false
    @State private var customRequestBody: String = ""
    @State private var showRequestEditor = false
    @State private var showAlert = false
    @State private var showRestart = false
    @State private var alertMessage = ""
    @State private var showCredentialsAlert = false
    @State private var longPressTimer: Timer?
    @GestureState private var isDetectingLongPress = false
    @State private var isCheckingForUpdate = false
    @State private var showUpdateAvailable = false
    @State private var latestVersion: String = ""
    
    let authMethods = ["None", "Bearer", "Api-Key"]
    
    // Reading version from Info.plist
    var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "Unknown"
        }
        return version
    }
    
    func checkForUpdates() {
        isCheckingForUpdate = true

        Nickel.checkForUpdates(appVersion: appVersion) { remoteVersion, errorMessage in
            DispatchQueue.main.async {
                isCheckingForUpdate = false

                if let errorMessage = errorMessage {
                    alertMessage = errorMessage
                    showAlert = true
                    return
                }

                guard let remoteVersion = remoteVersion else {
                    alertMessage = "Unable to retrieve version information"
                    showAlert = true
                    return
                }

                latestVersion = remoteVersion

                if compareVersions(appVersion, remoteVersion) == .orderedAscending {
                    showUpdateAvailable = true
                } else {
                    alertMessage = "You have the latest version (\(appVersion))"
                    showAlert = true
                }
            }
        }
    }
    
    public func openGitHubReleases() {
        if let url = URL(string: githubRepoURL), UIApplication.shared.canOpenURL(url) {        UIApplication.shared.open(url)
        }
    }
    
    private func loadSavedRequestBody() {
        if let saved = UserDefaults.standard.string(forKey: "customRequestBody") {
            customRequestBody = saved
        } else {
            // Convert default request body to JSON string
            if let jsonData = try? JSONSerialization.data(withJSONObject: DownloadManager.defaultRequestBody, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                customRequestBody = jsonString
            }
        }
    }
    
    private func saveRequestBody() {
        guard !customRequestBody.isEmpty else { return }
        
        // Validate JSON
        if let jsonData = customRequestBody.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: jsonData)) != nil {
            UserDefaults.standard.set(customRequestBody, forKey: "customRequestBody")
            alertMessage = "Settings saved successfully"
        } else {
            alertMessage = "Invalid JSON format"
        }
        showAlert = true
    }
    
    private func resetRequestBody() {
        if let jsonData = try? JSONSerialization.data(withJSONObject: DownloadManager.defaultRequestBody, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            customRequestBody = jsonString
            UserDefaults.standard.removeObject(forKey: "customRequestBody")
            alertMessage = "Request body reset to default"
            showAlert = true
        }
    }
    
    private func decodeBase64Credentials() {
        logOutput("Decode credentials called.")
        guard let clipboard = UIPasteboard.general.string,
              let data = Data(base64Encoded: clipboard),
              let decoded = String(data: data, encoding: .utf8) else {
            return
        }
        
        let components = decoded.components(separatedBy: "|")
        
        // Validate format and "nickel" prefix
        guard components.count >= 4,
              components[0].lowercased() == "nickel" else {
            return
        }
        
        // Validate auth method
        let auth = components[1]
        guard auth == "Api-Key" || auth == "Bearer" else {
            return
        }
        
        // Set values
        authMethod = auth
        customAPIURL = components[2]
        customAPIKey = components[3]
        
        // Show alert and exit app
        showCredentialsAlert = true
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API Settings")) {
                    TextField("API URL", text: $customAPIURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    Picker("Authentication Method", selection: $authMethod) {
                        ForEach(authMethods, id: \.self) { method in
                            Text(method)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if showAPIKey {
                        TextField("Auth Key", text: $customAPIKey)
                            .autocapitalization(.none)
                            .transition(.opacity)
                    }
                    
                    Button(action: {
                        withAnimation {
                            showAPIKey.toggle()
                        }
                    }) {
                        Text(showAPIKey ? "Hide Auth Key" : "Show Auth Key")
                            .foregroundColor(.blue)
                    }
                }
                
                Section(header: Text("Additional Settings")) {
                    Toggle(isOn: $autoSaveToPhotos) {
                        Text("Save Downloads to Photos Automatically")
                    }
                    Toggle(isOn: $enableConsole) {
                        Text("Enable Developer Console")
                    }
                    Toggle(isOn: $autoClearErrorMessage) {
                        Text("Clear Error Messages Automatically")
                    }
                    Toggle(isOn: $autoOpenHome) {
                        Text("Open Home Tab on App Launch")
                    }
                    Toggle(isOn: $disableAutoPasteRun) {
                        Text("Disable Auto-Download After Pasting Link")
                    }
                    Toggle(isOn: $disableNotifications) {
                        Text("Disable Download Notifications")
                    }
                }
                
                Section(header: Text("Download Settings")) {
                    Toggle(isOn: $disableBGDownloads) {
                        Text("Disable Background Downloads")
                        Text("Enable if using on device IPA signers")
                            .font(.footnote) // Smaller font size
                            .foregroundColor(.gray) // Gray color
                            .padding(.top, 5) // Optional: Adds a little space between the toggle and the text
                    }

                    Button("Edit Request Body") {
                        loadSavedRequestBody()
                        showRequestEditor = true
                    }
                    
                    Button("Reset Request Body to Default") {
                        resetRequestBody()
                    }
                    .foregroundColor(.red)
                }
                
                Section(header: Text("Updates")) {
                    Toggle(isOn: $autoCheckUpdates) {
                        Text("Check for Updates Automatically")
                    }
                    
                    HStack {
                        Text("Nickel Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: checkForUpdates) {
                        HStack {
                            Text("Check for Updates")
                            Spacer()
                            if isCheckingForUpdate {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                    }
                }
                
                .onChange(of: disableNotifications || disableBGDownloads) { oldValue, newValue in
                    showRestart = true
                }
                
            }
            .sheet(isPresented: $showRequestEditor) {
                NavigationView {
                    VStack {
                        TextEditor(text: $customRequestBody)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .navigationTitle("Request Body Editor")
                    .navigationBarItems(
                        leading: Button("Cancel") {
                            showRequestEditor = false
                        },
                        trailing: Button("Save") {
                            saveRequestBody()
                            showRequestEditor = false
                        }
                    )
                }
            }
            
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ZStack {
                        HStack {
                            Text("v\(appVersion)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("by TfourJ")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        
                        HStack(spacing: 0) {
                            Image("Nickel")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 30) // Adjust this value to match text height
                                .foregroundColor(.primary)
                            Text("Settings")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .gesture(
                                    LongPressGesture(minimumDuration: 2)
                                        .onEnded { _ in
                                            decodeBase64Credentials()
                                        }
                                )
                        }
                    }
                }
            }
            
            .alert("Request Body", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            
            .alert("Restart Required", isPresented: $showRestart) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please restart the app for changes to take effect.")
            }
            
            .alert("Nickel", isPresented: $showCredentialsAlert) {
                Button("OK", role: .cancel) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        exit(0)
                    }
                }
            } message: {
                Text("Credentials set, app will be restarted.")
            }
            
            .alert("Update Available", isPresented: $showUpdateAvailable) {
                Button("Open GitHub", role: .none) {
                    openGitHubReleases()
                }
                Button("Later", role: .cancel) { }
            } message: {
                Text("Version \(latestVersion) is available. You currently have version \(appVersion).")
            }
        }
    }
}

#Preview {
    SettingsView()
}


