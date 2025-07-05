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
    
    private func decodeBase64Credentials() {
        guard let clipboard = UIPasteboard.general.string,
              let data = Data(base64Encoded: clipboard),
              let decoded = String(data: data, encoding: .utf8) else {
            return
        }
        
        let components = decoded.components(separatedBy: "|")
        
        guard components.count >= 4,
              components[0].lowercased() == "nickel" else {
            return
        }
        
        let auth = components[1]
        guard auth == "Api-Key" || auth == "Bearer" else {
            return
        }
        
        settings.authMethod = auth
        settings.customAPIURL = components[2]
        settings.customAPIKey = components[3]
        
        showCredentialsAlert = true
    }
}

#Preview {
    InstanceSettingsView()
        .environmentObject(SettingsModel())
} 