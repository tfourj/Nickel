import SwiftUI
import UniformTypeIdentifiers

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct PickerOption: Identifiable {
    let id: String
    let label: String
    let url: URL

    init(label: String, url: URL) {
        self.id = url.absoluteString // Use the URL as the id
        self.label = label
        self.url = url
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @State private var urlInput = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var isSuccessMessage = false
    @State private var downloadedVideoURL: IdentifiableURL?
    @State private var pickerOptions: [PickerOption] = []
    @State private var showPicker = false
    @State private var listRefreshID = UUID()

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
        .sheet(isPresented: $showPicker) {
            VStack {
                Text("Select a Download Option")
                    .font(.headline)
                    .padding()

                List(pickerOptions, id: \.id) { option in
                    Button(option.label) {
                        selectPickerOption(option)
                    }
                }
            }
            .id(listRefreshID)
            .onAppear {
                logOutput("Picker appeared with \(pickerOptions.count) options")
                listRefreshID = UUID() // Trigger a refresh
            }
        }
    }

    private func checkForSharedURL() {
        logOutput("check for sharedurl called!")
        let sharedDefaults = UserDefaults(suiteName: "group.com.tfourj.nickel")
        if let sharedURL = sharedDefaults?.string(forKey: "sharedURL"), !sharedURL.isEmpty {
            logOutput(sharedURL)
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
                let result = try await DownloadManager.shared.fetchCobaltURL(inputURL: url)
                
                switch result {
                case .success(let videoURL):
                    handleDownloadSuccess(videoURL)
                    
                case .pickerOptions(let options):
                    DispatchQueue.main.async {
                        pickerOptions = options
                        listRefreshID = UUID()  // Force list refresh
                        logOutput("Picker options: \(pickerOptions)")  // Log to verify the options are populated
                        showPicker = true
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                isSuccessMessage = false
            }
            isLoading = false
        }
    }

    private func selectPickerOption(_ option: PickerOption) {
        isLoading = true
        showPicker = false

        Task {
            do {
                // Check the file extension or MIME type
                let fileExtension = option.url.pathExtension.lowercased()
                var downloadURL: URL

                if fileExtension == "mp4" {
                    // Download video
                    downloadURL = try await DownloadManager.shared.downloadVideoFile(from: option.url)
                } else if fileExtension == "jpg" || fileExtension == "png" || fileExtension == "jpeg" {
                    // Download image
                    downloadURL = try await DownloadManager.shared.downloadImageFile(from: option.url)
                } else if fileExtension == "mp3" || fileExtension == "aac" || fileExtension == "wav" {
                    // Download audio
                    downloadURL = try await DownloadManager.shared.downloadAudioFile(from: option.url)
                } else {
                    throw NSError(domain: "Unsupported file type", code: 0, userInfo: nil)
                }

                handleDownloadSuccess(downloadURL)
            } catch {
                errorMessage = error.localizedDescription
                isSuccessMessage = false
            }
            isLoading = false
        }
    }

    private func handleDownloadSuccess(_ videoURL: URL) {
        downloadedVideoURL = IdentifiableURL(url: videoURL)
        errorMessage = "Download successful"
        isSuccessMessage = true

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

#Preview {
    ContentView()
}
