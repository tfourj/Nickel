//
//  AppSettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var showRequestEditor = false
    @State private var showAlert = false
    @State private var showRestart = false
    @State private var alertMessage = ""
    @State private var requestBodyItems: [RequestBodyItem] = []
    
    let valueTypes = ["String", "Bool"]
    
    var body: some View {
        Form {
            Section(header: Text("Download Behavior")) {
                Toggle(isOn: $settings.autoSaveToPhotos) {
                    Text("Auto-Save to Photos")
                }
                
                Toggle(isOn: $settings.rememberPickerDownloadOption) {
                    Text("Remember Picker Choice")
                }
                
                Toggle(isOn: $settings.disableAutoPasteRun) {
                    Text("Disable Auto-Download on Paste")
                }
                
                Toggle(isOn: $settings.copyDownloadedVideoURL) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copy Downloaded Video URL")
                        Text("Copy video URL to clipboard after download")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                }
                
                Toggle(isOn: $settings.disableBGDownloads) {
                    Text("Disable Background Downloads")
                    Text("Enable if using on device IPA signers")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }

                Toggle(isOn: $settings.askDownloadOptionOnShareSheet) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask Download Option on Share Sheet")
                        Text("Prompt for download mode when opening links via share sheet")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Section(header: Text("User Interface")) {
                Toggle(isOn: $settings.autoOpenHome) {
                    Text("Open Home Tab at Launch")
                }
                
                Toggle(isOn: $settings.autoClearErrorMessage) {
                    Text("Auto-Clear Error Messages")
                }
                
                Toggle(isOn: $settings.enableConsole) {
                    Text("Enable Developer Console")
                }
                
                #if DEBUG
                Toggle(isOn: $settings.enableDebugTab) {
                    Text("Show Debug Tab")
                }
                #endif
            }
            
            Section(header: Text("Notifications")) {
                Toggle(isOn: $settings.disableNotifications) {
                    Text("Disable Download Notifications")
                }
            }
            
            Section(header: Text("Request Configuration")) {
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
            RequestBodyEditorView(
                requestBodyItems: $requestBodyItems,
                showRequestEditor: $showRequestEditor,
                showAlert: $showAlert,
                alertMessage: $alertMessage
            )
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
        .onChange(of: settings.disableNotifications || settings.disableBGDownloads || settings.rememberPickerDownloadOption) { oldValue, newValue in
            showRestart = true
        }
    }
    
    private func loadSavedRequestBody() {
        if let saved = UserDefaults.standard.string(forKey: "customRequestBody"),
           let jsonData = saved.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            DispatchQueue.main.async {
                var items: [RequestBodyItem] = []
                
                if let orderData = UserDefaults.standard.data(forKey: "requestBodyOrder"),
                   let orderArray = try? JSONSerialization.jsonObject(with: orderData) as? [String] {
                    for (index, key) in orderArray.enumerated() {
                        if let value = jsonObject[key] {
                            let stringValue = "\(value)"
                            let type = value is Bool ? "Bool" : "String"
                            items.append(RequestBodyItem(key: key, value: stringValue, type: type, order: index))
                        }
                    }
                    for (key, value) in jsonObject {
                        if !orderArray.contains(key) {
                            let stringValue = "\(value)"
                            let type = value is Bool ? "Bool" : "String"
                            items.append(RequestBodyItem(key: key, value: stringValue, type: type, order: items.count))
                        }
                    }
                } else {
                    items = jsonObject
                        .sorted { $0.key < $1.key }
                        .enumerated()
                        .map { index, element in
                            let stringValue = "\(element.value)"
                            let type = element.value is Bool ? "Bool" : "String"
                            return RequestBodyItem(key: element.key, value: stringValue, type: type, order: index)
                        }
                }
                
                requestBodyItems = items
            }
        } else {
            DispatchQueue.main.async {
                requestBodyItems = DownloadManager.defaultRequestBody
                    .sorted { $0.key < $1.key }
                    .enumerated()
                    .map { index, element in
                        let stringValue = "\(element.value)"
                        let type = element.value is Bool ? "Bool" : "String"
                        return RequestBodyItem(key: element.key, value: stringValue, type: type, order: index)
                    }
            }
        }
    }
    
    private func resetRequestBody() {
        requestBodyItems = DownloadManager.defaultRequestBody
            .sorted { $0.key < $1.key }
            .enumerated()
            .map { index, element in
                let stringValue = "\(element.value)"
                let type = element.value is Bool ? "Bool" : "String"
                return RequestBodyItem(key: element.key, value: stringValue, type: type, order: index)
            }
        UserDefaults.standard.removeObject(forKey: "customRequestBody")
        UserDefaults.standard.removeObject(forKey: "requestBodyOrder")
        alertMessage = "Request body reset to default"
        showAlert = true
    }
}

#Preview {
    AppSettingsView()
        .environmentObject(SettingsModel())
} 
