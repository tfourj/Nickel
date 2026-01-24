//
//  AboutView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct AboutView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var isCheckingForUpdate = false
    @State private var showUpdateAvailable = false
    @State private var latestVersion: String = ""
    @State private var tapCount = 0
    @State private var lastTapTime: Date?
    @State private var showDebugModeAlert = false
    
    var appVersion: String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "Unknown"
        }
        return version
    }
    
    var appBuild: String {
        guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "Unknown"
        }
        return build
    }
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image("Nickel")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                        .onTapGesture {
                            handleLogoTap()
                        }
                    
                    VStack(spacing: 4) {
                        Text("Nickel")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("v\(appVersion)\(appBuild != "100" ? " (\(appBuild))" : "")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("A powerful media downloader for iOS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            
            Section(header: Text("Developer")) {
                HStack {
                    Text("Developer")
                    Spacer()
                    Text("TfourJ")
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    if let url = URL(string: "https://github.com/TfourJ") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Text("GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Section(header: Text("Support")) {
                Button(action: {
                    if let url = URL(string: "https://getnickel.app") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Text("Website")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.blue)
                    }
                }
                
                Button(action: {
                    if let url = URL(string: "https://getnickel.app/instances/") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Text("Browse Instances")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.blue)
                    }
                }
                                Button(action: {
                    if let url = URL(string: "https://getnickel.app/discord") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Text("Discord")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.blue)
                    }
                }
            }
            
            Section(header: Text("Legal")) {
                Button(action: {
                    if let url = URL(string: "https://github.com/TfourJ/Nickel/blob/main/LICENSE") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Text("License")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .alert("Debug Mode", isPresented: $showDebugModeAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(settings.enableDebugTab ? "Debug mode enabled" : "Debug mode disabled")
        }
    }
    
    private func handleLogoTap() {
        let now = Date()
        
        if let lastTap = lastTapTime, now.timeIntervalSince(lastTap) > 0.8 {
            tapCount = 0
        }
        
        tapCount += 1
        lastTapTime = now
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        if tapCount >= 5 {
            settings.enableDebugTab.toggle()
            tapCount = 0
            lastTapTime = nil
            
            let successGenerator = UINotificationFeedbackGenerator()
            successGenerator.notificationOccurred(.success)
            
            showDebugModeAlert = true
        }
    }
}

#Preview {
    AboutView()
        .environmentObject(SettingsModel())
} 