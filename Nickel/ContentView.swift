import SwiftUI
import UniformTypeIdentifiers

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @State private var urlInput = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var isSuccessMessage = false
    @State private var downloadedVideoURL: IdentifiableURL?

    @AppStorage("autoSaveToPhotos") private var autoSaveToPhotos: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                HStack {
                    TextField("Enter video URL", text: $urlInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .padding()
                    
                    // Right-side button (Paste or Clear)
                    Button(action: {
                        if urlInput.isEmpty {
                            pasteURL()
                        } else {
                            urlInput = ""
                        }
                    }) {
                        Image(systemName: urlInput.isEmpty ? "doc.on.clipboard" : "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .padding(.trailing, 10)
                }
                
                Button(action: downloadVideo) {
                    Label("Download", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(isLoading)
                .padding(.horizontal)
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(isSuccessMessage ? .white : .red)
                        .padding()
                }
            }
            .navigationTitle("Nickel")
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                errorMessage = ""
                checkForSharedURL()
            }
        }
    }

    private func checkForSharedURL() {
        print("check for sharedurl called!")
        let sharedDefaults = UserDefaults(suiteName: "group.com.tfourj.nickel")
        if let sharedURL = sharedDefaults?.string(forKey: "sharedURL"), !sharedURL.isEmpty {
            print(sharedURL)
            urlInput = sharedURL
            sharedDefaults?.removeObject(forKey: "sharedURL") // Clear it after use
            downloadVideo() // Auto-start download
        }
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
                urlInput = ""
                
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
                urlInput = ""
            }
            isLoading = false
        }
    }

    private func pasteURL() {
        if let clipboardText = UIPasteboard.general.string {
            urlInput = clipboardText
            downloadVideo()
        } else {
            errorMessage = "Clipboard is empty"
            isSuccessMessage = false
        }
    }

    private func showShareSheet() {
        if let downloadedVideoURL = downloadedVideoURL {
            let shareSheet = ShareSheet(activityItems: [downloadedVideoURL.url])
            
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
