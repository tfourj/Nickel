//
//  UserInterfaceSettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct UserInterfaceSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        Form {
            Section(header: Text("Launch Behavior")) {
                Toggle(isOn: $settings.autoOpenHome) {
                    Text("Open Home Tab at Launch")
                }
            }
            
            Section(header: Text("Error Handling")) {
                Toggle(isOn: $settings.autoClearErrorMessage) {
                    Text("Auto-Clear Error Messages")
                }
            }
            
            Section(header: Text("Developer Tools")) {
                Toggle(isOn: $settings.enableConsole) {
                    Text("Enable Developer Console")
                }
                
                #if DEBUG
                Toggle(isOn: $settings.enableDebugTab) {
                    Text("Show Debug Tab")
                }
                #endif
            }
            
            Section(header: Text("Link History")) {
                Toggle(isOn: $settings.enableLinkHistory) {
                    Text("Enable Link History")
                }
                
                if settings.enableLinkHistory {
                    Stepper(value: $settings.maxLinkHistoryEntries, in: 1...100) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Max History Entries")
                            Text("\(settings.maxLinkHistoryEntries) entries")
                                .font(.footnote)
                                .foregroundColor(.gray)
                        }
                    }
                    .onChange(of: settings.maxLinkHistoryEntries) { oldValue, newValue in
                        LinkHistoryManager.shared.trimToMaxEntries()
                    }
                }
            }
        }
        .navigationTitle("User Interface")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        UserInterfaceSettingsView()
            .environmentObject(SettingsModel())
    }
}

