//
//  FileDownloader.swift
//  Nickel
//
//  Created by TfourJ on 11. 2. 25.
//

import Foundation

class FileDownloader: NSObject, URLSessionDownloadDelegate {
    static let shared = FileDownloader()
    
    // Add progress handler type
    typealias ProgressHandler = (Double, Double) -> Void
    private var progressHandler: ProgressHandler?

    enum DownloadType {
        case video
        case image
        case audio
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var downloadContinuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadType: DownloadType?
    private var targetURL: URL?

    func downloadFile(from url: URL, type: DownloadType, onProgress: ProgressHandler? = nil) async throws -> URL {
        clearTempFolder()
        
        downloadType = type
        progressHandler = onProgress
        
        // Try to extract the file extension from the URL
        let extractedExtension = url.pathExtension
        let fileExtension: String

        if extractedExtension.isEmpty {
            // Fallback to hardcoded extensions if extraction fails
            switch type {
            case .video:
                fileExtension = "mp4"
            case .image:
                fileExtension = "jpg"
            case .audio:
                fileExtension = "mp3"
            }
        } else {
            fileExtension = extractedExtension
            logOutput("Automatically fetched file extension: \(extractedExtension)")
        }

        let tempDir = FileManager.default.temporaryDirectory
        targetURL = tempDir.appendingPathComponent(UUID().uuidString + ".\(fileExtension)")
        
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()

        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
        }.0
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadContinuation?.resume(throwing: NSError(domain: "FileDownloader", code: -999, userInfo: [NSLocalizedDescriptionKey: "Download cancelled"]))
        downloadContinuation = nil
        targetURL = nil
        downloadType = nil
        progressHandler = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let targetURL = self.targetURL, let type = self.downloadType else {
            downloadContinuation?.resume(throwing: NSError(domain: "FileDownloader", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing target URL or download type"]))
            return
        }
        
        printTempFolderContents(context: "Before moving file")
        
        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            
            try FileManager.default.moveItem(at: location, to: targetURL)
            logOutput("✅ \(type) file moved successfully to: \(targetURL)")
            
            // Verify the move was successful
            if FileManager.default.fileExists(atPath: targetURL.path) {
                logOutput("✅ \(type) file exists at: \(targetURL)")
                if let response = downloadTask.response {
                    downloadContinuation?.resume(returning: (targetURL, response))
                } else {
                    downloadContinuation?.resume(throwing: URLError(.badServerResponse))
                }
            } else {
                let error = NSError(domain: "FileDownloader", code: -2, userInfo: [NSLocalizedDescriptionKey: "File not found at target location after move"])
                logOutput("⚠️ \(type) file does NOT exist at expected location!")
                downloadContinuation?.resume(throwing: error)
            }
        } catch {
            logOutput("❌ Error moving \(type) file: \(error.localizedDescription)")
            downloadContinuation?.resume(throwing: error)
        }
        
        printTempFolderContents(context: "After moving file")
        downloadContinuation = nil
        self.targetURL = nil
        self.downloadType = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let downloadedMB = Double(totalBytesWritten) / (1000.0 * 1000.0)
        let totalMB = Double(totalBytesExpectedToWrite) / (1000.0 * 1000.0)
        progressHandler?(downloadedMB, totalMB)
    }

    private func clearTempFolder() {
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            logOutput("🧹 Temp folder cleared. Removed \(files.count) files.")
        } catch {
            logOutput("❌ Error clearing temp folder: \(error.localizedDescription)")
        }
    }
    
    private func printTempFolderContents(context: String) {
        let tempDir = FileManager.default.temporaryDirectory
        do {
            let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            logOutput("📂 \(context): Temp folder contains \(files.count) files:")
            for file in files {
                logOutput("  - \(file.lastPathComponent)")
            }
        } catch {
            logOutput("❌ Error accessing temp folder: \(error.localizedDescription)")
        }
    }
}
