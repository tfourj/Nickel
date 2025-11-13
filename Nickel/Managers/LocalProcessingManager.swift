//
//  LocalProcessingManager.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import Foundation
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

// Data structures for local processing response
struct LocalProcessingResponse {
    let status: String
    let type: String
    let service: String
    let tunnel: [String]
    let output: OutputDetails
    let audio: AudioDetails?
    let isHLS: Bool?
}

struct OutputDetails {
    let url: String
    let filename: String
    let size: Int?
    let format: String?
}

struct AudioDetails {
    let url: String
    let filename: String
    let size: Int?
    let format: String?
}

class LocalProcessingManager {
    static let shared = LocalProcessingManager()
    private var shouldCancel = false
    
    enum ProcessingType: String, CaseIterable {
        case merge = "merge"
        case mute = "mute"
        case audio = "audio"
        case gif = "gif"
        case remux = "remux"
        case proxy = "proxy"
        
        var displayName: String {
            switch self {
            case .merge: return "Merge Video & Audio"
            case .mute: return "Mute Video"
            case .audio: return "Extract Audio"
            case .gif: return "Convert to GIF"
            case .remux: return "Remux Video"
            case .proxy: return "Proxy Download"
            }
        }
    }
    
    enum ProcessingError: Error, LocalizedError {
        case unsupportedType(String)
        case downloadFailed(String)
        case processingFailed(String)
        case fileNotFound(String)
        case invalidURL(String)
        
        var errorDescription: String? {
            switch self {
            case .unsupportedType(let type):
                return "Unsupported processing type: \(type)"
            case .downloadFailed(let reason):
                return "Download failed: \(reason)"
            case .processingFailed(let reason):
                return "Processing failed: \(reason)"
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .invalidURL(let url):
                return "Invalid URL: \(url)"
            }
        }
    }
    
    func processLocalResponse(_ response: LocalProcessingResponse, progressHandler: ((String) -> Void)? = nil) async throws -> URL {
        // Reset cancellation flag
        shouldCancel = false
        
        logOutput("Starting local processing for type: \(response.type)")
        progressHandler?("Starting \(response.type) processing...")
        
        guard let processingType = ProcessingType(rawValue: response.type) else {
            throw ProcessingError.unsupportedType(response.type)
        }
        
        // Download the main output file
        guard let outputURL = URL(string: response.output.url) else {
            throw ProcessingError.invalidURL(response.output.url)
        }
        
        let downloadProgressHandler: FileDownloader.ProgressHandler = { downloaded, total in
            let message = total <= 0 
                ? "Downloading: \(String(format: "%.1f", downloaded)) MB"
                : "Downloading: \(String(format: "%.1f", downloaded))/\(String(format: "%.1f", total)) MB"
            progressHandler?(message)
        }
        
        let downloadedFile = try await FileDownloader.shared.downloadFile(
            from: outputURL, 
            type: .video, 
            onProgress: downloadProgressHandler,
            filename: response.output.filename
        )
        
        // Check for cancellation after download
        if shouldCancel {
            throw CancellationError()
        }
        
        // Handle different processing types
        switch processingType {
        case .merge:
            return try await handleMerge(response: response, mainFile: downloadedFile, progressHandler: progressHandler)
        case .mute:
            return try await handleMute(response: response, mainFile: downloadedFile, progressHandler: progressHandler)
        case .audio:
            return try await handleAudio(response: response, mainFile: downloadedFile, progressHandler: progressHandler)
        case .gif:
            return try await handleGif(response: response, mainFile: downloadedFile, progressHandler: progressHandler)
        case .remux:
            return try await handleRemux(response: response, mainFile: downloadedFile, progressHandler: progressHandler)
        case .proxy:
            return try await handleProxy(response: response, mainFile: downloadedFile, progressHandler: progressHandler)
        }
    }
    
    func cancelProcessing() {
        shouldCancel = true
        logOutput("🛑 LocalProcessingManager cancellation requested")
    }
    
    private func handleMerge(response: LocalProcessingResponse, mainFile: URL, progressHandler: ((String) -> Void)?) async throws -> URL {
        logOutput("Handling merge processing")
        progressHandler?("Processing merge...")
        
        // Check for cancellation
        if shouldCancel {
            throw CancellationError()
        }
        
        guard let audio = response.audio,
              let audioURL = URL(string: audio.url) else {
            throw ProcessingError.processingFailed("Audio file not available for merge")
        }
        
        logOutput("Audio details: URL=\(audio.url), filename=\(audio.filename)")
        
        // Create a safe copy of the video file to prevent it from being deleted
        let videoFileCopy = FileManager.default.temporaryDirectory.appendingPathComponent("video_copy_\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: mainFile, to: videoFileCopy)
        logOutput("Video file copied to safe location: \(videoFileCopy)")
        
        // Check for cancellation before downloading audio
        if shouldCancel {
            try? FileManager.default.removeItem(at: videoFileCopy)
            throw CancellationError()
        }
        
        // Download audio file
        progressHandler?("Downloading audio file...")
        let audioFile = try await FileDownloader.shared.downloadFile(
            from: audioURL,
            type: .audio,
            onProgress: nil,
            filename: audio.filename,
            skipTempCleanup: true
        )
        
        logOutput("Audio file downloaded to: \(audioFile)")
        
        // Check for cancellation before merging
        if shouldCancel {
            try? FileManager.default.removeItem(at: videoFileCopy)
            throw CancellationError()
        }
        
        // Check if FFmpeg should be used
        let useFFmpeg = UserDefaults.standard.object(forKey: "useFFmpegForProcessing") as? Bool ?? true
        
        // Merge video and audio using FFmpeg or AVFoundation
        progressHandler?("Merging video and audio...")
        let result: URL
        if useFFmpeg {
            result = try await FFmpegProcessingManager.shared.mergeVideoAndAudio(
                videoURL: videoFileCopy,
                audioURL: audioFile,
                filename: response.output.filename,
                progressHandler: progressHandler,
                shouldCancel: { self.shouldCancel }
            )
        } else {
            result = try await AVExportProcessingManager.shared.mergeVideoAndAudio(
                videoURL: videoFileCopy,
                audioURL: audioFile,
                filename: response.output.filename,
                progressHandler: progressHandler,
                shouldCancel: { self.shouldCancel }
            )
        }
        
        // Clean up the temporary video copy
        try? FileManager.default.removeItem(at: videoFileCopy)
        logOutput("Cleaned up temporary video copy")
        
        return result
    }
    
    private func handleMute(response: LocalProcessingResponse, mainFile: URL, progressHandler: ((String) -> Void)?) async throws -> URL {
        logOutput("Handling mute processing")
        progressHandler?("Processing mute...")
        
        // Check if FFmpeg should be used
        let useFFmpeg = UserDefaults.standard.object(forKey: "useFFmpegForProcessing") as? Bool ?? true
        
        // Remove audio track from video using FFmpeg or AVFoundation
        if useFFmpeg {
            return try await FFmpegProcessingManager.shared.removeAudioFromVideo(
                videoURL: mainFile,
                filename: response.output.filename,
                progressHandler: progressHandler,
                shouldCancel: { self.shouldCancel }
            )
        } else {
            return try await AVExportProcessingManager.shared.removeAudioFromVideo(
                videoURL: mainFile,
                filename: response.output.filename,
                progressHandler: progressHandler,
                shouldCancel: { self.shouldCancel }
            )
        }
    }
    
    private func handleAudio(response: LocalProcessingResponse, mainFile: URL, progressHandler: ((String) -> Void)?) async throws -> URL {
        logOutput("Handling audio extraction")
        progressHandler?("Extracting audio...")
        
        // Check if the downloaded file is already an audio file
        let fileExtension = mainFile.pathExtension.lowercased()
        let audioExtensions = ["mp3", "m4a", "aac", "wav", "flac", "ogg"]
        
        if audioExtensions.contains(fileExtension) {
            logOutput("File is already an audio file (\(fileExtension)), returning directly")
            progressHandler?("Audio file ready")
            return mainFile
        }
        
        // Check if FFmpeg should be used
        let useFFmpeg = UserDefaults.standard.object(forKey: "useFFmpegForProcessing") as? Bool ?? true
        
        // Extract audio from video using FFmpeg or AVFoundation
        if useFFmpeg {
            return try await FFmpegProcessingManager.shared.extractAudioFromVideo(
                videoURL: mainFile,
                filename: response.output.filename,
                progressHandler: progressHandler,
                shouldCancel: { self.shouldCancel }
            )
        } else {
            return try await AVExportProcessingManager.shared.extractAudioFromVideo(
                videoURL: mainFile,
                filename: response.output.filename,
                progressHandler: progressHandler,
                shouldCancel: { self.shouldCancel }
            )
        }
    }
    
    private func handleGif(response: LocalProcessingResponse, mainFile: URL, progressHandler: ((String) -> Void)?) async throws -> URL {
        logOutput("Handling GIF conversion")
        progressHandler?("Converting to GIF...")
        
        // Check if file has .gif extension but is actually a video file
        let fileExtension = mainFile.pathExtension.lowercased()
        
        if fileExtension == "gif" {
            logOutput("File has .gif extension, checking if it's actually a GIF...")
            
            // First try to read as GIF image
            if UIImage(contentsOfFile: mainFile.path) != nil {
                logOutput("✅ File is actually a GIF image - saving directly")
                progressHandler?("GIF file ready")
                return mainFile
            } else {
                logOutput("File is not a readable GIF, renaming to .mp4 and saving...")
                
                // Rename the file to have .mp4 extension
                let newFilename = response.output.filename.replacingOccurrences(of: ".gif", with: ".mp4")
                let newURL = FileManager.default.temporaryDirectory.appendingPathComponent(newFilename)
                
                // Move the file to the new name
                try FileManager.default.moveItem(at: mainFile, to: newURL)
                logOutput("✅ File renamed to: \(newFilename)")
                
                progressHandler?("Video file ready")
                return newURL
            }
        } else {
            logOutput("File doesn't have .gif extension - converting to GIF")
            progressHandler?("Converting to GIF...")
            return try await convertVideoToGif(videoURL: mainFile, filename: response.output.filename, progressHandler: progressHandler)
        }
    }
    
    private func handleRemux(response: LocalProcessingResponse, mainFile: URL, progressHandler: ((String) -> Void)?) async throws -> URL {
        logOutput("Handling remux processing")
        progressHandler?("Remuxing video...")
        
        // Check if FFmpeg should be used
        let useFFmpeg = UserDefaults.standard.object(forKey: "useFFmpegForProcessing") as? Bool ?? true
        
        // Remux video using FFmpeg or AVFoundation
        if useFFmpeg {
            return try await FFmpegProcessingManager.shared.remuxVideo(
                videoURL: mainFile,
                filename: response.output.filename,
                progressHandler: progressHandler,
                shouldCancel: { self.shouldCancel }
            )
        } else {
            return try await AVExportProcessingManager.shared.remuxVideo(
                videoURL: mainFile,
                filename: response.output.filename,
                progressHandler: progressHandler,
                shouldCancel: { self.shouldCancel }
            )
        }
    }
    
    private func handleProxy(response: LocalProcessingResponse, mainFile: URL, progressHandler: ((String) -> Void)?) async throws -> URL {
        logOutput("Handling proxy download")
        progressHandler?("Downloading file...")
        
        // For proxy, we just return the main file URL
        return mainFile
    }
    
    // MARK: - GIF Processing (kept here as it doesn't use FFmpeg or AVExport)
    
    private func convertVideoToGif(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?) async throws -> URL {
        // This is a simplified GIF conversion - in a real implementation you'd want more sophisticated frame extraction
        progressHandler?("Converting video frames to GIF...")
        
        let asset = AVAsset(url: videoURL)
        let duration = try await LenghtExtractor.extractDuration(from: videoURL)
        let frameCount = Int(duration * 10) // 10 fps
        
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        var images: [UIImage] = []
        
        for i in 0..<min(frameCount, 50) { // Limit to 50 frames for performance
            let time = CMTime(seconds: Double(i) / 10.0, preferredTimescale: 600)
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                images.append(UIImage(cgImage: cgImage))
            } catch {
                logOutput("Failed to extract frame \(i): \(error)")
            }
        }
        
        guard !images.isEmpty else {
            throw ProcessingError.processingFailed("Failed to extract video frames")
        }
        
        // Create GIF from images
        let gifData = try createGifData(from: images)
        let gifURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try gifData.write(to: gifURL)
        
        return gifURL
    }
    
    // MARK: - Helper Methods
    
    private func createGifData(from images: [UIImage]) throws -> Data {
        let gifData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(gifData, UTType.gif.identifier as CFString, images.count, nil) else {
            throw ProcessingError.processingFailed("Failed to create GIF destination")
        }
        
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]]
        let gifProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
        
        for image in images {
            if let cgImage = image.cgImage {
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            }
        }
        
        guard CGImageDestinationFinalize(destination) else {
            throw ProcessingError.processingFailed("Failed to finalize GIF")
        }
        
        return gifData as Data
    }

}
