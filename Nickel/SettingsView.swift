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
    
    @State private var showAPIKey = false
    
    let authMethods = ["Bearer", "Api-Key"]
    
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
                
                Section(header: Text("Aditional Settings")) {
                    Toggle(isOn: $autoSaveToPhotos) {
                        Text("Automatically Save to Photos")
                    }
                    Toggle(isOn: $enableConsole) {
                        Text("Enable Console")
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
