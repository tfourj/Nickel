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
    @AppStorage("autoSaveToPhotos") private var autoSaveToPhotos: Bool = false  // Add this line
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API Settings")) {
                    TextField("API URL", text: $customAPIURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    TextField("API Key", text: $customAPIKey)
                        .autocapitalization(.none)
                }
                
                Section(header: Text("Video Settings")) {
                    Toggle(isOn: $autoSaveToPhotos) {
                        Text("Automatically Save to Photos")
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

