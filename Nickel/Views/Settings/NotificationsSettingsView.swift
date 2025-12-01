//
//  NotificationsSettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct NotificationsSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        Form {
            Section(header: Text("Download Notifications")) {
                Toggle(isOn: $settings.disableNotifications) {
                    Text("Disable Download Notifications")
                }
            }
            
            Section(footer: Text("Notifications help you track download progress and completion status.")) {
                EmptyView()
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        NotificationsSettingsView()
            .environmentObject(SettingsModel())
    }
}

