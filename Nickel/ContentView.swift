//
//  ContentView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI
import UniformTypeIdentifiers

struct IdentifiableURL: Identifiable {
    let id = UUID()  // Unique identifier
    let url: URL
}

struct ContentView: View {
    @State private var urlInput = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var downloadedVideoURL: IdentifiableURL?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Enter video URL", text: $urlInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .padding()
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
                
                Button(action: downloadVideo) {
                    Text("Download Video")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .disabled(isLoading)
            }
            .navigationTitle("Nickel")
            .sheet(item: $downloadedVideoURL) { identifiableURL in
                ShareSheet(activityItems: [identifiableURL.url])
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func downloadVideo() {
        guard let url = URL(string: urlInput),
              UIApplication.shared.canOpenURL(url) else {
            errorMessage = "Invalid URL"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                let videoURL = try await DownloadManager.shared.fetchCobaltURL(inputURL: url)
                downloadedVideoURL = IdentifiableURL(url: videoURL)
                print("Download sucessfull")
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

