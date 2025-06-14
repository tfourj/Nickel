//
//  SettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI
import Foundation

struct RequestBodyItem: Identifiable {
    let id = UUID()
    var key: String
    var value: String
    var type: String
    var order: Int
}

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
    @State private var requestBodyItems: [RequestBodyItem] = []
    
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
                var items: [RequestBodyItem] = []
                
                // Check if we have order information stored
                if let orderData = UserDefaults.standard.data(forKey: "requestBodyOrder"),
                   let orderArray = try? JSONSerialization.jsonObject(with: orderData) as? [String] {
                    // Load items in stored order
                    for (index, key) in orderArray.enumerated() {
                        if let value = jsonObject[key] {
                            let stringValue = "\(value)"
                            let type = value is Bool ? "Bool" : "String"
                            items.append(RequestBodyItem(key: key, value: stringValue, type: type, order: index))
                        }
                    }
                    // Add any new items that weren't in the order list
                    for (key, value) in jsonObject {
                        if !orderArray.contains(key) {
                            let stringValue = "\(value)"
                            let type = value is Bool ? "Bool" : "String"
                            items.append(RequestBodyItem(key: key, value: stringValue, type: type, order: items.count))
                        }
                    }
                } else {
                    // Fallback to alphabetical order if no order data exists
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
                logOutput("Returning custom request body values")
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
                logOutput("Returning default request body values")
            }
        }
    }
    
    private func saveRequestBody() {
        var jsonObject: [String: Any] = [:]
        var orderArray: [String] = []
        
        // Sort items by order before saving
        let sortedItems = requestBodyItems.sorted { $0.order < $1.order }
        
        for item in sortedItems {
            orderArray.append(item.key)
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
        
        // Save the JSON data
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            UserDefaults.standard.set(jsonString, forKey: "customRequestBody")
            
            // Save the order information
            if let orderData = try? JSONSerialization.data(withJSONObject: orderArray, options: []) {
                UserDefaults.standard.set(orderData, forKey: "requestBodyOrder")
            }
            
            alertMessage = "Settings saved successfully"
        } else {
            alertMessage = "Failed to save request body"
        }
        showAlert = true
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
                    #if DEBUG
                    Toggle(isOn: $settings.enableDebugTab) {
                        Text("Show Debug Tab")
                    }
                    #endif
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
                        ForEach(requestBodyItems.sorted { $0.order < $1.order }) { item in
                            if let index = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                                GeometryReader { geometry in
                                    HStack(spacing: 0) {
                                        // Key field - left 35% of width
                                        TextField("Key", text: Binding(
                                            get: { requestBodyItems.first(where: { $0.id == item.id })?.key ?? "" },
                                            set: { newValue in
                                                if let idx = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                                                    requestBodyItems[idx].key = newValue
                                                }
                                            }
                                        ))
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(width: geometry.size.width * 0.35, alignment: .leading)
                                        
                                        // Type selector - using fixed width
                                        Menu {
                                            ForEach(valueTypes, id: \.self) { type in
                                                Button(type) {
                                                    if let idx = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                                                        requestBodyItems[idx].type = type
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Text(requestBodyItems.first(where: { $0.id == item.id })?.type ?? "String")
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
                                            if let currentItem = requestBodyItems.first(where: { $0.id == item.id }),
                                               currentItem.type == "Bool" {
                                                Toggle("", isOn: Binding(
                                                    get: { 
                                                        guard let currentItem = requestBodyItems.first(where: { $0.id == item.id }) else { return false }
                                                        let value = currentItem.value.lowercased()
                                                        return value == "true" || value == "1" 
                                                    },
                                                    set: { newValue in
                                                        if let idx = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                                                            let currentValue = requestBodyItems[idx].value.lowercased()
                                                            let isCurrentlyTrue = currentValue == "true" || currentValue == "1"
                                                            
                                                            if newValue != isCurrentlyTrue {
                                                                // Preserve numeric format if that's what was used
                                                                if currentValue == "1" || currentValue == "0" {
                                                                    requestBodyItems[idx].value = newValue ? "1" : "0"
                                                                } else {
                                                                    requestBodyItems[idx].value = newValue ? "true" : "false"
                                                                }
                                                            }
                                                        }
                                                    }
                                                ))
                                                .labelsHidden()
                                            } else {
                                                TextField("Value", text: Binding(
                                                    get: { requestBodyItems.first(where: { $0.id == item.id })?.value ?? "" },
                                                    set: { newValue in
                                                        if let idx = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                                                            requestBodyItems[idx].value = newValue
                                                        }
                                                    }
                                                ))
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
                        }
                        .onDelete { indices in
                            let sortedItems = requestBodyItems.sorted { $0.order < $1.order }
                            let itemsToDelete = indices.map { sortedItems[$0] }
                            
                            for itemToDelete in itemsToDelete {
                                if let index = requestBodyItems.firstIndex(where: { $0.id == itemToDelete.id }) {
                                    requestBodyItems.remove(at: index)
                                }
                            }
                            
                            // Reorder remaining items to maintain sequence
                            for (newOrder, item) in requestBodyItems.sorted(by: { $0.order < $1.order }).enumerated() {
                                if let index = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                                    requestBodyItems[index].order = newOrder
                                }
                            }
                        }
                        .onMove { source, destination in
                            let sortedItems = requestBodyItems.sorted { $0.order < $1.order }
                            var newOrderedItems = sortedItems
                            newOrderedItems.move(fromOffsets: source, toOffset: destination)
                            
                            // Update order values in the original array
                            for (newOrder, movedItem) in newOrderedItems.enumerated() {
                                if let index = requestBodyItems.firstIndex(where: { $0.id == movedItem.id }) {
                                    requestBodyItems[index].order = newOrder
                                }
                            }
                        }
                        
                        Button("Add New Item") {
                            let newOrder = (requestBodyItems.map { $0.order }.max() ?? -1) + 1
                            requestBodyItems.append(RequestBodyItem(key: "", value: "", type: "String", order: newOrder))
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


