//
//  FFmpegProcessingManager.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import Foundation
import ffmpegkit

class FFmpegProcessingManager {
    static let shared = FFmpegProcessingManager()
    
    enum ProcessingError: Error, LocalizedError {
        case processingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .processingFailed(let reason):
                return "FFmpeg processing failed: \(reason)"
            }
        }
    }
    
    func mergeVideoAndAudio(videoURL: URL, audioURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        logOutput("Starting FFmpeg merge process...")
        logOutput("Video URL: \(videoURL)")
        logOutput("Audio URL: \(audioURL)")
        
        // Check if files exist
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ProcessingError.processingFailed("Video file does not exist at path: \(videoURL.path)")
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ProcessingError.processingFailed("Audio file does not exist at path: \(audioURL.path)")
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        // Quote file paths for FFmpeg to handle spaces
        let videoPath = "\"\(videoURL.path)\""
        let audioPath = "\"\(audioURL.path)\""
        let outputPath = "\"\(outputURL.path)\""
        
        // Build FFmpeg command: merge video and audio, copy video codec, encode audio as AAC, use shortest duration
        let command = "-i \(videoPath) -i \(audioPath) -c:v copy -c:a aac -shortest -y \(outputPath)"
        
        logOutput("FFmpeg command: \(command)")
        progressHandler?("Merging video and audio with FFmpeg...")
        
        return try await executeFFmpegCommand(command: command, outputURL: outputURL, progressHandler: progressHandler, shouldCancel: shouldCancel)
    }
    
    func removeAudioFromVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        logOutput("Starting FFmpeg mute process...")
        
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ProcessingError.processingFailed("Video file does not exist at path: \(videoURL.path)")
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        // Quote file paths for FFmpeg to handle spaces
        let inputPath = "\"\(videoURL.path)\""
        let outputPath = "\"\(outputURL.path)\""
        
        // Build FFmpeg command: copy video, remove audio (-an)
        let command = "-i \(inputPath) -c:v copy -an -y \(outputPath)"
        
        logOutput("FFmpeg command: \(command)")
        progressHandler?("Removing audio with FFmpeg...")
        
        return try await executeFFmpegCommand(command: command, outputURL: outputURL, progressHandler: progressHandler, shouldCancel: shouldCancel)
    }
    
    func extractAudioFromVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        logOutput("Starting FFmpeg audio extraction...")
        
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ProcessingError.processingFailed("Video file does not exist at path: \(videoURL.path)")
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        // Quote file paths for FFmpeg to handle spaces
        let inputPath = "\"\(videoURL.path)\""
        let outputPath = "\"\(outputURL.path)\""
        
        // Determine audio codec based on output file extension
        let fileExtension = filename.components(separatedBy: ".").last?.lowercased() ?? "m4a"
        let audioCodec: String
        switch fileExtension {
        case "mp3":
            audioCodec = "libmp3lame"
        case "aac":
            audioCodec = "aac"
        case "wav":
            audioCodec = "pcm_s16le"
        default:
            audioCodec = "copy" // Use copy for m4a and other formats
        }
        
        // Build FFmpeg command: remove video (-vn), copy or encode audio
        let command: String
        if audioCodec == "copy" {
            command = "-i \(inputPath) -vn -c:a copy -y \(outputPath)"
        } else {
            command = "-i \(inputPath) -vn -c:a \(audioCodec) -y \(outputPath)"
        }
        
        logOutput("FFmpeg command: \(command)")
        progressHandler?("Extracting audio with FFmpeg...")
        
        return try await executeFFmpegCommand(command: command, outputURL: outputURL, progressHandler: progressHandler, shouldCancel: shouldCancel)
    }
    
    func remuxVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        logOutput("Starting FFmpeg remux process...")
        
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ProcessingError.processingFailed("Video file does not exist at path: \(videoURL.path)")
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        // Quote file paths for FFmpeg to handle spaces
        let inputPath = "\"\(videoURL.path)\""
        let outputPath = "\"\(outputURL.path)\""
        
        // Build FFmpeg command: copy all streams (remux)
        let command = "-i \(inputPath) -c copy -y \(outputPath)"
        
        logOutput("FFmpeg command: \(command)")
        progressHandler?("Remuxing video with FFmpeg...")
        
        return try await executeFFmpegCommand(command: command, outputURL: outputURL, progressHandler: progressHandler, shouldCancel: shouldCancel)
    }
    
    // MARK: - FFmpeg Helper Methods
    
    private func executeFFmpegCommand(command: String, outputURL: URL, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            // Check for cancellation before starting
            if shouldCancel() {
                continuation.resume(throwing: CancellationError())
                return
            }
            
            // Store session reference for cancellation
            var currentSession: Session?
            
            // Execute FFmpeg command asynchronously
            FFmpegKit.executeAsync(command) { sessionResult in
                guard let session = sessionResult else {
                    continuation.resume(throwing: ProcessingError.processingFailed("FFmpeg session creation failed"))
                    return
                }
                
                currentSession = session
                
                // Check for cancellation during execution
                if shouldCancel() {
                    session.cancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                
                let returnCode = session.getReturnCode()
                
                if ReturnCode.isSuccess(returnCode) {
                    // Check if output file exists
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        progressHandler?("Processing completed")
                        continuation.resume(returning: outputURL)
                    } else {
                        let errorMessage = session.getOutput() ?? "Output file not found"
                        logOutput("FFmpeg error: \(errorMessage)")
                        continuation.resume(throwing: ProcessingError.processingFailed("Output file not created"))
                    }
                } else {
                    // Get error message from session output or logs
                    let errorMessage = session.getOutput() ?? session.getAllLogsAsString() ?? "Unknown FFmpeg error"
                    logOutput("FFmpeg error: \(errorMessage)")
                    continuation.resume(throwing: ProcessingError.processingFailed(errorMessage))
                }
            } withLogCallback: { log in
                // Check for cancellation during log callbacks
                if shouldCancel() {
                    currentSession?.cancel()
                }
                
                // Parse progress from FFmpeg output
                if let logMessage = log?.getMessage() {
                    // FFmpeg progress format: frame=  123 fps= 25 q=28.0 size=    1024kB time=00:00:05.00 bitrate=1677.7kbits/s speed=1.0x
                    if logMessage.contains("time=") {
                        // Extract time information for progress
                        if let timeRange = logMessage.range(of: "time=") {
                            let timeString = String(logMessage[timeRange.upperBound...])
                            if let timeEndRange = timeString.range(of: " ") {
                                let time = String(timeString[..<timeEndRange.lowerBound])
                                progressHandler?("Processing: \(time)")
                            }
                        }
                    }
                }
            } withStatisticsCallback: { statistics in
                // Check for cancellation during statistics callbacks
                if shouldCancel() {
                    currentSession?.cancel()
                }
                
                // Use statistics for more accurate progress
                if let stats = statistics {
                    let time = stats.getTime()
                    if time > 0 {
                        let seconds = Double(time) / 1000.0
                        let minutes = Int(seconds) / 60
                        let secs = Int(seconds) % 60
                        progressHandler?("Processing: \(String(format: "%02d:%02d", minutes, secs))")
                    }
                }
            }
        }
    }
}

