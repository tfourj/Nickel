//
//  DownloadManager.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//


import Foundation
import DeviceCheck
import UIKit

class DownloadManager {
    static let shared = DownloadManager()
    
    var settings: SettingsModel = SettingsModel()
    private var shouldCancel = false
    
    // Default values; these will be used if custom values aren’t set in Settings.
    private let NONE = ""
    private let defaultAuthType = "Api-Key"
    
    static let defaultRequestBody: [String: Any] = [
        "videoQuality": "1080",
        "audioFormat": "mp3",
        "audioBitrate": "128",
        "downloadMode": "auto",
        "localProcessing": "preferred",
    ]

    enum CobaltDownloadResult {
        case success(URL, String?)
        case pickerOptions([PickerOption])
        case localProcessing(LocalProcessingResponse)
    }

    func fetchCobaltURL(
        inputURL: URL,
        downloadModeOverride: String? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) async throws -> CobaltDownloadResult {
        // Reset cancellation flag
        self.shouldCancel = false
        
        // Start background task to ensure completion even if app goes to background
        let backgroundTaskID = await UIApplication.shared.beginBackgroundTask(withName: "CobaltDownload") {
            // This will be called if the background task expires
            logOutput("⚠️ Background task expired for Cobalt download")
        }
        defer {
            if backgroundTaskID != .invalid {
                Task { @MainActor in
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                    logOutput("🔵 Ended background task for Cobalt download")
                }
            }
        }
        
        logOutput("Starting fetchCobaltURL with input URL: \(inputURL.absoluteString)")

        let storedAPIURL = settings.customAPIURL
        let storedAPIKey = settings.customAPIKey
        let authType = settings.authMethod

        logOutput("Loaded config - API URL: \(storedAPIURL), Auth Type: \(authType)")

        var apiURL: URL

        if authType.contains("Nickel-Auth") {
            logOutput("Fetching Nickel-Auth URL from AppAttestClient")
            let appAttestClient = AppAttestClient()
            apiURL = appAttestClient.buildEndpointURL(path: "ios-request")
        } else {
            guard let customURL = URL(string: storedAPIURL) else {
                logOutput("❌ Invalid API URL in UserDefaults")
                throw NSError(domain: "ConfigError", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
            }
            apiURL = customURL
        }

        // Load custom request body from UserDefaults or use default
        var requestBody: [String: Any] = {
            if let savedBodyString = UserDefaults.standard.string(forKey: "customRequestBody"),
               let data = savedBodyString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                logOutput("Loading custom request body")
                return dict
            }
            return DownloadManager.defaultRequestBody
        }()
        
        // Add URL and api-url to the request body
        requestBody["url"] = inputURL.absoluteString
        if authType.contains("Nickel-Auth") {
            requestBody["api-url"] = storedAPIURL
        }

        // Override downloadMode if provided
        if let override = downloadModeOverride {
            requestBody["downloadMode"] = override
        }
        
        logOutput("Request body: \(requestBody)")

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // Set the Authorization header
        if authType.contains("Nickel-Auth") {
            var authValue: String
            let appAttestClient = AppAttestClient()
            
            // Check for cancellation before starting auth
            if shouldCancel?() == true || self.shouldCancel {
                throw CancellationError()
            }
            
            // Send initial progress update
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Starting authentication process..."])
            }
            
            // Use the new background-safe method
            do {
                authValue = try await appAttestClient.ensureValidTempKey()
                if shouldCancel?() == true || self.shouldCancel { throw CancellationError() }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Authentication completed successfully"])
                }
            } catch {
                if error is CancellationError {
                    throw error
                }
                logOutput("❌ AppAttest authentication failed: \(error.localizedDescription)")
                throw NSError(domain: "AppAttest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Authentication failed: \(error.localizedDescription)"])
            }

            request.setValue("Nickel-Auth \(authValue)", forHTTPHeaderField: "Authorization")
        } else if authType != "None" {
            let authValue = "\(authType) \(storedAPIKey)"
            logOutput("Auth Header: \(authValue)")
            request.setValue(authValue, forHTTPHeaderField: "Authorization")
        } else {
            logOutput("Auth value is set to none so Authorization Headers won't be set")
        }

        // Send the request
        logOutput("Sending request to \(apiURL.absoluteString)")
        if shouldCancel?() == true || self.shouldCancel { throw CancellationError() }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Sending request to API url"])
        }
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logOutput("❌ No HTTP response received")
            throw URLError(.badServerResponse)
        }

        logOutput("Received response with status code: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 404 {
            logOutput("❌ Server unavailable: Received 404 Not Found")
            throw NSError(domain: "CobaltAPI", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Server unavailable. Please check the API URL or try again later."])
        }

        if httpResponse.statusCode != 200 {
            let errorDetails = String(data: data, encoding: .utf8) ?? "Unknown error"
            logOutput("❌ API Error Response: \(errorDetails)")
            throw NSError(domain: "CobaltAPI", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: errorDetails])
        }

        // Parse the JSON response
        logOutput("Parsing JSON response...")
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = jsonObject["status"] as? String else {
            logOutput("❌ Failed to extract status from JSON")
            throw NSError(domain: "ParsingError", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to extract status from JSON"])
        }

        logOutput("API returned status: \(status)")

        switch status {
        case "redirect", "stream", "tunnel":
            guard let mediaURLString = jsonObject["url"] as? String,
                  let mediaURL = URL(string: mediaURLString) else {
                logOutput("❌ Failed to extract URL from JSON")
                throw NSError(domain: "ParsingError", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to extract URL from JSON"])
            }
            // Extract filename from response if available
            let filename = jsonObject["filename"] as? String
            logOutput("✅ Download URL received: \(mediaURL.absoluteString), filename: \(filename ?? "nil")")
            return .success(mediaURL, filename)
            
        case "picker":
            logOutput("Handling picker response...")
            guard let pickerArray = jsonObject["picker"] as? [[String: Any]] else {
                logOutput("❌ Failed to extract picker options")
                throw NSError(domain: "ParsingError", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to extract picker options"])
            }

            var options = pickerArray.compactMap { item -> PickerOption? in
                guard let urlString = item["url"] as? String, let url = URL(string: urlString) else { return nil }

                let type = item["type"] as? String ?? "Unknown"
                return PickerOption(label: type, url: url)
            }

            // Handle audio separately if it exists
            if let audioURLString = jsonObject["audio"] as? String, let audioURL = URL(string: audioURLString) {
                options.append(PickerOption(label: "audio", url: audioURL))
            }

            logOutput("✅ Picker options found: \(options.count) options")
            logOutput("Picker details: \(options)")

            return .pickerOptions(options)
            
        case "error":
            logOutput("❌ API returned an error status")
            throw NSError(domain: "CobaltAPI", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "API returned an error."])
            
        case "local-processing":
            logOutput("Handling local-processing response...")
            
            // Debug: Print the full response
            if let responseString = String(data: data, encoding: .utf8) {
                logOutput("🔍 Full API Response: \(responseString)")
            }
            
            // Parse the local processing response
            guard let type = jsonObject["type"] as? String,
                  let service = jsonObject["service"] as? String,
                  let tunnel = jsonObject["tunnel"] as? [String],
                  let outputDict = jsonObject["output"] as? [String: Any],
                  let outputFilename = outputDict["filename"] as? String,
                  !tunnel.isEmpty else {
                logOutput("❌ Failed to extract local-processing details")
                throw NSError(domain: "ParsingError", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to extract local-processing details"])
            }
            
            // The tunnel array contains the download URLs
            let outputURL = tunnel[0]
            
            let output = OutputDetails(
                url: outputURL,
                filename: outputFilename,
                size: outputDict["size"] as? Int,
                format: outputDict["type"] as? String
            )
            
            var audio: AudioDetails? = nil
            // Check for audio object first (preferred method)
            if let audioDict = jsonObject["audio"] as? [String: Any],
               let audioURL = audioDict["url"] as? String,
               let audioFilename = audioDict["filename"] as? String {
                audio = AudioDetails(
                    url: audioURL,
                    filename: audioFilename,
                    size: audioDict["size"] as? Int,
                    format: audioDict["format"] as? String
                )
                logOutput("✅ Audio details found from audio object")
            }
            // For merge operations without audio object, the second tunnel URL is the audio file
            else if type == "merge" && tunnel.count > 1 {
                let audioURL = tunnel[1]
                // Create a more appropriate audio filename based on the output filename
                let audioFilename: String
                if outputFilename.hasSuffix(".mp4") {
                    audioFilename = outputFilename.replacingOccurrences(of: ".mp4", with: "_audio.m4a")
                } else {
                    // If the output filename doesn't end with .mp4, just append _audio.m4a
                    audioFilename = outputFilename + "_audio.m4a"
                }
                audio = AudioDetails(
                    url: audioURL,
                    filename: audioFilename,
                    size: nil,
                    format: "audio/m4a"
                )
                logOutput("✅ Audio URL found for merge (fallback method) - filename: \(audioFilename)")
            }
            
            let localProcessingResponse = LocalProcessingResponse(
                status: status,
                type: type,
                service: service,
                tunnel: tunnel,
                output: output,
                audio: audio,
                isHLS: jsonObject["isHLS"] as? Bool
            )
            
            logOutput("✅ Local processing response parsed: type=\(type), service=\(service)")
            return .localProcessing(localProcessingResponse)
            
        default:
            logOutput("❌ Unexpected API response: \(status)")
            throw NSError(domain: "CobaltAPI", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected API response."])
        }
    }
    
    func cancelDownload() {
        shouldCancel = true
        logOutput("🛑 DownloadManager cancellation requested")
    }
}
