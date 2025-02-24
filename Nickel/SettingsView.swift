//
//  SettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

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
    
    @State private var showAPIKey = false
    @State private var customRequestBody: String = ""
    @State private var showRequestEditor = false
    @State private var showAlert = false
    @State private var showRestart = false
    @State private var alertMessage = ""
    
    let authMethods = ["None", "Bearer", "Api-Key"]
    
    // Reading version from Info.plist
    var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "Unknown"
        }
        return version
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
                }
                
                Section(header: Text("Download Settings")) {
                    Toggle(isOn: $disableBGDownloads) {
                            Text("Disable Background Downloads")
                        }
                        .onChange(of: disableBGDownloads) { oldValue, newValue in
                            showRestart = true
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
        }
    }
}

#Preview {
    SettingsView()
}


