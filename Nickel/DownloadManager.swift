//
//  DownloadManager.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//


import Foundation

class DownloadManager {
    static let shared = DownloadManager()
    
    // Default values; these will be used if custom values aren’t set in Settings.
    private let NONE = ""
    private let defaultAuthType = "Api-Key"
    
    enum CobaltDownloadResult {
        case success(URL)
        case pickerOptions([PickerOption])
    }

    func fetchCobaltURL(inputURL: URL) async throws -> CobaltDownloadResult {
        // Get custom API URL and key from UserDefaults, or fall back to defaults.
        let storedAPIURL = UserDefaults.standard.string(forKey: "customAPIURL") ?? NONE
        let storedAPIKey = UserDefaults.standard.string(forKey: "customAPIKey") ?? NONE
        let authType = UserDefaults.standard.string(forKey: "authMethod") ?? defaultAuthType
        
        guard let apiURL = URL(string: storedAPIURL) else {
            throw NSError(domain: "ConfigError", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        let requestBody: [String: Any] = [
            "url": inputURL.absoluteString,
            "videoQuality": "1080",
            "audioFormat": "mp3",
            "audioBitrate": "128",
            "filenameStyle": "classic",
            "downloadMode": "auto",
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Set the Authorization header
        let authValue = "\(authType) \(storedAPIKey)"
        logOutput("Auth Value: \(authValue)")
        request.setValue(authValue, forHTTPHeaderField: "Authorization")
        
        // Send the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorDetails = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "CobaltAPI", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: errorDetails])
        }
        
        // Parse the JSON response
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = jsonObject["status"] as? String else {
            throw NSError(domain: "ParsingError", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to extract status from JSON"])
        }
        
        switch status {
        case "redirect", "stream", "tunnel":
            guard let mediaURLString = jsonObject["url"] as? String,
                  let mediaURL = URL(string: mediaURLString) else {
                throw NSError(domain: "ParsingError", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to extract URL from JSON"])
            }
            return .success(try await downloadVideoFile(from: mediaURL))
            
        case "picker":
            // Now accessing the correct 'picker' array
            guard let pickerArray = jsonObject["picker"] as? [[String: Any]] else {
                throw NSError(domain: "ParsingError", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to extract picker options"])
            }
            
            let options = pickerArray.compactMap { item -> PickerOption? in
                guard let urlString = item["url"] as? String, let url = URL(string: urlString) else { return nil }
                
                let type = item["type"] as? String ?? "Unknown"
                return PickerOption(label: type, url: url)
            }
            
            // Log the options for debugging
            logOutput("Picker options: \(options)")

            return .pickerOptions(options)
            
        case "error":
            throw NSError(domain: "CobaltAPI", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "API returned an error."])
            
        default:
            throw NSError(domain: "CobaltAPI", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected API response."])
        }
    }
    
    func downloadVideoFile(from url: URL) async throws -> URL {
        clearTempFolder()
        let (downloadURL, _) = try await URLSession.shared.download(from: url)
        let tempDir = FileManager.default.temporaryDirectory
        let targetURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")

        printTempFolderContents(context: "Before moving file")

        do {
            try FileManager.default.moveItem(at: downloadURL, to: targetURL)
            logOutput("✅ File moved successfully to: \(targetURL)")
        } catch {
            logOutput("❌ Error moving file: \(error.localizedDescription)")
        }

        // Verify if the file exists
        if FileManager.default.fileExists(atPath: targetURL.path) {
            logOutput("✅ File exists at: \(targetURL)")
        } else {
            logOutput("⚠️ File does NOT exist at expected location!")
        }

        printTempFolderContents(context: "After moving file")

        return targetURL
    }
    
    func downloadImageFile(from url: URL) async throws -> URL {
        clearTempFolder()
        let (downloadURL, _) = try await URLSession.shared.download(from: url)
        let tempDir = FileManager.default.temporaryDirectory
        let targetURL = tempDir.appendingPathComponent(UUID().uuidString + ".jpg") // Assuming JPG for simplicity, you can adjust the file extension

        printTempFolderContents(context: "Before moving file")

        do {
            try FileManager.default.moveItem(at: downloadURL, to: targetURL)
            logOutput("✅ Image file moved successfully to: \(targetURL)")
        } catch {
            logOutput("❌ Error moving file: \(error.localizedDescription)")
        }

        // Verify if the file exists
        if FileManager.default.fileExists(atPath: targetURL.path) {
            logOutput("✅ Image file exists at: \(targetURL)")
        } else {
            logOutput("⚠️ Image file does NOT exist at expected location!")
        }

        printTempFolderContents(context: "After moving file")

        return targetURL
    }
    
    func downloadAudioFile(from url: URL) async throws -> URL {
        clearTempFolder()
        let (downloadURL, _) = try await URLSession.shared.download(from: url)
        let tempDir = FileManager.default.temporaryDirectory
        let targetURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp3") // Assuming MP3 for simplicity, adjust as needed

        printTempFolderContents(context: "Before moving file")

        do {
            try FileManager.default.moveItem(at: downloadURL, to: targetURL)
            logOutput("✅ Audio file moved successfully to: \(targetURL)")
        } catch {
            logOutput("❌ Error moving file: \(error.localizedDescription)")
        }

        // Verify if the file exists
        if FileManager.default.fileExists(atPath: targetURL.path) {
            logOutput("✅ Audio file exists at: \(targetURL)")
        } else {
            logOutput("⚠️ Audio file does NOT exist at expected location!")
        }

        printTempFolderContents(context: "After moving file")

        return targetURL
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
