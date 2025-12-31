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
    private let ffmpegLogBufferQueue = DispatchQueue(label: "com.ffmpeg.logbuffer")
    private var ffmpegLogBuffer: [String] = []
    private var ffmpegLogFlushTimer: DispatchSourceTimer?
    private let ffmpegLogFlushInterval: TimeInterval = 0.25
    private let ffmpegLogMaxBufferLines = 200
    private let ffmpegLogMaxStoredLines = 2000
    private var ffmpegLogWindowStart = Date.distantPast
    private var ffmpegLogWindowCount = 0
    private var ffmpegLogDroppedCount = 0
    private let ffmpegLogRateWindow: TimeInterval = 1.0
    private let ffmpegLogMaxPerWindow = 200
    
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

    private func enqueueFFmpegLog(_ message: String) {
        ffmpegLogBufferQueue.async {
            let now = Date()
            if now.timeIntervalSince(self.ffmpegLogWindowStart) >= self.ffmpegLogRateWindow {
                self.ffmpegLogWindowStart = now
                self.ffmpegLogWindowCount = 0
            }
            
            if self.ffmpegLogWindowCount >= self.ffmpegLogMaxPerWindow {
                self.ffmpegLogDroppedCount += 1
                return
            }
            self.ffmpegLogWindowCount += 1
            self.ffmpegLogBuffer.append(message)
            
            if self.ffmpegLogBuffer.count >= self.ffmpegLogMaxBufferLines {
                self.flushFFmpegLogBufferLocked()
                return
            }
            
            if self.ffmpegLogFlushTimer == nil {
                let timer = DispatchSource.makeTimerSource(queue: self.ffmpegLogBufferQueue)
                timer.schedule(deadline: .now() + self.ffmpegLogFlushInterval, repeating: self.ffmpegLogFlushInterval)
                timer.setEventHandler { [weak self] in
                    self?.flushFFmpegLogBufferLocked()
                }
                self.ffmpegLogFlushTimer = timer
                timer.resume()
            }
        }
    }
    
    private func flushFFmpegLogBufferLocked() {
        guard !ffmpegLogBuffer.isEmpty else {
            if let timer = ffmpegLogFlushTimer {
                timer.cancel()
                ffmpegLogFlushTimer = nil
            }
            return
        }
        
        var messages = ffmpegLogBuffer
        ffmpegLogBuffer.removeAll(keepingCapacity: true)
        
        if ffmpegLogDroppedCount > 0 {
            messages.append("[FFmpeg] Dropped \(ffmpegLogDroppedCount) log lines to keep app responsive")
            ffmpegLogDroppedCount = 0
        }
        
        if UserDefaults.standard.bool(forKey: "enableConsole") {
            ConsoleLogger.shared.appendLogs(messages)
        }
        
        print(messages.joined(separator: "\n"))
    }
    
    private func flushFFmpegLogBuffer() {
        ffmpegLogBufferQueue.async {
            self.flushFFmpegLogBufferLocked()
            if let timer = self.ffmpegLogFlushTimer {
                timer.cancel()
                self.ffmpegLogFlushTimer = nil
            }
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
        
        // Determine format from filename extension (same as cobalt.tools)
        let format = (filename as NSString).pathExtension.lowercased()
        
        // Build FFmpeg arguments array: merge video and audio (same as cobalt.tools remux for merge type)
        var arguments = [
            "-i", videoURL.path,
            "-i", audioURL.path,
            "-map", "0:v",
            "-map", "1:a",
            "-c:v", "copy",
            "-c:a", "copy"
        ]
        
        // Add format-specific flags (same as cobalt.tools)
        if format == "mp4" {
            arguments.append(contentsOf: ["-movflags", "faststart+frag_keyframe+empty_moov"])
        }
        
        // Set output format (same as cobalt.tools)
        let outputFormat: String
        if format == "mkv" {
            outputFormat = "matroska"
        } else {
            outputFormat = format
        }
        arguments.append(contentsOf: ["-f", outputFormat])
        
        arguments.append("-y")
        arguments.append(finalOutputURL.path)  // Will be replaced with temp path in helper
        
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
        
        // Determine format from filename extension (same as cobalt.tools)
        let format = (filename as NSString).pathExtension.lowercased()
        
        // Build FFmpeg arguments array: copy video, remove audio (-an) (same as cobalt.tools remux for mute type)
        var arguments = [
            "-i", videoURL.path,
            "-map", "0:v:0",
            "-map", "0:a:0",
            "-c:v", "copy",
            "-an"
        ]
        
        // Add format-specific flags (same as cobalt.tools)
        if format == "mp4" {
            arguments.append(contentsOf: ["-movflags", "faststart+frag_keyframe+empty_moov"])
        }
        
        // Set output format (same as cobalt.tools)
        let outputFormat: String
        if format == "mkv" {
            outputFormat = "matroska"
        } else {
            outputFormat = format
        }
        arguments.append(contentsOf: ["-f", outputFormat])
        
        arguments.append("-y")
        arguments.append(finalOutputURL.path)  // Will be replaced with temp path in helper
        
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

    func transcodeAudioToMp3(audioURL: URL, filename: String, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        logOutput("Starting FFmpeg audio transcode to MP3...")
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw ProcessingError.processingFailed("Audio file does not exist at path: \(audioURL.path)")
        }
        
        let finalOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        let arguments = [
            "-i", audioURL.path,
            "-vn",
            "-map", "0:a:0",
            "-c:a", "libmp3lame",
            "-q:a", "2",
            "-y",
            finalOutputURL.path  // Will be replaced with temp path in helper
        ]
        
        logOutput("FFmpeg command: \(arguments.joined(separator: " "))")
        progressHandler?("Transcoding audio to MP3 with FFmpeg...")
        
        return try await executeFFmpegWithTempFile(
            arguments: arguments,
            finalOutputURL: finalOutputURL,
            progressHandler: progressHandler,
            shouldCancel: shouldCancel
        )
    }
    
    func remuxVideo(videoURL: URL, filename: String, hasAudio: Bool = true, progressHandler: ((String) -> Void)?, shouldCancel: @escaping () -> Bool) async throws -> URL {
        logOutput("Starting FFmpeg remux process...")
        
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ProcessingError.processingFailed("Video file does not exist at path: \(videoURL.path)")
        }
        
        let finalOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        // Determine format from filename extension (same as cobalt.tools)
        let format = (filename as NSString).pathExtension.lowercased()
        
        // Build FFmpeg arguments array: copy all streams (remux) - same as cobalt.tools for single URL
        var arguments = [
            "-i", videoURL.path,
            "-map", "0:v:0"
        ]
        
        // Only map audio if the video has audio streams
        if hasAudio {
            arguments.append(contentsOf: ["-map", "0:a:0"])
            arguments.append(contentsOf: ["-c:v", "copy", "-c:a", "copy"])
        } else {
            // For videos without audio, only copy video
            arguments.append(contentsOf: ["-c:v", "copy"])
        }
        
        // Add format-specific flags (same as cobalt.tools)
        if format == "mp4" {
            arguments.append(contentsOf: ["-movflags", "faststart+frag_keyframe+empty_moov"])
        }
        
        // Set output format (same as cobalt.tools)
        let outputFormat: String
        if format == "mkv" {
            outputFormat = "matroska"
        } else {
            outputFormat = format
        }
        arguments.append(contentsOf: ["-f", outputFormat])
        
        arguments.append("-y")
        arguments.append(finalOutputURL.path)  // Will be replaced with temp path in helper
        
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
    
    /// Check if a video file has audio tracks using ffprobe
    /// This works even if AVFoundation doesn't support the codec
    func checkVideoHasAudioTrack(fileURL: URL) async -> Bool {
        logOutput("Checking for audio tracks using ffprobe: \(fileURL.path)")
        
        // Use ffprobe to check for audio streams
        // -select_streams a: Select only audio streams
        // -show_entries stream=codec_type: Show codec type for selected streams
        // -of default=noprint_wrappers=1:nokey=1: Simple output format (just "audio" if found)
        let arguments = [
            "-v", "error",
            "-select_streams", "a",
            "-show_entries", "stream=codec_type",
            "-of", "default=noprint_wrappers=1:nokey=1",
            fileURL.path
        ]
        
        return await withCheckedContinuation { continuation in
            ffmpegExecutionQueue.async {
                do {
                    // Use ffprobe directly with the new API
                    let (exitCode, output) = try SwiftFFmpeg.execute(arguments, tool: .ffprobe)
                    
                    // ffprobe returns 0 on success
                    // If audio streams exist, output will contain "audio" (one per stream)
                    // If no audio streams, output will be empty
                    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasAudio = exitCode == 0 && trimmedOutput.contains("audio")
                    
                    logOutput("ffprobe result: exitCode=\(exitCode), hasAudio=\(hasAudio), output=\(trimmedOutput.isEmpty ? "(empty)" : trimmedOutput)")
                    
                    continuation.resume(returning: hasAudio)
                } catch SwiftFFmpegError.executionFailed(let code) {
                    logOutput("ffprobe failed with exit code \(code)")
                    // If ffprobe fails, assume it has audio to avoid unnecessary remuxing
                    continuation.resume(returning: true)
                } catch {
                    logOutput("Error checking for audio tracks: \(error.localizedDescription)")
                    // If we can't check, assume it has audio to avoid unnecessary remuxing
                    continuation.resume(returning: true)
                }
            }
        }
    }

    func getAudioCodecName(fileURL: URL) async -> String? {
        logOutput("Checking audio codec using ffprobe: \(fileURL.path)")
        
        let arguments = [
            "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", "stream=codec_name",
            "-of", "json",
            fileURL.path
        ]
        
        return await withCheckedContinuation { continuation in
            ffmpegExecutionQueue.async {
                do {
                    let (exitCode, output) = try SwiftFFmpeg.execute(arguments, tool: .ffprobe)
                    let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    var codecName: String? = nil
                    
                    if let jsonStart = trimmedOutput.firstIndex(of: "{"),
                       let jsonEnd = trimmedOutput.lastIndex(of: "}") {
                        let jsonString = String(trimmedOutput[jsonStart...jsonEnd])
                        if let data = jsonString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let streams = json["streams"] as? [[String: Any]] {
                            codecName = streams.compactMap { $0["codec_name"] as? String }.first
                        }
                    } else if trimmedOutput.lowercased().contains("mp3") {
                        codecName = "mp3"
                    }
                    
                    if exitCode == 0, let codecName = codecName, !codecName.isEmpty {
                        logOutput("ffprobe audio codec result: \(codecName)")
                        continuation.resume(returning: codecName)
                    } else {
                        if exitCode == 0 && !trimmedOutput.isEmpty {
                            logOutput("ffprobe codec output unrecognized: \(trimmedOutput)")
                        } else {
                            logOutput("ffprobe failed to detect codec (exitCode=\(exitCode))")
                        }
                        continuation.resume(returning: nil)
                    }
                } catch SwiftFFmpegError.executionFailed(let code) {
                    logOutput("ffprobe codec check failed with exit code \(code)")
                    continuation.resume(returning: nil)
                } catch {
                    logOutput("Error checking audio codec: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
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
        if enableFFmpegLogs {
            ffmpegLogBufferQueue.sync {
                ffmpegLogBuffer.removeAll(keepingCapacity: true)
                ffmpegLogWindowStart = Date.distantPast
                ffmpegLogWindowCount = 0
                ffmpegLogDroppedCount = 0
            }
        }
        
        // Set log level and handler synchronously
        if enableFFmpegLogs {
            SwiftFFmpeg.setLogLevel(.debug)
        } else {
            SwiftFFmpeg.setLogLevel(.quiet)
        }
        
        // Create a thread-safe progress handler wrapper
        let progressQueue = DispatchQueue(label: "com.ffmpeg.progress")
        var currentProgressHandler: ((String) -> Void)? = progressHandler
        var lastProgressUpdate = Date.distantPast
        let progressUpdateInterval: TimeInterval = 0.25
        
        // Set log handler thread-safely
        logHandlerLock.lock()
        SwiftFFmpeg.setLogHandler { [weak self] level, message in
            guard let self = self else { return }
            
            // Thread-safe append (always collect for error reporting)
            self.logQueue.sync {
                self.logMessages.append(message)
                if self.logMessages.count > self.ffmpegLogMaxStoredLines {
                    let overflow = self.logMessages.count - self.ffmpegLogMaxStoredLines
                    self.logMessages.removeFirst(overflow)
                }
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
                self.enqueueFFmpegLog(formattedMessage)
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
                            let now = Date()
                            if now.timeIntervalSince(lastProgressUpdate) >= progressUpdateInterval {
                                lastProgressUpdate = now
                                currentProgressHandler?("Processing: \(time)")
                            }
                        }
                    } else {
                        // Sometimes time is at the end of the line
                        let time = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !time.isEmpty {
                            progressQueue.async {
                                let now = Date()
                                if now.timeIntervalSince(lastProgressUpdate) >= progressUpdateInterval {
                                    lastProgressUpdate = now
                                    currentProgressHandler?("Processing: \(time)")
                                }
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
                self.flushFFmpegLogBuffer()
                
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
                self.flushFFmpegLogBuffer()
                
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
                    let (exitCode, output) = try SwiftFFmpeg.execute(arguments, tool: .ffmpeg)
                    
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
