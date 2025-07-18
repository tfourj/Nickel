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
        
        // Merge video and audio using AVFoundation
        progressHandler?("Merging video and audio...")
        let result = try await mergeVideoAndAudio(videoURL: videoFileCopy, audioURL: audioFile, filename: response.output.filename, progressHandler: progressHandler)
        
        // Clean up the temporary video copy
        try? FileManager.default.removeItem(at: videoFileCopy)
        logOutput("Cleaned up temporary video copy")
        
        return result
    }
    
    private func handleMute(response: LocalProcessingResponse, mainFile: URL, progressHandler: ((String) -> Void)?) async throws -> URL {
        logOutput("Handling mute processing")
        progressHandler?("Processing mute...")
        
        // Remove audio track from video
        return try await removeAudioFromVideo(videoURL: mainFile, filename: response.output.filename, progressHandler: progressHandler)
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
        
        // Extract audio from video using the original filename
        return try await extractAudioFromVideo(videoURL: mainFile, filename: response.output.filename, progressHandler: progressHandler)
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
        
        // Remux video to different format
        return try await remuxVideo(videoURL: mainFile, filename: response.output.filename, progressHandler: progressHandler)
    }
    
    private func handleProxy(response: LocalProcessingResponse, mainFile: URL, progressHandler: ((String) -> Void)?) async throws -> URL {
        logOutput("Handling proxy download")
        progressHandler?("Downloading file...")
        
        // For proxy, we just return the main file URL
        return mainFile
    }
    
    // MARK: - Processing Methods
    
    private func mergeVideoAndAudio(videoURL: URL, audioURL: URL, filename: String, progressHandler: ((String) -> Void)?) async throws -> URL {
        let composition = AVMutableComposition()
        
        logOutput("Starting merge process...")
        logOutput("Video URL: \(videoURL)")
        logOutput("Audio URL: \(audioURL)")
        
        // Check if files exist
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ProcessingError.processingFailed("Video file does not exist at path: \(videoURL.path)")
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ProcessingError.processingFailed("Audio file does not exist at path: \(audioURL.path)")
        }
        
        // Use LenghtExtractor for accurate video duration analysis
        progressHandler?("Analyzing video duration...")
        
        // Extract accurate durations using LenghtExtractor
        let videoDuration = try await LenghtExtractor.extractDuration(from: videoURL)
        let audioDuration = try await LenghtExtractor.extractDuration(from: audioURL)
        
        // Smart duration selection logic
        let durationDifference = abs(videoDuration - audioDuration)
        let toleranceThreshold = 0.1 // 100ms tolerance
        
        let targetDuration: Double
        let durationSource: String
        
        if durationDifference <= toleranceThreshold {
            // Durations are very close, use video duration (traditional approach)
            targetDuration = videoDuration
            durationSource = "video (durations match within \(toleranceThreshold)s)"
            logOutput("✅ Video and audio durations are very close (diff: \(String(format: "%.3f", durationDifference))s), using video duration")
        } else if videoDuration > audioDuration {
            // Video is longer - check if the difference is significant
            if durationDifference > 2.0 {
                // Significant difference, use shorter duration to avoid blank video
                targetDuration = audioDuration
                durationSource = "audio (video significantly longer by \(String(format: "%.2f", durationDifference))s)"
                logOutput("⚠️ Video much longer than audio, using audio duration to avoid blank video")
            } else {
                // Moderate difference, use video duration
                targetDuration = videoDuration
                durationSource = "video (slightly longer than audio)"
                logOutput("📹 Video slightly longer than audio, using video duration")
            }
        } else {
            // Audio is longer - check if the difference is significant
            if durationDifference > 2.0 {
                // Significant difference, use shorter duration to avoid silent audio
                targetDuration = videoDuration
                durationSource = "video (audio significantly longer by \(String(format: "%.2f", durationDifference))s)"
                logOutput("⚠️ Audio much longer than video, using video duration to avoid silent audio")
            } else {
                // Moderate difference, use longer duration to preserve content
                targetDuration = audioDuration
                durationSource = "audio (slightly longer than video, preserving content)"
                logOutput("🎵 Audio slightly longer than video, using audio duration to preserve content")
            }
        }
        
        let targetCMTime = CMTime(seconds: targetDuration, preferredTimescale: 600)
        
        logOutput("=== Duration Analysis ===")
        logOutput("Video duration: \(String(format: "%.3f", videoDuration))s")
        logOutput("Audio duration: \(String(format: "%.3f", audioDuration))s")
        logOutput("Difference: \(String(format: "%.3f", durationDifference))s")
        logOutput("Selected: \(String(format: "%.3f", targetDuration))s from \(durationSource)")
        
        // Load tracks for composition
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        async let videoTracksTask = videoAsset.loadTracks(withMediaType: .video)
        async let audioTracksTask = audioAsset.loadTracks(withMediaType: .audio)
        
        let videoTracks = try await videoTracksTask
        let audioTracks = try await audioTracksTask
        
        logOutput("Found \(videoTracks.count) video tracks")
        
        guard let sourceVideoTrack = videoTracks.first else {
            throw ProcessingError.processingFailed("No video tracks found in video file")
        }
        
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProcessingError.processingFailed("Failed to create video composition track")
        }
        
        // Use the target duration instead of full video duration
        let videoTimeRange = CMTimeRange(start: .zero, duration: targetCMTime)
        logOutput("Video time range: \(videoTimeRange)")
        
        try videoTrack.insertTimeRange(videoTimeRange, of: sourceVideoTrack, at: .zero)
        logOutput("Video track added successfully")
        
        // Add audio track
        guard let sourceAudioTrack = audioTracks.first else {
            throw ProcessingError.processingFailed("No audio tracks found in audio file")
        }
        
        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProcessingError.processingFailed("Failed to create audio composition track")
        }
        
        // Use the target duration instead of full audio duration
        let audioTimeRange = CMTimeRange(start: .zero, duration: targetCMTime)
        logOutput("Audio time range: \(audioTimeRange)")
        
        try audioTrack.insertTimeRange(audioTimeRange, of: sourceAudioTrack, at: .zero)
        logOutput("Audio track added successfully")
        
        // Export merged composition
        logOutput("Starting export of merged composition...")
        return try await exportComposition(composition, filename: filename, progressHandler: progressHandler)
    }
    
    private func removeAudioFromVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?) async throws -> URL {
        let composition = AVMutableComposition()
        
        guard let videoAsset = AVAsset(url: videoURL) as? AVURLAsset,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceVideoTrack = try? await videoAsset.loadTracks(withMediaType: .video).first else {
            throw ProcessingError.processingFailed("Failed to load video track")
        }
        
        let videoTimeRange = try await sourceVideoTrack.load(.timeRange)
        try videoTrack.insertTimeRange(videoTimeRange, of: sourceVideoTrack, at: .zero)
        
        return try await exportComposition(composition, filename: filename, progressHandler: progressHandler)
    }
    
    private func extractAudioFromVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?) async throws -> URL {
        let composition = AVMutableComposition()
        
        guard let videoAsset = AVAsset(url: videoURL) as? AVURLAsset,
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceAudioTrack = try? await videoAsset.loadTracks(withMediaType: .audio).first else {
            throw ProcessingError.processingFailed("Failed to load audio track")
        }
        
        let audioTimeRange = try await sourceAudioTrack.load(.timeRange)
        try audioTrack.insertTimeRange(audioTimeRange, of: sourceAudioTrack, at: .zero)
        
        return try await exportComposition(composition, filename: filename, progressHandler: progressHandler)
    }
    
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
    
    private func remuxVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?) async throws -> URL {
        // For remuxing, we'll just copy the video to a new container format
        progressHandler?("Remuxing video...")
        
        let composition = AVMutableComposition()
        
        guard let videoAsset = AVAsset(url: videoURL) as? AVURLAsset else {
            throw ProcessingError.processingFailed("Failed to load video asset")
        }
        
        // Copy all tracks
        for track in try await videoAsset.loadTracks(withMediaType: .video) {
            let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            let timeRange = try await track.load(.timeRange)
            try compositionTrack?.insertTimeRange(timeRange, of: track, at: .zero)
        }
        
        for track in try await videoAsset.loadTracks(withMediaType: .audio) {
            let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            let timeRange = try await track.load(.timeRange)
            try compositionTrack?.insertTimeRange(timeRange, of: track, at: .zero)
        }
        
        return try await exportComposition(composition, filename: filename, progressHandler: progressHandler)
    }
    
    // MARK: - Helper Methods
    
    private func exportComposition(_ composition: AVComposition, filename: String, progressHandler: ((String) -> Void)?) async throws -> URL {
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        
        guard let exportSession = exportSession else {
            throw ProcessingError.processingFailed("Failed to create export session")
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        exportSession.outputURL = outputURL
        
        // Determine output file type based on filename extension
        let fileExtension = filename.components(separatedBy: ".").last?.lowercased() ?? "mp4"
        switch fileExtension {
        case "m4a", "aac":
            exportSession.outputFileType = .m4a
        case "mp3":
            exportSession.outputFileType = .mp3
        case "wav":
            exportSession.outputFileType = .wav
        default:
            exportSession.outputFileType = .mp4
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let session = exportSession // Capture in local variable to avoid Sendable issue
            
            // Check for cancellation before starting export
            if shouldCancel {
                continuation.resume(throwing: CancellationError())
                return
            }
            
            // Show initial progress message
            progressHandler?("Starting export...")
            
            // Start progress monitoring using DispatchSourceTimer
            var progressTimer: DispatchSourceTimer?
            if progressHandler != nil {
                progressTimer = DispatchSource.makeTimerSource(queue: .main)
                progressTimer?.schedule(deadline: .now(), repeating: .milliseconds(100))
                progressTimer?.setEventHandler(flags: []) {
                    let progress = session.progress
                    let scaledProgress = min(progress * 2, 1.0)
                    let percentage = Int(scaledProgress * 100)
                    
                    if progress > 0 {
                        progressHandler?("Exporting: \(percentage)%")
                        
                        // Stop timer when actual progress reaches 99% or higher
                        if progress > 0.99 {
                            progressTimer?.cancel()
                        }
                    } else {
                        progressHandler?("Preparing export...")
                    }
                    
                    // Check for cancellation during progress updates
                    if self.shouldCancel {
                        session.cancelExport()
                        progressTimer?.cancel()
                    }
                }
                progressTimer?.resume()
            }
            
            session.exportAsynchronously {
                // Stop progress timer
                progressTimer?.cancel()
                
                // Check for cancellation during export
                if self.shouldCancel {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                switch session.status {
                case .completed:
                    progressHandler?("Export completed")
                    continuation.resume(returning: outputURL)
                case .failed:
                    continuation.resume(throwing: ProcessingError.processingFailed(session.error?.localizedDescription ?? "Export failed"))
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: ProcessingError.processingFailed("Export failed with status: \(session.status.rawValue)"))
                }
            }
        }
    }
    
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
