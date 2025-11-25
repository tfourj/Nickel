//
//  FFmpegTest.swift
//  Nickel
//
//  Created by TfourJ on 25. 11. 25.
//

import Foundation
import SwiftFFmpeg

func TestFFmpegVersions() {
    logOutput("🔍 Testing FFmpeg and FFprobe availability...")
    
    // Run tests sequentially to avoid interference
    Task {
        // Test FFmpeg version first
        do {
            let (exitCode, output) = try SwiftFFmpeg.execute(["-version"], tool: .ffmpeg)
            if exitCode == 0 {
                let versionLine = output.components(separatedBy: .newlines).first(where: { $0.contains("ffmpeg version") }) ?? "Unknown"
                logOutput("✅ FFmpeg is available: \(versionLine)")
            } else {
                logOutput("⚠️ FFmpeg returned exit code \(exitCode)")
                if !output.isEmpty {
                    logOutput("FFmpeg output: \(output)")
                }
            }
        } catch {
            logOutput("❌ FFmpeg test failed: \(error.localizedDescription)")
        }
        
        // Small delay between tests
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Test FFprobe version
        do {
            let (exitCode, output) = try SwiftFFmpeg.execute(["-version"], tool: .ffprobe)
            if exitCode == 0 {
                let versionLine = output.components(separatedBy: .newlines).first(where: { $0.contains("ffprobe version") }) ?? "Unknown"
                logOutput("✅ FFprobe is available: \(versionLine)")
            } else {
                logOutput("⚠️ FFprobe returned exit code \(exitCode)")
                if !output.isEmpty {
                    logOutput("FFprobe output: \(output)")
                }
            }
        } catch {
            logOutput("❌ FFprobe test failed: \(error.localizedDescription)")
        }
    }
}

