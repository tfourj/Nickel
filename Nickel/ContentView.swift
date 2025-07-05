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
    @State private var selectedDownloadMode: String = "auto"
    @State private var shouldCancelDownload = false
    
    @EnvironmentObject var settings: SettingsModel

    init() {
        if UserDefaults.standard.bool(forKey: "rememberPickerDownloadOption") {
            if let savedMode = UserDefaults.standard.string(forKey: "selectedDownloadMode") {
                _selectedDownloadMode = State(initialValue: savedMode)
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 10) {
                HStack {
                    
                    Image("Nickel")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                    
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
                    
                    // Stop Download button
                    if isLoading {
                        Button(action: {
                            shouldCancelDownload = true
                            FileDownloader.shared.cancelDownload()
                            isLoading = false
                            errorMessage = "Download cancelled"
                            isSuccessMessage = false
                        }) {
                            HStack {
                                Image(systemName: "stop.circle.fill")
                                    .font(.title2)
                                Text("Cancel")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.red, lineWidth: 2)
                            )
                        }
                        .padding(.bottom, 4)
                    }
                    
                    // Picker for download mode overwrite
                    Picker("Download Mode", selection: $selectedDownloadMode) {
                        Text("Auto").tag("auto")
                        Text("Audio").tag("audio")
                        Text("Mute").tag("mute")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
                    .onChange(of: selectedDownloadMode) {
                        if settings.rememberPickerDownloadOption {
                            logOutput("Picker option set to: \(selectedDownloadMode)")
                            UserDefaults.standard.set(selectedDownloadMode, forKey: "selectedDownloadMode")
                        }
                    }
                    
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
                    Button(action: { downloadVideo(mode: selectedDownloadMode) }) {
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
        
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                if settings.autoClearErrorMessage {
                    errorMessage = ""
                }
            }
        }
        
        .onOpenURL { url in
            // Extract the URL from the scheme and set it to urlField
            if url.scheme == "nickel", url.host == "download",
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let linkItem = queryItems.first(where: { $0.name == "url" }),
               let sharedLink = linkItem.value {
                logOutput("App opened using url scheme. link: \(sharedLink)")
                urlInput = sharedLink
                downloadVideo(mode: selectedDownloadMode)
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowMessageUI"))) { notification in
            if let text = notification.userInfo?["text"] as? String {
                DispatchQueue.main.async {
                    self.errorMessage = text
                    self.isSuccessMessage = true
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
    }

    private func downloadVideo(mode: String = "auto") {
        guard let url = URL(string: urlInput),
              UIApplication.shared.canOpenURL(url) else {
            errorMessage = "Invalid URL"
            isSuccessMessage = false
            return
        }
        
        isLoading = true
        shouldCancelDownload = false
        errorMessage = ""
        
        Task {
            do {
                let result = try await DownloadManager.shared.fetchCobaltURL(
                    inputURL: url,
                    downloadModeOverride: mode,
                    shouldCancel: { shouldCancelDownload }
                )
                
                // Check again after fetchCobaltURL returns, in case cancel was pressed during async
                if shouldCancelDownload {
                    isLoading = false
                    errorMessage = "Download cancelled"
                    isSuccessMessage = false
                    return
                }
                
                switch result {
                case .success(let videoURL, let filename):
                    let progressHandler: FileDownloader.ProgressHandler = { downloaded, total in
                        DispatchQueue.main.async {
                            self.errorMessage = total <= 0 
                                ? "Downloading: \(String(format: "%.1f", downloaded)) MB"
                                : "Downloading: \(String(format: "%.1f", downloaded))/\(String(format: "%.1f", total)) MB"
                            self.isSuccessMessage = true
                        }
                    }
                    let downloadURL = try await FileDownloader.shared.downloadFile(from: videoURL, type: .video, onProgress: progressHandler, filename: filename)
                    handleDownloadSuccess(downloadURL)
                    
                case .pickerOptions(let options):
                    DispatchQueue.main.async {
                        errorMessage = "Please select option from menu"
                        NotificationManager.sendDownloadCompleteNotification(text: "Please open app to download file from picker options")
                        isSuccessMessage = true
                        pickerOptions = options
                        listRefreshID = UUID()  // Force list refresh
                        logOutput("Picker options: \(pickerOptions)")  // Log to verify the options are populated
                        showPicker = true
                    }
                    
                case .localProcessing(let localResponse):
                    DispatchQueue.main.async {
                        errorMessage = "Processing \(localResponse.type) locally..."
                        isSuccessMessage = true
                    }
                    
                    let progressHandler: (String) -> Void = { message in
                        DispatchQueue.main.async {
                            self.errorMessage = message
                            self.isSuccessMessage = true
                        }
                    }
                    
                    let processedFileURL = try await LocalProcessingManager.shared.processLocalResponse(localResponse, progressHandler: progressHandler)
                    handleDownloadSuccess(processedFileURL)
                }
            } catch {
                if shouldCancelDownload {
                    errorMessage = "Download cancelled"
                    isSuccessMessage = false
                } else {
                    errorMessage = error.localizedDescription
                    isSuccessMessage = false
                }
                urlInput = ""
            }
            isLoading = false
        }
    }

    private func selectPickerOption(_ option: PickerOption) {
        isLoading = true
        showPicker = false
        errorMessage = ""

        Task {
            do {
                let fileExtension = option.url.pathExtension.lowercased()
                let label = option.label.lowercased()
                var downloadURL: URL
                var downloadType: FileDownloader.DownloadType = .video

                let progressHandler: FileDownloader.ProgressHandler = { downloaded, total in
                    DispatchQueue.main.async {
                        self.errorMessage = total <= 0 
                            ? "Downloading: \(String(format: "%.1f", downloaded)) MB"
                            : "Downloading: \(String(format: "%.1f", downloaded))/\(String(format: "%.1f", total)) MB"
                        self.isSuccessMessage = true
                    }
                }

                if ["mp4", "mov", "webm", "mkv"].contains(fileExtension) || label.contains("video") {
                    downloadType = .video
                } else if ["jpg", "png", "jpeg", "gif", "bmp", "webp"].contains(fileExtension) || label.contains("photo") || label.contains("image") {
                    downloadType = .image
                } else if ["mp3", "aac", "wav", "m4a", "ogg"].contains(fileExtension) || label.contains("audio") || label.contains("sound") {
                    downloadType = .audio
                } else {
                    throw NSError(domain: "Unsupported file type", code: 0, userInfo: nil)
                }

                downloadURL = try await FileDownloader.shared.downloadFile(from: option.url, type: downloadType, onProgress: progressHandler)
                handleDownloadSuccess(downloadURL)
            } catch {
                errorMessage = error.localizedDescription
                isSuccessMessage = false
                urlInput = ""
            }
            isLoading = false
        }
    }

    private func handleDownloadSuccess(_ fileURL: URL) {
        downloadedVideoURL = IdentifiableURL(url: fileURL)
        errorMessage = "Download successful"
        isSuccessMessage = true
        urlInput = ""

        // Determine file type by extension for saving or sharing
        let ext = fileURL.pathExtension.lowercased()
        let isImage = ["jpg", "jpeg", "png", "gif", "bmp", "webp"].contains(ext)
        let isVideo = ["mp4", "mov", "webm", "mkv"].contains(ext)

        if settings.autoSaveToPhotos && (isImage || isVideo) {
            if isImage {
                if let image = UIImage(contentsOfFile: fileURL.path) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    logOutput("Saving image directly to Photos \(image)")
                    errorMessage = "Image saved to Photos"
                    NotificationManager.sendDownloadCompleteNotification(text: errorMessage)
                    isSuccessMessage = true
                }
            } else if isVideo {
                UISaveVideoAtPathToSavedPhotosAlbum(fileURL.path, nil, nil, nil)
                logOutput("Saving video directly to Photos \(fileURL)")
                errorMessage = "Video saved to Photos"
                NotificationManager.sendDownloadCompleteNotification(text: errorMessage)
                isSuccessMessage = true
            }
        } else {
            DispatchQueue.main.async {
                logOutput("Opening share sheet for file")
                NotificationManager.sendDownloadCompleteNotification(text: "File downloaded, open app to proceed")
                downloadedVideoURL = IdentifiableURL(url: fileURL)
                showShareSheet()
            }
        }
    }

    private func pasteURL() {
        if let clipboardText = UIPasteboard.general.string {
            urlInput = clipboardText
            if (!settings.disableAutoPasteRun) {
                downloadVideo(mode: selectedDownloadMode)
            }
        } else {
            errorMessage = "Clipboard is empty"
            isSuccessMessage = false
        }
    }

    private func showShareSheet() {
        if let downloadedVideoURL = downloadedVideoURL {
            (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController?.present(UIActivityViewController(activityItems: [downloadedVideoURL.url], applicationActivities: nil), animated: true)
            }
        }
}

#Preview {
    ContentView()
}
