//
//  InstanceSettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct InstanceSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var showAPIKey = false
    @State private var showCredentialsAlert = false
    
    let authMethods = ["None", "Bearer", "Api-Key", "Nickel-Auth", "Nickel-Auth (Custom)"]
    
    var body: some View {
        Form {
            Section(header: Text("API Configuration")) {
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
                .onChange(of: settings.authMethod) { oldValue, newValue in
                    if newValue != "Api-Key" && newValue != "Bearer" {
                        showAPIKey = false
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
            
            Section(header: Text("Quick Setup")) {
                Button(action: {
                    exportConfiguration()
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Configuration")
                    }
                }
                .foregroundColor(.blue)
                
                Button(action: {
                    decodeBase64Credentials()
                }) {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                        Text("Import from Clipboard")
                    }
                }
                .foregroundColor(.blue)
            }
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
    
    private func exportConfiguration() {
        var configData: [String: String] = [:]
        
        // Add basic configuration
        configData["authMethod"] = settings.authMethod
        configData["apiURL"] = settings.customAPIURL
        
        // Add auth-specific data
        if settings.authMethod == "Api-Key" || settings.authMethod == "Bearer" {
            configData["apiKey"] = settings.customAPIKey
        } else if settings.authMethod == "Nickel-Auth (Custom)" {
            configData["authServerURL"] = settings.customAuthServerURL
        }
        
        // Convert to JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: configData, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        // Copy to clipboard
        UIPasteboard.general.string = jsonString
        
        // Show success alert
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Configuration Exported",
                message: "Your configuration has been copied to clipboard. You can now share it with others.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(alert, animated: true)
            }
        }
    }
    
    private func decodeBase64Credentials() {
        guard let clipboard = UIPasteboard.general.string else {
            showImportError("No data found in clipboard")
            return
        }
        
        // Try to parse as JSON first (new format)
        if let jsonData = clipboard.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
            importFromJSON(jsonObject)
            return
        }
        
        // Fallback to old base64 format
        guard let data = Data(base64Encoded: clipboard),
              let decoded = String(data: data, encoding: .utf8) else {
            showImportError("Invalid clipboard data format")
            return
        }
        
        let components = decoded.components(separatedBy: "|")
        
        guard components.count >= 4,
              components[0].lowercased() == "nickel" else {
            showImportError("Invalid configuration format")
            return
        }
        
        let auth = components[1]
        guard auth == "Api-Key" || auth == "Bearer" else {
            showImportError("Unsupported auth method")
            return
        }
        
        settings.authMethod = auth
        settings.customAPIURL = components[2]
        settings.customAPIKey = components[3]
        
        showCredentialsAlert = true
    }
    
    private func importFromJSON(_ config: [String: String]) {
        // Validate required fields
        guard let authMethod = config["authMethod"],
              let apiURL = config["apiURL"] else {
            showImportError("Missing required configuration fields")
            return
        }
        
        // Set basic configuration
        settings.authMethod = authMethod
        settings.customAPIURL = apiURL
        
        // Set auth-specific data
        if authMethod == "Api-Key" || authMethod == "Bearer" {
            if let apiKey = config["apiKey"] {
                settings.customAPIKey = apiKey
            }
        } else if authMethod == "Nickel-Auth (Custom)" {
            if let authServerURL = config["authServerURL"] {
                settings.customAuthServerURL = authServerURL
            }
        }
        
        showCredentialsAlert = true
    }
    
    private func showImportError(_ message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "Import Failed",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(alert, animated: true)
            }
        }
    }
}

#Preview {
    InstanceSettingsView()
        .environmentObject(SettingsModel())
} 