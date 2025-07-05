//
//  AboutView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct AboutView: View {
    @State private var isCheckingForUpdate = false
    @State private var showUpdateAvailable = false
    @State private var latestVersion: String = ""
    
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
                    if let url = URL(string: "https://getnickel.site") {
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
                    if let url = URL(string: "https://getnickel.site/instances/") {
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
    }
}

#Preview {
    AboutView()
} 