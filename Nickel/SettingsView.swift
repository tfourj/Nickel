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
    @AppStorage("autoSaveToPhotos") private var autoSaveToPhotos: Bool = false
    @AppStorage("enableConsole") private var enableConsole: Bool = false
    @AppStorage("autoClearErrorMessage") private var autoClearErrorMessage: Bool = false
    
    @State private var showAPIKey = false
    
    let authMethods = ["Bearer", "Api-Key"]
    
    // Reading version from Info.plist
    var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "Unknown"
        }
        return version
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
                        Text("Automatically Save to Photos")
                    }
                    Toggle(isOn: $enableConsole) {
                        Text("Enable Console")
                    }
                    Toggle(isOn: $autoClearErrorMessage) {
                        Text("Auto Clear Error Message")
                    }
                }
                
                // Footer section for version and name
                Section {
                    HStack {
                        Text(appVersion)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("By TfourJ")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}


