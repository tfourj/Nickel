//
//  ProcessingSettingsView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct ProcessingSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        Form {
            Section(header: Text("Video Processing Engine")) {
                Toggle(isOn: $settings.useFFmpegForProcessing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use FFmpeg for Processing")
                        Text("Use FFmpeg instead of AVExport for video processing")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            if settings.useFFmpegForProcessing {
                Section(header: Text("FFmpeg Debugging")) {
                    Toggle(isOn: $settings.enableFFmpegLogs) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable FFmpeg Logs")
                            Text("⚠️ Warning: Enabling FFmpeg logs significantly slows down processing performance")
                                .font(.footnote)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            Section(footer: Text("FFmpeg provides better format support and more control over video processing. AVExport is the default iOS framework and may have limitations with certain formats.")) {
                EmptyView()
            }
        }
        .navigationTitle("Processing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        ProcessingSettingsView()
            .environmentObject(SettingsModel())
    }
}

