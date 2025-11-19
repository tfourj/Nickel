//
//  FFmpegProcessingManager.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import Foundation
import SwiftFFmpeg

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
        
        // Build FFmpeg arguments array: merge video and audio, copy video codec, encode audio as AAC, use shortest duration
        let arguments = [
            "-i", videoURL.path,
            "-i", audioURL.path,
            "-c:v", "copy",
            "-c:a", "aac",
            "-shortest",
            "-y",
            outputURL.path
        ]
        
        logOutput("FFmpeg command: \(arguments.joined(separator: " "))")
        progressHandler?("Merging video and audio with FFmpeg...")
        
        return try await executeFFmpegCommand(arguments: arguments, outputURL: outputURL, progressHandler: progressHandler, shouldCancel: shouldCancel)
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
        
        // Build FFmpeg arguments array: copy video, remove audio (-an)
        let arguments = [
            "-i", videoURL.path,
            "-c:v", "copy",
            "-an",
            "-y",
            outputURL.path
        ]
        
        logOutput("FFmpeg command: \(arguments.joined(separator: " "))")
        progressHandler?("Removing audio with FFmpeg...")
        
        return try await executeFFmpegCommand(arguments: arguments, outputURL: outputURL, progressHandler: progressHandler, shouldCancel: shouldCancel)
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
        
        // Build FFmpeg arguments array: remove video (-vn), copy or encode audio
        let arguments: [String]
        if audioCodec == "copy" {
            arguments = [
                "-i", videoURL.path,
                "-vn",
                "-c:a", "copy",
                "-y",
                outputURL.path
            ]
        } else {
            arguments = [
                "-i", videoURL.path,
                "-vn",
                "-c:a", audioCodec,
                "-y",
                outputURL.path
            ]
        }
        
        logOutput("FFmpeg command: \(arguments.joined(separator: " "))")
        progressHandler?("Extracting audio with FFmpeg...")
        
        return try await executeFFmpegCommand(arguments: arguments, outputURL: outputURL, progressHandler: progressHandler, shouldCancel: shouldCancel)
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
        
        // Build FFmpeg arguments array: copy all streams (remux)
        let arguments = [
            "-i", videoURL.path,
            "-c", "copy",
            "-y",
            outputURL.path
        ]
        
        logOutput("FFmpeg command: \(arguments.joined(separator: " "))")
        progressHandler?("Remuxing video with FFmpeg...")
        
        return try await executeFFmpegCommand(arguments: arguments, outputURL: outputURL, progressHandler: progressHandler, shouldCancel: shouldCancel)
    }
    
    // MARK: - FFmpeg Helper Methods
    
    private func executeFFmpegCommand(arguments: [String], outputURL: URL, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        // Check for cancellation before starting
        if shouldCancel() {
            throw CancellationError()
        }
        
        // Execute FFmpeg on background thread
        return try await Task.detached {
            // Check cancellation again before execution
            if Task.isCancelled || shouldCancel() {
                throw CancellationError()
            }
            
            // Set up thread-safe log message collection
            let logQueue = DispatchQueue(label: "com.ffmpeg.logs")
            var logMessages: [String] = []
            
            // Set up log handler for progress updates (inside the task)
            SwiftFFmpeg.setLogLevel(.info)
            SwiftFFmpeg.setLogHandler { level, message in
                // Thread-safe append
                logQueue.sync {
                    logMessages.append(message)
                }
                
                // Log all messages for debugging
                //logOutput("[FFmpeg \(level)] \(message)")
                
                // Parse progress from FFmpeg output
                // FFmpeg progress format: frame=  123 fps= 25 q=28.0 size=    1024kB time=00:00:05.00 bitrate=1677.7kbits/s speed=1.0x
                if message.contains("time=") {
                    // Extract time information for progress
                    if let timeRange = message.range(of: "time=") {
                        let timeString = String(message[timeRange.upperBound...])
                        if let timeEndRange = timeString.range(of: " ") {
                            let time = String(timeString[..<timeEndRange.lowerBound])
                            progressHandler?("Processing: \(time)")
                        } else {
                            // Sometimes time is at the end of the line
                            let time = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !time.isEmpty {
                                progressHandler?("Processing: \(time)")
                            }
                        }
                    }
                }
            }
            
            defer {
                // Clean up log handler
                SwiftFFmpeg.setLogHandler(nil)
            }
            
            do {
                // Execute FFmpeg command
                // Try executeWithOutput first to capture any error messages
                let (exitCode, output) = try SwiftFFmpeg.executeWithOutput(arguments)
                
                // Get log messages thread-safely
                let allLogs = logQueue.sync { logMessages.joined(separator: "\n") }
                
                // Combine output and logs
                let fullOutput = output.isEmpty ? allLogs : (allLogs.isEmpty ? output : "\(output)\n\(allLogs)")
                
                // Check if output file exists
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    progressHandler?("Processing completed")
                    return outputURL
                } else {
                    logOutput("FFmpeg error: Output file not created. Exit code: \(exitCode). Output: \(fullOutput)")
                    throw ProcessingError.processingFailed("Output file not created. FFmpeg output: \(fullOutput)")
                }
            } catch SwiftFFmpegError.executionFailed(let code) {
                let allLogs = logQueue.sync { logMessages.joined(separator: "\n") }
                logOutput("FFmpeg error (exit code \(code)): \(allLogs)")
                
                // Provide more helpful error message
                let errorMsg: String
                if code == -1 {
                    errorMsg = "FFmpeg crashed or returned invalid exit code. Logs: \(allLogs.isEmpty ? "No logs available" : allLogs)"
                } else if code == 512 {
                    errorMsg = "FFmpeg returned unusual exit code 512 (possible crash). Logs: \(allLogs.isEmpty ? "No logs available" : allLogs)"
                } else {
                    errorMsg = "FFmpeg failed with exit code \(code). Logs: \(allLogs.isEmpty ? "No logs available" : allLogs)"
                }
                
                throw ProcessingError.processingFailed(errorMsg)
            } catch {
                let allLogs = logQueue.sync { logMessages.joined(separator: "\n") }
                logOutput("FFmpeg error: \(error.localizedDescription). Logs: \(allLogs)")
                throw ProcessingError.processingFailed("\(error.localizedDescription)")
            }
        }.value
    }
}

