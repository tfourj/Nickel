//
//  LenghtExtractor.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import Foundation
import AVFoundation

/// Utility class for extracting accurate media durations
class LenghtExtractor {
    
    /// Extracts the most accurate duration from a media file
    /// Tries to read from mvhd atom first for all formats, falls back to AVFoundation
    static func extractDuration(from url: URL) async throws -> Double {
        // Try MP4 duration extraction for all formats first
        if let lenght = extractLenght(url: url) {
            logOutput("lenght for \(url.lastPathComponent) is: \(lenght) seconds")
            return lenght
        } else {
            logOutput("Failed to extract lenght for \(url.lastPathComponent), falling back to AVFoundation")
        }
        
        // Fallback to AVFoundation for all cases
        return try await extractAVFoundationDuration(from: url)
    }
    
    /// Extracts duration using AVFoundation
    private static func extractAVFoundationDuration(from url: URL) async throws -> Double {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationInSeconds = CMTimeGetSeconds(duration)
        
        guard durationInSeconds.isFinite && durationInSeconds > 0 else {
            throw DurationExtractionError.extractionFailed("Invalid or zero duration for file: \(url.lastPathComponent)")
        }
        
        logOutput("Using AVFoundation duration: \(durationInSeconds) seconds")
        return durationInSeconds
    }
    
    /// Extracts the duration from the 'mvhd' atom in the 'moov' box of an MP4 file.
    /// Returns duration in seconds, or nil if not found or not an MP4.
    private static func extractLenght(url: URL) -> Double? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        
        func readUInt32() -> UInt32? {
            let data = try? file.read(upToCount: 4)
            guard let bytes = data, bytes.count == 4 else { return nil }
            return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        }
        
        while true {
            guard let boxSize = readUInt32() else { break }
            guard let boxTypeData = try? file.read(upToCount: 4),
                  let boxType = String(data: boxTypeData, encoding: .ascii) else { break }
            
            if boxType == "moov" {
                guard let currentOffset = try? file.offset() else { break }
                let moovEnd = Int(currentOffset) + Int(boxSize) - 8
                while true {
                    guard let atomOffset = try? file.offset(), Int(atomOffset) < moovEnd else { break }
                    guard let atomSize = readUInt32() else { break }
                    guard let atomTypeData = try? file.read(upToCount: 4),
                          let atomType = String(data: atomTypeData, encoding: .ascii) else { break }
                    
                    if atomType == "mvhd" {
                        _ = try? file.read(upToCount: 4) // version + flags
                        _ = try? file.read(upToCount: 8) // creation + modification time
                        guard let timescale = readUInt32(),
                              let duration = readUInt32() else { return nil }
                        return Double(duration) / Double(timescale)
                    } else {
                        _ = try? file.read(upToCount: Int(atomSize) - 8)
                    }
                }
            } else {
                _ = try? file.read(upToCount: Int(boxSize) - 8)
            }
        }
        return nil
    }
}

/// Errors that can occur during duration extraction
enum DurationExtractionError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidFormat(String)
    case extractionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let message):
            return "File Not Found: \(message)"
        case .invalidFormat(let message):
            return "Invalid Format: \(message)"
        case .extractionFailed(let message):
            return "Extraction Failed: \(message)"
        }
    }
} 