//
//  DownloadBehaviorSettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct DownloadBehaviorSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        Form {
            Section(header: Text("Auto-Save")) {
                Toggle(isOn: $settings.autoSaveToPhotos) {
                    Text("Auto-Save to Photos")
                }
            }
            
            Section(header: Text("Download Options")) {
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
                
                Toggle(isOn: $settings.askDownloadOptionOnShareSheet) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask Download Option on Share Sheet")
                        Text("Prompt for download mode when opening links via share sheet")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Section(header: Text("Background Downloads")) {
                Toggle(isOn: $settings.disableBGDownloads) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Disable Background Downloads")
                        Text("Enable if using on device IPA signers")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .navigationTitle("Download Behavior")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        DownloadBehaviorSettingsView()
            .environmentObject(SettingsModel())
    }
}

