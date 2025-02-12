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
        logOutput("Starting fetchCobaltURL with input URL: \(inputURL.absoluteString)")

        // Get custom API URL and key from UserDefaults, or fall back to defaults.
        let storedAPIURL = UserDefaults.standard.string(forKey: "customAPIURL") ?? NONE
        let storedAPIKey = UserDefaults.standard.string(forKey: "customAPIKey") ?? NONE
        let authType = UserDefaults.standard.string(forKey: "authMethod") ?? defaultAuthType

        logOutput("Loaded config - API URL: \(storedAPIURL), Auth Type: \(authType)")

        guard let apiURL = URL(string: storedAPIURL) else {
            logOutput("❌ Invalid API URL in UserDefaults")
            throw NSError(domain: "ConfigError", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }

        let requestBody: [String: Any] = [
            "url": inputURL.absoluteString,
            "videoQuality": "1080",
            "audioFormat": "mp3",
            "audioBitrate": "128",
            "downloadMode": "auto",
        ]
        
        logOutput("Request body: \(requestBody)")

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // Set the Authorization header
        let authValue = "\(authType) \(storedAPIKey)"
        logOutput("Auth Header: \(authValue)")
        request.setValue(authValue, forHTTPHeaderField: "Authorization")

        // Send the request
        logOutput("Sending request to \(apiURL.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logOutput("❌ No HTTP response received")
            throw URLError(.badServerResponse)
        }

        logOutput("Received response with status code: \(httpResponse.statusCode)")

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
            
            logOutput("✅ Download URL received: \(mediaURL.absoluteString)")
            return .success(mediaURL)
            
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
            
        default:
            logOutput("❌ Unexpected API response: \(status)")
            throw NSError(domain: "CobaltAPI", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected API response."])
        }
    }
}
