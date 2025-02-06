//
//  ContentView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI
import UniformTypeIdentifiers

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @State private var urlInput = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var isSuccessMessage = false
    @State private var downloadedVideoURL: IdentifiableURL?
    
    @AppStorage("autoSaveToPhotos") private var autoSaveToPhotos: Bool = false  // Accessing autoSave setting
    
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
                        .foregroundColor(isSuccessMessage ? .white : .red)
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
        }
        .preferredColorScheme(.dark)
    }
    
    private func downloadVideo() {
        guard let url = URL(string: urlInput),
              UIApplication.shared.canOpenURL(url) else {
            errorMessage = "Invalid URL"
            isSuccessMessage = false
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                let videoURL = try await DownloadManager.shared.fetchCobaltURL(inputURL: url)
                downloadedVideoURL = IdentifiableURL(url: videoURL)
                errorMessage = "Download successful"
                isSuccessMessage = true
                urlInput = ""  // Clear input field
                
                // If autoSaveToPhotos is enabled, save video directly to Photos
                if autoSaveToPhotos {
                    UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, nil, nil, nil)
                    errorMessage = "Saved to Photos"
                    isSuccessMessage = true
                } else {
                    DispatchQueue.main.async {
                        downloadedVideoURL = IdentifiableURL(url: videoURL)
                        showShareSheet()
                    }

                }
                
            } catch {
                errorMessage = error.localizedDescription
                isSuccessMessage = false
            }
            isLoading = false
        }
    }
    
    private func showShareSheet() {
        if let downloadedVideoURL = downloadedVideoURL {
            // Trigger ShareSheet in your other file
            let shareSheet = ShareSheet(activityItems: [downloadedVideoURL.url])
            
            // Manually present the ShareSheet here
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let topController = scene.windows.first?.rootViewController {
                let hostingController = UIHostingController(rootView: shareSheet)
                topController.present(hostingController, animated: true, completion: nil)
                errorMessage = "Share sheet opened"
                isSuccessMessage = true
            }
        }
    }
}
