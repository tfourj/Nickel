//
//  AVExportProcessingManager.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import Foundation
import AVFoundation

class AVExportProcessingManager {
    static let shared = AVExportProcessingManager()
    
    enum ProcessingError: Error, LocalizedError {
        case processingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .processingFailed(let reason):
                return "AVExport processing failed: \(reason)"
            }
        }
    }
    
    func mergeVideoAndAudio(videoURL: URL, audioURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
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
        return try await exportComposition(composition, filename: filename, progressHandler: progressHandler, shouldCancel: shouldCancel)
    }
    
    func removeAudioFromVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        let composition = AVMutableComposition()
        
        guard let videoAsset = AVAsset(url: videoURL) as? AVURLAsset,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceVideoTrack = try? await videoAsset.loadTracks(withMediaType: .video).first else {
            throw ProcessingError.processingFailed("Failed to load video track")
        }
        
        let videoTimeRange = try await sourceVideoTrack.load(.timeRange)
        try videoTrack.insertTimeRange(videoTimeRange, of: sourceVideoTrack, at: .zero)
        
        return try await exportComposition(composition, filename: filename, progressHandler: progressHandler, shouldCancel: shouldCancel)
    }
    
    func extractAudioFromVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        let composition = AVMutableComposition()
        
        guard let videoAsset = AVAsset(url: videoURL) as? AVURLAsset,
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceAudioTrack = try? await videoAsset.loadTracks(withMediaType: .audio).first else {
            throw ProcessingError.processingFailed("Failed to load audio track")
        }
        
        let audioTimeRange = try await sourceAudioTrack.load(.timeRange)
        try audioTrack.insertTimeRange(audioTimeRange, of: sourceAudioTrack, at: .zero)
        
        return try await exportComposition(composition, filename: filename, progressHandler: progressHandler, shouldCancel: shouldCancel)
    }
    
    func remuxVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
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
        
        return try await exportComposition(composition, filename: filename, progressHandler: progressHandler, shouldCancel: shouldCancel)
    }
    
    // MARK: - Helper Methods
    
    private func exportComposition(_ composition: AVComposition, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
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
            if shouldCancel() {
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
                    if shouldCancel() {
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
                if shouldCancel() {
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
}

