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
    @AppStorage("enableBetaUpdates") private var enableBetaUpdates: Bool = false
    
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
    @State private var requestBodyItems: [(key: String, value: String, type: String)] = []
    
    let authMethods = ["None", "Bearer", "Api-Key"]
    let valueTypes = ["String", "Bool"]
    
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
        logOutput("Loading custom request body values called")
        if let saved = UserDefaults.standard.string(forKey: "customRequestBody"),
           let jsonData = saved.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            DispatchQueue.main.async {
                requestBodyItems = jsonObject
                    .sorted { $0.key < $1.key }
                    .map { key, value in
                        let stringValue = "\(value)"
                        let type = value is Bool ? "Bool" : "String"
                        return (key: key, value: stringValue, type: type)
                    }
                    logOutput("Returning custom request body values")
            }
        } else {
            DispatchQueue.main.async {
                requestBodyItems = DownloadManager.defaultRequestBody
                    .sorted { $0.key < $1.key }
                    .map { key, value in
                        let stringValue = "\(value)"
                        // Only treat actual boolean values as Boolean type
                        let type = value is Bool ? "Bool" : "String"
                        return (key: key, value: stringValue, type: type)
                    }
                    logOutput("Returning default request body values")
            }
        }
    }
    
    private func saveRequestBody() {
        var jsonObject: [String: Any] = [:]
        for item in requestBodyItems {
            if item.type == "Bool" {
                if item.value == "1" {
                    jsonObject[item.key] = true
                } else if item.value == "0" {
                    jsonObject[item.key] = false
                } else {
                    jsonObject[item.key] = item.value.lowercased() == "true"
                }
            } else {
                jsonObject[item.key] = item.value
            }
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            UserDefaults.standard.set(jsonString, forKey: "customRequestBody")
            alertMessage = "Settings saved successfully"
        } else {
            alertMessage = "Failed to save request body"
        }
        showAlert = true
    }
    
    private func resetRequestBody() {
        requestBodyItems = DownloadManager.defaultRequestBody.map { key, value in
            let stringValue = "\(value)"
            let type = value is Bool ? "Boolean" : "String"
            return (key: key, value: stringValue, type: type)
        }
        UserDefaults.standard.removeObject(forKey: "customRequestBody")
        alertMessage = "Request body reset to default"
        showAlert = true
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
                    
                    Toggle(isOn: $enableBetaUpdates) {
                        Text("Check for Beta versions")
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
                
                .onChange(of: disableNotifications || disableBGDownloads || enableBetaUpdates) { oldValue, newValue in
                    showRestart = true
                }
                
            }
            .sheet(isPresented: $showRequestEditor) {
                NavigationView {
                    Form {
                        ForEach($requestBodyItems.indices, id: \.self) { index in
                            GeometryReader { geometry in
                                HStack(spacing: 0) {
                                    // Key field - left 35% of width
                                    TextField("Key", text: $requestBodyItems[index].key)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(width: geometry.size.width * 0.35, alignment: .leading)
                                    
                                    // Type selector - using fixed width
                                    Menu {
                                        ForEach(valueTypes, id: \.self) { type in
                                            Button(type) {
                                                requestBodyItems[index].type = type
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text(requestBodyItems[index].type)
                                                .foregroundColor(.primary)
                                            Image(systemName: "chevron.down")
                                                .foregroundColor(.gray)
                                                .font(.caption)
                                        }
                                        .padding(5)
                                        .frame(width: 80)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(Color.gray, lineWidth: 0.5)
                                        )
                                    }
                                    .frame(minWidth: 80, maxWidth: 80)
                                    .padding(.horizontal, 5)
                                    
                                    // Value area - right 35% of width
                                    ZStack {
                                        if requestBodyItems[index].type == "Bool" {
                                            Toggle("", isOn: Binding(
                                                get: { 
                                                    let value = requestBodyItems[index].value.lowercased()
                                                    return value == "true" || value == "1" 
                                                },
                                                set: { newValue in
                                                    // Only update if it's different from current value
                                                    let currentValue = requestBodyItems[index].value.lowercased()
                                                    let isCurrentlyTrue = currentValue == "true" || currentValue == "1"
                                                    
                                                    if newValue != isCurrentlyTrue {
                                                        // Preserve numeric format if that's what was used
                                                        if currentValue == "1" || currentValue == "0" {
                                                            requestBodyItems[index].value = newValue ? "1" : "0"
                                                        } else {
                                                            requestBodyItems[index].value = newValue ? "true" : "false"
                                                        }
                                                    }
                                                }
                                            ))
                                            .labelsHidden()
                                        } else {
                                            TextField("Value", text: $requestBodyItems[index].value)
                                                .autocapitalization(.none)
                                                .disableAutocorrection(true)
                                                .multilineTextAlignment(.trailing)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }
                                    }
                                    .frame(width: geometry.size.width * 0.35, alignment: .trailing)
                                }
                            }
                            .frame(height: 40)
                        }
                        .onDelete { indices in
                            requestBodyItems.remove(atOffsets: indices)
                        }
                        
                        Button("Add New Item") {
                            requestBodyItems.append((key: "", value: "", type: "String"))
                        }
                    }
                    .navigationTitle("Request Body Editor")
                    .navigationBarItems(
                        leading: Button("Cancel") {
                            showRequestEditor = false
                        },
                        trailing: EditButton()
                    )
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Save") {
                                saveRequestBody()
                                showRequestEditor = false
                            }
                        }
                    }
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


