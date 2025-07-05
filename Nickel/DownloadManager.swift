//
//  DownloadManager.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//


import Foundation
import DeviceCheck

class DownloadManager {
    static let shared = DownloadManager()
    
    var settings: SettingsModel = SettingsModel()
    
    // Default values; these will be used if custom values aren’t set in Settings.
    private let NONE = ""
    private let defaultAuthType = "Api-Key"
    
    static let defaultRequestBody: [String: Any] = [
        "videoQuality": "1080",
        "audioFormat": "mp3",
        "audioBitrate": "128",
        "downloadMode": "auto",
        "youtubeHLS": false,
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
            if let tempKey = UserDefaults.standard.string(forKey: "TempKey") {
                let isValid = try await AppAttestClient().validateTempKey(tempKey)
                if shouldCancel?() == true { throw CancellationError() }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Validating authorization key with Auth server"])
                }
                if isValid {
                    authValue = tempKey
                } else {
                    authValue = try await AppAttestClient().regenerateTempKey()
                    if shouldCancel?() == true { throw CancellationError() }
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Authorization key is invalid, regenerating a new one"])
                    }
                }
            } else {
                logOutput("TempKey not found. Generating a new one...")
                authValue = try await AppAttestClient().regenerateTempKey()
                if shouldCancel?() == true { throw CancellationError() }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Authorization key is not found, generating a new one"])
                }
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
        if shouldCancel?() == true { throw CancellationError() }
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
            logOutput("Full JSON response: \(jsonObject)")
            
            // Parse the local processing response
            guard let type = jsonObject["type"] as? String,
                  let service = jsonObject["service"] as? String,
                  let tunnel = jsonObject["tunnel"] as? [String],
                  let outputDict = jsonObject["output"] as? [String: Any],
                  let outputFilename = outputDict["filename"] as? String,
                  !tunnel.isEmpty else {
                logOutput("❌ Failed to extract local-processing details")
                logOutput("Available keys in JSON: \(jsonObject.keys)")
                if let type = jsonObject["type"] { logOutput("Type value: \(type)") }
                if let service = jsonObject["service"] { logOutput("Service value: \(service)") }
                if let tunnel = jsonObject["tunnel"] { logOutput("Tunnel value: \(tunnel)") }
                if let output = jsonObject["output"] { logOutput("Output value: \(output)") }
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
            // For merge operations, the second tunnel URL is the audio file
            if type == "merge" && tunnel.count > 1 {
                let audioURL = tunnel[1]
                let audioFilename = outputFilename.replacingOccurrences(of: ".mp4", with: "_audio.m4a")
                audio = AudioDetails(
                    url: audioURL,
                    filename: audioFilename,
                    size: nil,
                    format: "audio/m4a"
                )
                logOutput("✅ Audio URL found for merge: \(audioURL)")
            } else if let audioDict = jsonObject["audio"] as? [String: Any],
                      let audioURL = audioDict["url"] as? String,
                      let audioFilename = audioDict["filename"] as? String {
                audio = AudioDetails(
                    url: audioURL,
                    filename: audioFilename,
                    size: audioDict["size"] as? Int,
                    format: audioDict["format"] as? String
                )
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
            
            logOutput("✅ Local processing response parsed: type=\(type), service=\(service), tunnel count=\(tunnel.count)")
            return .localProcessing(localProcessingResponse)
            
        default:
            logOutput("❌ Unexpected API response: \(status)")
            throw NSError(domain: "CobaltAPI", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected API response."])
        }
    }
}
