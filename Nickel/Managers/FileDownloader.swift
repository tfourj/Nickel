//
//  FileDownloader.swift
//  Nickel
//
//  Created by TfourJ on 11. 2. 25.
//

import Foundation
import UIKit

class FileDownloader: NSObject, URLSessionDownloadDelegate {
    static let shared = FileDownloader()
    var settings: SettingsModel = SettingsModel()

    // Add progress handler type
    typealias ProgressHandler = (Double, Double) -> Void
    private var progressHandler: ProgressHandler?

    enum DownloadType {
        case video
        case image
        case audio
    }

    private lazy var session: URLSession = {
        let config = !settings.disableBGDownloads
            ? URLSessionConfiguration.background(withIdentifier: "\(Bundle.main.bundleIdentifier ?? "com.tfourj.Nickel").filedownloader")
            : .default
        logOutput("disableBGD state: \(settings.disableBGDownloads)")
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var downloadContinuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var downloadTask: URLSessionDownloadTask?
    private var downloadType: DownloadType?
    private var targetURL: URL?
    private var providedMediaType: String?

    func downloadFile(from url: URL, type: DownloadType, onProgress: ProgressHandler? = nil, filename: String? = nil, mediaType: String? = nil, skipTempCleanup: Bool = false) async throws -> URL {
        if !skipTempCleanup {
            clearTempFolder()
        }
        
        downloadType = type
        progressHandler = onProgress
        providedMediaType = mediaType

        let tempDir = FileManager.default.temporaryDirectory

        // Use provided mediaType if available, otherwise fetch Content-Type from header
        var contentType: String? = mediaType
        if mediaType == nil {
            if let httpResponse = try? await fetchContentType(from: url) {
                contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
                logOutput("Content-Type from header: \(contentType ?? "nil")")
            }
        } else {
            logOutput("Using provided mediaType from API: \(mediaType ?? "nil")")
        }

        if let filename = filename, !filename.isEmpty {
            logOutput("Using provided filename: \(filename)")
            var finalFilename = filename
            
            // Only check Content-Type and correct extension if mediaType was NOT provided
            // When mediaType is provided, use filename directly without correction
            if mediaType == nil, let contentType = contentType, let correctExt = extractExtensionFromContentType(contentType) {
                let currentExt = (filename as NSString).pathExtension.lowercased()
                if currentExt != correctExt.lowercased() {
                    logOutput("⚠️ Correcting filename extension: \(currentExt) -> \(correctExt) based on Content-Type")
                    let filenameWithoutExt = (filename as NSString).deletingPathExtension
                    finalFilename = "\(filenameWithoutExt).\(correctExt)"
                    logOutput("✅ Updated filename to: \(finalFilename)")
                }
            }
            
            targetURL = tempDir.appendingPathComponent(finalFilename)
        } else {
            // Use Content-Type or mediaType to determine file extension
            let fileExtension: String
            if let contentType = contentType, let ext = extractExtensionFromContentType(contentType) {
                fileExtension = ext
                logOutput("Using file extension from \(mediaType != nil ? "provided mediaType" : "Content-Type"): \(ext)")
            } else {
                // Fallback to URL extension or type-based default
                let extractedExtension = url.pathExtension
                if extractedExtension.isEmpty {
                    logOutput("⚠️ No file extension found, using fallback method")
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
                    logOutput("Using file extension from URL: \(extractedExtension)")
                }
            }
            targetURL = tempDir.appendingPathComponent(UUID().uuidString + ".\(fileExtension)")
        }
        
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()

        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
        }.0
    }
    
    /// Fetch Content-Type header using HEAD request
    private func fetchContentType(from url: URL) async throws -> HTTPURLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        return httpResponse
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadContinuation?.resume(throwing: NSError(domain: "FileDownloader", code: -999, userInfo: [NSLocalizedDescriptionKey: "Download cancelled"]))
        downloadContinuation = nil
        targetURL = nil
        downloadType = nil
        progressHandler = nil
        providedMediaType = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard var targetURL = self.targetURL, let type = self.downloadType else {
            downloadContinuation?.resume(throwing: NSError(domain: "FileDownloader", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing target URL or download type"]))
            return
        }
        
        printTempFolderContents(context: "Before moving file")
        
        // Only check Content-Type header and correct extension if mediaType was NOT provided
        // When mediaType is provided, skip Content-Type correction (use API values directly)
        if providedMediaType == nil,
           let httpResponse = downloadTask.response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            logOutput("Content-Type header: \(contentType)")
            
            // Extract extension from Content-Type (e.g., "audio/mpeg" -> "mp3", "video/mp4" -> "mp4")
            if let correctExtension = extractExtensionFromContentType(contentType) {
                let currentExtension = targetURL.pathExtension.lowercased()
                
                if currentExtension != correctExtension.lowercased() {
                    logOutput("⚠️ Correcting file extension: \(currentExtension) -> \(correctExtension) based on Content-Type")
                    
                    // Create new filename with correct extension
                    let filenameWithoutExt = targetURL.deletingPathExtension().lastPathComponent
                    let newFilename = "\(filenameWithoutExt).\(correctExtension)"
                    let tempDir = FileManager.default.temporaryDirectory
                    targetURL = tempDir.appendingPathComponent(newFilename)
                    self.targetURL = targetURL
                    
                    logOutput("✅ Updated filename to: \(newFilename)")
                }
            }
        } else if providedMediaType != nil {
            logOutput("Skipping Content-Type correction - using API-provided mediaType and filename directly")
        }
        
        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            
            try FileManager.default.moveItem(at: location, to: targetURL)
            logOutput("✅ \(type) file moved successfully to: \(targetURL)")
            
            // Verify the move was successful
            if FileManager.default.fileExists(atPath: targetURL.path) {
                logOutput("✅ \(type) file exists at: \(targetURL)")
                
                // Check if the file is 0 bytes
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: targetURL.path)
                let fileSize = fileAttributes[.size] as? Int64 ?? 0
                
                if fileSize == 0 {
                    let error = NSError(domain: "FileDownloader", code: -4, userInfo: [NSLocalizedDescriptionKey: "Downloaded file is 0 bytes."])
                    logOutput("⚠️ \(type) file is 0 bytes, returning error")
                    downloadContinuation?.resume(throwing: error)
                    return
                }
                
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
        self.providedMediaType = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let downloadedMB = Double(totalBytesWritten) / (1000.0 * 1000.0)
        let totalMB = Double(totalBytesExpectedToWrite) / (1000.0 * 1000.0)
        progressHandler?(downloadedMB, totalMB)
    }

    // Add handling for background session errors
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            logOutput("❌ Download task failed with error: \(error.localizedDescription)")
            
            // Check if this is a cancellation error
            let errorCode = (error as NSError).code
            let isCancellationError = errorCode == NSURLErrorCancelled // -999
            
            // If we hit an error with the background configuration (and it's not a cancellation)
            if !settings.disableBGDownloads && !isCancellationError, let originalRequest = task.originalRequest {
                logOutput("⚠️ Background download failed, attempting foreground download")
                
                // Show alert about background download failure
                showBackgroundDownloadFailureAlert()
                
                let foregroundSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                let newTask = foregroundSession.downloadTask(with: originalRequest)
                downloadTask = newTask
                newTask.resume()
                return
            }
            
            downloadContinuation?.resume(throwing: error)
            downloadContinuation = nil
            targetURL = nil
            downloadType = nil
            progressHandler = nil
            providedMediaType = nil
        }
    }
    
    // Add method to show alert when background downloads fail
    private func showBackgroundDownloadFailureAlert() {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                return
            }

            let alertController = UIAlertController(
                title: "Download Issue",
                message: "Background download isn't working due to signing method, file was downloaded with foreground download method.\n\nTo disable this error notification, please turn on Disable Background Downloads in settings.",
                preferredStyle: .alert
            )

            alertController.addAction(UIAlertAction(title: "OK", style: .default))
            rootViewController.present(alertController, animated: true)
        }
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
    
    /// Extract file extension directly from Content-Type header
    private func extractExtensionFromContentType(_ contentType: String) -> String? {
        // Remove parameters (e.g., "audio/mpeg; charset=utf-8" -> "audio/mpeg")
        let mimeType = contentType.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? contentType.lowercased()
        
        // Simple mapping: extract extension from common Content-Type patterns
        // audio/mpeg -> mp3, audio/mp4 -> m4a, video/mp4 -> mp4, etc.
        if mimeType.contains("audio/mpeg") || mimeType == "audio/mp3" {
            return "mp3"
        } else if mimeType.contains("audio/mp4") || mimeType.contains("audio/x-m4a") {
            return "m4a"
        } else if mimeType.contains("audio/aac") {
            return "aac"
        } else if mimeType.contains("audio/wav") || mimeType.contains("audio/x-wav") {
            return "wav"
        } else if mimeType.contains("audio/ogg") {
            return "ogg"
        } else if mimeType.contains("audio/flac") {
            return "flac"
        } else if mimeType.contains("audio/webm") {
            return "webm"
        } else if mimeType.contains("video/mp4") {
            return "mp4"
        } else if mimeType.contains("video/quicktime") {
            return "mov"
        } else if mimeType.contains("video/webm") {
            return "webm"
        } else if mimeType.contains("video/x-matroska") {
            return "mkv"
        } else if mimeType.contains("image/jpeg") || mimeType.contains("image/jpg") {
            return "jpg"
        } else if mimeType.contains("image/png") {
            return "png"
        } else if mimeType.contains("image/gif") {
            return "gif"
        } else if mimeType.contains("image/webp") {
            return "webp"
        }
        
        return nil
    }
}
