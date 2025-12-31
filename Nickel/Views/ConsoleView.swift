import SwiftUI
import Combine
import UniformTypeIdentifiers

/// A simple logger that captures console output with size limits.
final class ConsoleLogger: ObservableObject {
    static let shared = ConsoleLogger()
    @Published private(set) var log: String = ""
    @Published private(set) var filteredLog: String = ""
    private var logLines: [String] = []
    private let maxLines: Int
    
    init() {
        let maxLinesSetting = UserDefaults.standard.object(forKey: "consoleMaxLines") as? Int ?? 10000
        self.maxLines = maxLinesSetting
    }
    
    /// Appends a new message to the log (always logs everything).
    func appendLog(_ message: String) {
        appendLogs([message])
    }
    
    /// Appends multiple messages to the log (always logs everything).
    func appendLogs(_ messages: [String]) {
        guard !messages.isEmpty else { return }
        DispatchQueue.main.async {
            self.logLines.append(contentsOf: messages)
            
            // Rotate if exceeding max lines (keep last maxLines)
            if self.logLines.count > self.maxLines {
                let removeCount = self.logLines.count - self.maxLines
                self.logLines.removeFirst(removeCount)
            }
            
            self.log = self.logLines.joined(separator: "\n")
            self.filteredLog = self.log
        }
    }
    
    /// Clears all logs
    func clearLogs() {
        DispatchQueue.main.async {
            self.logLines.removeAll()
            self.log = ""
            self.filteredLog = ""
        }
    }
    
    /// Applies search filter
    func applySearchFilter(_ searchText: String) {
        DispatchQueue.main.async {
            if searchText.isEmpty {
                self.filteredLog = self.log
            } else {
                let lines = self.logLines.filter { line in
                    line.localizedCaseInsensitiveContains(searchText)
                }
                self.filteredLog = lines.joined(separator: "\n")
            }
        }
    }
    
    /// Gets all log lines for export
    func getAllLogLines() -> [String] {
        return logLines
    }
}

func logOutput(_ message: String) {
    let enableConsole = UserDefaults.standard.bool(forKey: "enableConsole")
    if enableConsole {
        ConsoleLogger.shared.appendLog(message)
    }
    // Print the message to Xcode's console
    print(message)
}

/// A view that displays captured console output with filtering, search, and export.
struct ConsoleView: View {
    @StateObject private var logger = ConsoleLogger.shared
    @EnvironmentObject var settings: SettingsModel
    @State private var searchText: String = ""
    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var highlightText: String = ""
    @State private var isExporting = false
    @State private var exportProgress: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and filter bar
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search logs...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: searchText) { _, newValue in
                                logger.applySearchFilter(newValue)
                                highlightText = newValue
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                highlightText = ""
                                logger.applySearchFilter("")
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .background(Color(UIColor.systemBackground))
                
                // Log content with highlighting and selection support
                SelectableTextView(
                    text: logger.filteredLog.isEmpty ? "No logs yet..." : logger.filteredLog,
                    highlightText: highlightText
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Console")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            exportLogs()
                        }) {
                            Label("Export Logs", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: {
                            logger.clearLogs()
                        }) {
                            Label("Clear Logs", systemImage: "trash")
                        }
                        
                        Button(action: {
                            UIPasteboard.general.string = logger.filteredLog
                        }) {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let exportURL = exportURL, FileManager.default.fileExists(atPath: exportURL.path) {
                    ShareSheet(activityItems: [exportURL])
                } else {
                    // This shouldn't happen, but show error if it does
                    VStack {
                        Text("Export file not ready")
                            .padding()
                    }
                }
            }
            .overlay {
                if isExporting {
                    // Progress overlay
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            
                            Text(exportProgress.isEmpty ? "Exporting logs..." : exportProgress)
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .padding(24)
                        .background(Color(UIColor.systemBackground).opacity(0.95))
                        .cornerRadius(16)
                        .shadow(radius: 10)
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(.dark)
    }
    
    private func exportLogs() {
        Task {
            await MainActor.run {
                isExporting = true
                exportProgress = "Preparing logs..."
            }
            
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let timestamp = DateFormatter.logTimestamp.string(from: Date())
                
                await MainActor.run {
                    exportProgress = "Collecting log data..."
                }
                
                // Create log file content
                let logContent = logger.getAllLogLines().joined(separator: "\n")
                
                await MainActor.run {
                    exportProgress = "Writing file..."
                }
                
                // Save as .txt file
                let txtURL = tempDir.appendingPathComponent("nickel_logs_\(timestamp).txt")
                
                // Remove existing file if present
                if FileManager.default.fileExists(atPath: txtURL.path) {
                    try? FileManager.default.removeItem(at: txtURL)
                }
                
                // Write file atomically
                try logContent.write(to: txtURL, atomically: true, encoding: .utf8)
                
                await MainActor.run {
                    exportProgress = "Verifying file..."
                }
                
                // Verify file exists and is readable
                var fileReady = false
                var attempts = 0
                while !fileReady && attempts < 20 {
                    if FileManager.default.fileExists(atPath: txtURL.path) {
                        if let fileContent = try? String(contentsOf: txtURL, encoding: .utf8), !fileContent.isEmpty {
                            fileReady = true
                        }
                    }
                    if !fileReady {
                        attempts += 1
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
                    }
                }
                
                guard fileReady else {
                    throw NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "File not ready for sharing"])
                }
                
                await MainActor.run {
                    exportProgress = "Finalizing..."
                }
                
                // Small delay to ensure file system has registered the file
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2 second delay
                
                // Final verification
                guard FileManager.default.fileExists(atPath: txtURL.path),
                      let _ = try? String(contentsOf: txtURL, encoding: .utf8) else {
                    throw NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "File verification failed"])
                }
                
                await MainActor.run {
                    self.exportURL = txtURL
                    self.isExporting = false
                    self.exportProgress = ""
                    // Small delay before showing sheet to ensure UI is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showExportSheet = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.exportProgress = ""
                    logOutput("❌ Error exporting logs: \(error.localizedDescription)")
                }
            }
        }
    }
    
}

/// Selectable text view with highlighting support
struct SelectableTextView: UIViewRepresentable {
    let text: String
    let highlightText: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        let attributedString = NSMutableAttributedString(string: text)
        
        // Apply base attributes
        let range = NSRange(location: 0, length: text.count)
        attributedString.addAttributes([
            .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: UIColor.label
        ], range: range)
        
        // Apply highlighting if search text is provided
        if !highlightText.isEmpty {
            let searchLower = highlightText.lowercased()
            let textLower = text.lowercased()
            var searchRange = textLower.startIndex
            
            while let range = textLower.range(of: searchLower, range: searchRange..<textLower.endIndex) {
                let nsRange = NSRange(range, in: textLower)
                attributedString.addAttributes([
                    .backgroundColor: UIColor.systemYellow,
                    .foregroundColor: UIColor.label
                ], range: nsRange)
                searchRange = range.upperBound
            }
        }
        
        textView.attributedText = attributedString
        
        // Scroll to top if text changed significantly
        if textView.contentOffset.y > 0 && text.count < textView.attributedText.length {
            textView.setContentOffset(.zero, animated: false)
        }
    }
}

/// Share sheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

#Preview {
    ConsoleView()
        .environmentObject(SettingsModel())
}
