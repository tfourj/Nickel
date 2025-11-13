//
//  RequestConfigurationSettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct RequestConfigurationSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var showRequestEditor = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var requestBodyItems: [RequestBodyItem] = []
    
    var body: some View {
        Form {
            Section(header: Text("Request Body Configuration")) {
                Button(action: {
                    loadSavedRequestBody()
                    showRequestEditor = true
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit Request Body")
                    }
                }
                
                Button(action: {
                    resetRequestBody()
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Request Body to Default")
                    }
                }
                .foregroundColor(.red)
            }
            
            Section(footer: Text("Customize the request body sent to the API. Use with caution as incorrect values may cause API errors.")) {
                EmptyView()
            }
        }
        .navigationTitle("Request Configuration")
        .navigationBarTitleDisplayMode(.inline)
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
    NavigationView {
        RequestConfigurationSettingsView()
            .environmentObject(SettingsModel())
    }
}

