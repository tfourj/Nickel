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
    
    // Thread-safe log message collection
    private let logQueue = DispatchQueue(label: "com.ffmpeg.logs")
    private var logMessages: [String] = []
    private var isLogHandlerSet = false
    private let logHandlerLock = NSLock()
    
    // Dedicated serial queue for FFmpeg execution
    private let ffmpegExecutionQueue = DispatchQueue(label: "com.ffmpeg.execution", qos: .userInitiated)
    
    enum ProcessingError: Error, LocalizedError {
        case processingFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .processingFailed(let reason):
                return "FFmpeg processing failed: \(reason)"
            }
        }
    }
    
    private init() {
        // Initialize FFmpeg logging system early on main thread
        // This prevents crashes from uninitialized logging
        DispatchQueue.main.async {
            // Set quiet level by default (will be adjusted per-operation)
            SwiftFFmpeg.setLogLevel(.quiet)
        }
    }
    
    /// Helper function to create a temporary output file and move it to final location after FFmpeg completes
    private func executeFFmpegWithTempFile(
        arguments: [String],
        finalOutputURL: URL,
        progressHandler: ((String) -> Void)?,
        shouldCancel: @escaping () -> Bool
    ) async throws -> URL {
        // Create a unique temporary filename
        let fileExtension = (finalOutputURL.lastPathComponent as NSString).pathExtension
        let fileNameWithoutExtension = (finalOutputURL.lastPathComponent as NSString).deletingPathExtension
        let tempFilename = "\(fileNameWithoutExtension)_\(UUID().uuidString).\(fileExtension)"
        let tempOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempFilename)
        
        // Remove temp file if it exists (shouldn't happen with UUID, but be safe)
        if FileManager.default.fileExists(atPath: tempOutputURL.path) {
            try? FileManager.default.removeItem(at: tempOutputURL)
        }
        
        // Replace the output path in arguments with temp path
        var tempArguments = arguments
        if let lastIndex = tempArguments.indices.last {
            tempArguments[lastIndex] = tempOutputURL.path
        }
        
        do {
            // Execute FFmpeg with temp file
            let resultURL = try await executeFFmpegCommand(
                arguments: tempArguments,
                outputURL: tempOutputURL,
                progressHandler: progressHandler,
                shouldCancel: shouldCancel
            )
            
            // Remove final file if it exists
            if FileManager.default.fileExists(atPath: finalOutputURL.path) {
                try? FileManager.default.removeItem(at: finalOutputURL)
            }
            
            // Move temp file to final location
            try FileManager.default.moveItem(at: resultURL, to: finalOutputURL)
            
            return finalOutputURL
        } catch {
            // Clean up temp file on error
            if FileManager.default.fileExists(atPath: tempOutputURL.path) {
                try? FileManager.default.removeItem(at: tempOutputURL)
            }
            throw error
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
        
        let finalOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // Build FFmpeg arguments array: merge video and audio, copy video codec, encode audio as AAC, use shortest duration
        let arguments = [
            "-i", videoURL.path,
            "-i", audioURL.path,
            "-c:v", "copy",
            "-c:a", "aac",
            "-shortest",
            "-y",
            finalOutputURL.path  // Will be replaced with temp path in helper
        ]
        
        logOutput("FFmpeg command: \(arguments.joined(separator: " "))")
        progressHandler?("Merging video and audio with FFmpeg...")
        
        return try await executeFFmpegWithTempFile(
            arguments: arguments,
            finalOutputURL: finalOutputURL,
            progressHandler: progressHandler,
            shouldCancel: shouldCancel
        )
    }
    
    func removeAudioFromVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        logOutput("Starting FFmpeg mute process...")
        
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ProcessingError.processingFailed("Video file does not exist at path: \(videoURL.path)")
        }
        
        let finalOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // Build FFmpeg arguments array: copy video, remove audio (-an)
        let arguments = [
            "-i", videoURL.path,
            "-c:v", "copy",
            "-an",
            "-y",
            finalOutputURL.path  // Will be replaced with temp path in helper
        ]
        
        logOutput("FFmpeg command: \(arguments.joined(separator: " "))")
        progressHandler?("Removing audio with FFmpeg...")
        
        return try await executeFFmpegWithTempFile(
            arguments: arguments,
            finalOutputURL: finalOutputURL,
            progressHandler: progressHandler,
            shouldCancel: shouldCancel
        )
    }
    
    func extractAudioFromVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        logOutput("Starting FFmpeg audio extraction...")
        
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ProcessingError.processingFailed("Video file does not exist at path: \(videoURL.path)")
        }
        
        let finalOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
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
                finalOutputURL.path  // Will be replaced with temp path in helper
            ]
        } else {
            arguments = [
                "-i", videoURL.path,
                "-vn",
                "-c:a", audioCodec,
                "-y",
                finalOutputURL.path  // Will be replaced with temp path in helper
            ]
        }
        
        logOutput("FFmpeg command: \(arguments.joined(separator: " "))")
        progressHandler?("Extracting audio with FFmpeg...")
        
        return try await executeFFmpegWithTempFile(
            arguments: arguments,
            finalOutputURL: finalOutputURL,
            progressHandler: progressHandler,
            shouldCancel: shouldCancel
        )
    }
    
    func remuxVideo(videoURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        logOutput("Starting FFmpeg remux process...")
        
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ProcessingError.processingFailed("Video file does not exist at path: \(videoURL.path)")
        }
        
        let finalOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // Build FFmpeg arguments array: copy all streams (remux)
        let arguments = [
            "-i", videoURL.path,
            "-c", "copy",
            "-y",
            finalOutputURL.path  // Will be replaced with temp path in helper
        ]
        
        logOutput("FFmpeg command: \(arguments.joined(separator: " "))")
        progressHandler?("Remuxing video with FFmpeg...")
        
        return try await executeFFmpegWithTempFile(
            arguments: arguments,
            finalOutputURL: finalOutputURL,
            progressHandler: progressHandler,
            shouldCancel: shouldCancel
        )
    }
    
    // MARK: - FFmpeg Helper Methods
    
    private func executeFFmpegCommand(arguments: [String], outputURL: URL, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        // Check for cancellation before starting
        if shouldCancel() {
            throw CancellationError()
        }
        
        // Clear previous log messages for this operation
        logQueue.sync {
            logMessages.removeAll()
        }
        
        // Set up log handler BEFORE executing FFmpeg
        let enableFFmpegLogs = UserDefaults.standard.bool(forKey: "enableFFmpegLogs")
        
        // Set log level and handler synchronously
        if enableFFmpegLogs {
            SwiftFFmpeg.setLogLevel(.debug)
        } else {
            SwiftFFmpeg.setLogLevel(.quiet)
        }
        
        // Create a thread-safe progress handler wrapper
        let progressQueue = DispatchQueue(label: "com.ffmpeg.progress")
        var currentProgressHandler: ((String) -> Void)? = progressHandler
        
        // Set log handler thread-safely
        logHandlerLock.lock()
        SwiftFFmpeg.setLogHandler { [weak self] level, message in
            guard let self = self else { return }
            
            // Thread-safe append (always collect for error reporting)
            self.logQueue.sync {
                self.logMessages.append(message)
            }
            
            // Only log to console if FFmpeg logs are enabled
            if enableFFmpegLogs {
                // Format message with FFmpeg level prefix
                let levelPrefix: String
                switch level {
                case .error, .fatal:
                    levelPrefix = "❌ [FFmpeg ERROR]"
                case .warning:
                    levelPrefix = "⚠️ [FFmpeg WARNING]"
                default:
                    levelPrefix = "[FFmpeg \(level)]"
                }
                let formattedMessage = "\(levelPrefix) \(message)"
                // Always print to Xcode console
                print(formattedMessage)
                // Add to ConsoleLogger if console is enabled
                logOutput(formattedMessage)
            }
            
            // Parse progress from FFmpeg output thread-safely
            // FFmpeg progress format: frame=  123 fps= 25 q=28.0 size=    1024kB time=00:00:05.00 bitrate=1677.7kbits/s speed=1.0x
            if message.contains("time=") {
                // Extract time information for progress
                if let timeRange = message.range(of: "time=") {
                    let timeString = String(message[timeRange.upperBound...])
                    if let timeEndRange = timeString.range(of: " ") {
                        let time = String(timeString[..<timeEndRange.lowerBound])
                        progressQueue.async {
                            currentProgressHandler?("Processing: \(time)")
                        }
                    } else {
                        // Sometimes time is at the end of the line
                        let time = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !time.isEmpty {
                            progressQueue.async {
                                currentProgressHandler?("Processing: \(time)")
                            }
                        }
                    }
                }
            }
        }
        isLogHandlerSet = true
        logHandlerLock.unlock()
        
        // Execute FFmpeg on dedicated serial queue using continuation
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()
            
            func safeResume(returning value: URL) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                
                // Clean up log handler before resuming
                logHandlerLock.lock()
                if isLogHandlerSet {
                    SwiftFFmpeg.setLogHandler(nil)
                    isLogHandlerSet = false
                }
                logHandlerLock.unlock()
                
                // Clear progress handler
                progressQueue.sync {
                    currentProgressHandler = nil
                }
                
                continuation.resume(returning: value)
            }
            
            func safeResume(throwing error: Error) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                
                // Clean up log handler before resuming
                logHandlerLock.lock()
                if isLogHandlerSet {
                    SwiftFFmpeg.setLogHandler(nil)
                    isLogHandlerSet = false
                }
                logHandlerLock.unlock()
                
                // Clear progress handler
                progressQueue.sync {
                    currentProgressHandler = nil
                }
                
                continuation.resume(throwing: error)
            }
            
            ffmpegExecutionQueue.async { [weak self] in
                guard let self = self else {
                    safeResume(throwing: CancellationError())
                    return
                }
                
                // Check cancellation before execution
                if shouldCancel() {
                    safeResume(throwing: CancellationError())
                    return
                }
                
                // Verify all input files exist and are accessible before executing FFmpeg
                // Find all "-i" arguments and validate their corresponding input files
                var inputIndex = 0
                while inputIndex < arguments.count {
                    if arguments[inputIndex] == "-i" && inputIndex + 1 < arguments.count {
                        let inputPath = arguments[inputIndex + 1]
                        
                        // Check if file exists
                        guard FileManager.default.fileExists(atPath: inputPath) else {
                            safeResume(throwing: ProcessingError.processingFailed("Input file does not exist: \(inputPath)"))
                            return
                        }
                        
                        // Verify file is readable
                        guard FileManager.default.isReadableFile(atPath: inputPath) else {
                            safeResume(throwing: ProcessingError.processingFailed("Input file is not readable: \(inputPath)"))
                            return
                        }
                        
                        // Get file attributes to verify it's a regular file
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: inputPath),
                           let fileType = attributes[.type] as? FileAttributeType,
                           fileType != .typeRegular {
                            safeResume(throwing: ProcessingError.processingFailed("Input path is not a regular file: \(inputPath)"))
                            return
                        }
                    }
                    inputIndex += 1
                }
                
                do {
                    // Execute FFmpeg command
                    let (exitCode, output) = try SwiftFFmpeg.executeWithOutput(arguments)
                    
                    // Get log messages thread-safely
                    let allLogs = self.logQueue.sync { self.logMessages.joined(separator: "\n") }
                    
                    // Combine output and logs
                    let fullOutput = output.isEmpty ? allLogs : (allLogs.isEmpty ? output : "\(output)\n\(allLogs)")
                    
                    // Check if output file exists
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        progressQueue.async {
                            currentProgressHandler?("Processing completed")
                        }
                        safeResume(returning: outputURL)
                    } else {
                        logOutput("FFmpeg error: Output file not created. Exit code: \(exitCode). Output: \(fullOutput)")
                        safeResume(throwing: ProcessingError.processingFailed("Output file not created. FFmpeg output: \(fullOutput)"))
                    }
                } catch SwiftFFmpegError.executionFailed(let code) {
                    let allLogs = self.logQueue.sync { self.logMessages.joined(separator: "\n") }
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
                    
                    safeResume(throwing: ProcessingError.processingFailed(errorMsg))
                } catch {
                    let allLogs = self.logQueue.sync { self.logMessages.joined(separator: "\n") }
                    logOutput("FFmpeg error: \(error.localizedDescription). Logs: \(allLogs)")
                    safeResume(throwing: ProcessingError.processingFailed("\(error.localizedDescription)"))
                }
            }
        }
    }
}

