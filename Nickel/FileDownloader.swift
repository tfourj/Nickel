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

    func downloadFile(from url: URL, type: DownloadType, onProgress: ProgressHandler? = nil, filename: String? = nil) async throws -> URL {
        clearTempFolder()
        
        downloadType = type
        progressHandler = onProgress

        let tempDir = FileManager.default.temporaryDirectory

        if let filename = filename, !filename.isEmpty {
            logOutput("Using provided filename: \(filename)")
            targetURL = tempDir.appendingPathComponent(filename)
        } else {
            // Fallback to generating a filename
            let extractedExtension = url.pathExtension
            let fileExtension: String

            if extractedExtension.isEmpty {
                logOutput("⚠️ No file extension found in URL, using fallback method")
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
            targetURL = tempDir.appendingPathComponent(UUID().uuidString + ".\(fileExtension)")
        }
        
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
                
                // Check if the file is 0 bytes
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: targetURL.path)
                let fileSize = fileAttributes[.size] as? Int64 ?? 0
                
                if fileSize == 0 {
                    let error = NSError(domain: "FileDownloader", code: -4, userInfo: [NSLocalizedDescriptionKey: "Downloaded file is 0 bytes \n\n Try to enable youtubeHLS in request body settings and retry \n (Note that this solution may not work in all cases)."])
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
}
