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
    @AppStorage("autoClearErrorMessage") private var autoClearErrorMessage: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 10) {
                HStack {
                    
                    Image("Nickel") // Replace with your actual asset name
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80) // Adjust size as needed
                    
                    Text("Nickel")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }

                // Centered Error or Success Message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .fontWeight(.semibold)
                        .foregroundColor(isSuccessMessage ? .white : .red)
                        .padding()
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(10)
                        .multilineTextAlignment(.center) // Keep text centered
                        .frame(maxWidth: .infinity) // Stretch to center
                        .padding(.horizontal, 24) // Add padding
                        .onTapGesture {
                            // Clear error message on tap
                            errorMessage = ""
                        }
                        .onLongPressGesture {
                            // Copy error message to clipboard on long press
                            UIPasteboard.general.string = errorMessage
                            isSuccessMessage = true
                            errorMessage = "Copied!"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                errorMessage = ""
                            }
                        }
                }

                Spacer()

                // Bottom Section: Input Field + Download Button
                VStack(spacing: 15) {
                    // URL Input + Paste Button - Unified Design
                    HStack {
                        TextField("Enter video URL", text: $urlInput)
                            .textFieldStyle(PlainTextFieldStyle())
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .padding()
                            .frame(height: 50)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(10)

                        Button(action: {
                            if urlInput.isEmpty {
                                pasteURL()
                            } else {
                                urlInput = ""
                            }
                        }) {
                            Image(systemName: urlInput.isEmpty ? "doc.on.clipboard" : "xmark.circle.fill")
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.gray.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)

                    // Download Button - Unified Style
                    Button(action: downloadVideo) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                            Text("Download")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, 24)
                }
                .offset(y: -50) // Moves the input field and button up a little
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        }
        
        .preferredColorScheme(.dark)
        
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                if autoClearErrorMessage {
                    errorMessage = ""
                }
            }
        }
        
        .onOpenURL { url in
            // Extract the URL from the scheme and set it to urlField
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let linkItem = queryItems.first(where: { $0.name == "url" }),
               let sharedLink = linkItem.value {
                logOutput("App opened using url scheme. link: \(sharedLink)")
                urlInput = sharedLink
                downloadVideo()
            }
        }
        
        .sheet(isPresented: $showPicker) {
                    VStack {
                        Text("Select a Download Option")
                            .font(.headline)
                            .padding()
                        
                        List(pickerOptions, id: \.id) { option in
                            Button(action: {
                                selectPickerOption(option)
                            }) {
                                HStack {
                                    // Conditionally display either an image or a music note icon
                                    if option.label.contains("audio") {  // Check if label contains "audio"
                                        Image(systemName: "music.note")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 50, height: 50)
                                    } else {
                                        // Image preview
                                        AsyncImage(url: option.url) { image in
                                            image.resizable()
                                                .scaledToFit()
                                                .frame(width: 50, height: 50)
                                        } placeholder: {
                                            ProgressView()
                                        }
                                    }
                                    
                                    Text(option.label)
                                        .padding(.leading)
                                }
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
                        errorMessage = "Please select option from menu"
                        isSuccessMessage = true
                        pickerOptions = options
                        listRefreshID = UUID()  // Force list refresh
                        logOutput("Picker options: \(pickerOptions)")  // Log to verify the options are populated
                        showPicker = true
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

    private func selectPickerOption(_ option: PickerOption) {
        isLoading = true
        showPicker = false

        Task {
            do {
                // Check the file extension or MIME type
                let fileExtension = option.url.pathExtension.lowercased()
                let label = option.label.lowercased()
                var downloadURL: URL

                if fileExtension == "mp4" || label.contains("video") {
                    // Download video
                    downloadURL = try await DownloadManager.shared.downloadFile(from: option.url, type: .video)
                    handleDownloadSuccess(downloadURL) // Normal behavior
                } else if fileExtension == "jpg" || fileExtension == "png" || fileExtension == "jpeg" || label.contains("photo") || label.contains("image") {
                    // Download image
                    downloadURL = try await DownloadManager.shared.downloadFile(from: option.url, type: .image)
                    handleDownloadSuccess(downloadURL, isImage: true)
                } else if fileExtension == "mp3" || fileExtension == "aac" || fileExtension == "wav" || label.contains("audio") || label.contains("sound") {
                    // Download audio
                    downloadURL = try await DownloadManager.shared.downloadFile(from: option.url, type: .audio)
                    handleDownloadSuccess(downloadURL, forceShare: true) // Force share sheet
                } else {
                    throw NSError(domain: "Unsupported file type", code: 0, userInfo: nil)
                }
                
            } catch {
                errorMessage = error.localizedDescription
                isSuccessMessage = false
                urlInput = ""
            }
            isLoading = false
        }
    }

    private func handleDownloadSuccess(_ videoURL: URL, forceShare: Bool = false, isImage: Bool = false) {
        downloadedVideoURL = IdentifiableURL(url: videoURL)
        errorMessage = "Download successful"
        isSuccessMessage = true
        urlInput = ""

        if autoSaveToPhotos && !forceShare {
            if isImage {
                if let image = UIImage(contentsOfFile: videoURL.path) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    logOutput("Saving image dirrectly to Photos \(image)")
                    errorMessage = "Image saved to Photos"
                    isSuccessMessage = true
                }
            } else {
                UISaveVideoAtPathToSavedPhotosAlbum(videoURL.path, nil, nil, nil)
                logOutput("Saving video dirrectly to Photos \(videoURL)")
                errorMessage = "Video saved to Photos"
                isSuccessMessage = true
            }
        } else {
            DispatchQueue.main.async {
                logOutput("Opening share sheet for file")
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
