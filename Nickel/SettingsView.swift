//
//  SettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI
import Foundation

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    
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
    
    let authMethods = ["None", "Bearer", "Api-Key", "Nickel-Auth", "Nickel-Auth (Custom)"]
    let valueTypes = ["String", "Bool"]
    
    // Reading version from Info.plist
    var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "Unknown"
        }
        return version
    }
    
    // Reading build number from Info.plist
    var appBuild: String {
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "Unknown"
        }
        return build
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
        settings.authMethod = auth
        settings.customAPIURL = components[2]
        settings.customAPIKey = components[3]
        
        // Show alert and exit app
        showCredentialsAlert = true
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API Settings")) {
                    TextField("API URL", text: $settings.customAPIURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    Menu {
                        ForEach(authMethods, id: \.self) { method in
                            Button(action: {
                                settings.authMethod = method
                            }) {
                                HStack {
                                    Text(method)
                                    if settings.authMethod == method {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Auth Method")
                            Spacer()
                            Text(settings.authMethod)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    if showAPIKey {
                        TextField("Auth Key", text: $settings.customAPIKey)
                            .autocapitalization(.none)
                            .transition(.opacity)
                    }
                    
                    if settings.authMethod == "Api-Key" || settings.authMethod == "Bearer" {
                        Button(action: {
                            withAnimation {
                                showAPIKey.toggle()
                            }
                        }) {
                            Text(showAPIKey ? "Hide Auth Key" : "Show Auth Key")
                                .foregroundColor(.blue)
                        }
                    } else if settings.authMethod == "Nickel-Auth" || settings.authMethod == "Nickel-Auth (Custom)" {
                        Button(action: {
                            if let url = URL(string: "https://getnickel.site/instances/") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Browse Compatible Instances")
                                .foregroundColor(.blue)
                        }
                        
                        if settings.authMethod == "Nickel-Auth (Custom)" {
                            TextField("Custom Auth Server URL", text: $settings.customAuthServerURL)
                                .autocapitalization(.none)
                                .keyboardType(.URL)
                        }
                    }
                }
                
                Section(header: Text("Additional Settings")) {
                    Toggle(isOn: $settings.autoSaveToPhotos) {
                        Text("Automatically Save Downloads to Photos")
                    }
                    Toggle(isOn: $settings.rememberPickerDownloadOption) {
                        Text("Remember Picker Download Option")
                    }
                    Toggle(isOn: $settings.enableConsole) {
                        Text("Enable Developer Console")
                    }
                    Toggle(isOn: $settings.autoClearErrorMessage) {
                        Text("Auto-Clear Error Messages")
                    }
                    Toggle(isOn: $settings.autoOpenHome) {
                        Text("Open Home Tab at Launch")
                    }
                    Toggle(isOn: $settings.disableAutoPasteRun) {
                        Text("Disable Auto-Download on Paste")
                    }
                    Toggle(isOn: $settings.disableNotifications) {
                        Text("Disable Download Notifications")
                    }
                }
                
                Section(header: Text("Download Settings")) {
                    Toggle(isOn: $settings.disableBGDownloads) {
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
                
                .onChange(of: settings.disableNotifications || settings.disableBGDownloads || settings.rememberPickerDownloadOption) { oldValue, newValue in
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
                            Text("v\(appVersion)\(appBuild != "100" ? " (\(appBuild))" : "")")
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
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SettingsView()
}


