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
    
    // Default values; these will be used if custom values aren’t set in Settings.
    private let NONE = ""
    private let defaultAuthType = "Api-Key"
    
    static let defaultRequestBody: [String: Any] = [
        "videoQuality": "1080",
        "audioFormat": "mp3",
        "audioBitrate": "128",
        "downloadMode": "auto"
    ]

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

        var apiURL: URL

        if authType == "Nickel-Auth" {
            guard let nickelURL = URL(string: "https://getnickel.site/ios-request") else {
                logOutput("❌ Invalid Nickel-Auth URL")
                throw NSError(domain: "ConfigError", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid Nickel-Auth URL"])
            }
            apiURL = nickelURL
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
        if authType == "Nickel-Auth" {
            requestBody["api-url"] = storedAPIURL
        }
        
        logOutput("Request body: \(requestBody)")

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // Set the Authorization header
        if authType == "Nickel-Auth" {
            var authValue: String
            if let tempKey = UserDefaults.standard.string(forKey: "TempKey") {
                logOutput("Validating stored TempKey: \(tempKey)")
                let isValid = try await validateTempKey(tempKey)
                if isValid {
                    authValue = tempKey
                } else {
                    authValue = try await regenerateTempKey()
                }
            } else {
                logOutput("TempKey not found. Generating a new one...")
                authValue = try await regenerateTempKey()
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

    private func validateTempKey(_ tempKey: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "https://getnickel.site/ios-validate")!)
        request.httpMethod = "POST"
        request.setValue("Nickel-Auth \(tempKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        logOutput("Validating TempKey via Authorization header.")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ValidationError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No HTTP response received."])
        }

        if httpResponse.statusCode == 200 {
            logOutput("✅ TempKey validation succeeded.")
            return true
        } else if httpResponse.statusCode == 401 {
            logOutput("❌ TempKey validation failed with 401 Unauthorized. Details: \(String(data: data, encoding: .utf8) ?? "Unknown error")")
            return false
        } else if httpResponse.statusCode == 403 {
            logOutput("❌ TempKey validation failed with 403 Forbidden.")
            return false
        } else {
            let errorDetails = String(data: data, encoding: .utf8) ?? "Unknown error"
            logOutput("❌ TempKey validation failed with status code: \(httpResponse.statusCode). Details: \(errorDetails)")
            throw NSError(domain: "ValidationError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorDetails])
        }
    }

    private func regenerateTempKey() async throws -> String {
        let newTempKey = try await AppAttestClient().attestKey()
        logOutput("Generated new TempKey: \(newTempKey)")
        UserDefaults.standard.set(newTempKey, forKey: "TempKey")
        return newTempKey
    }

    private func generateDeviceCheckToken() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DCDevice.current.generateToken { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data.base64EncodedString())
                } else {
                    continuation.resume(throwing: NSError(domain: "DeviceCheckError", code: 0,
                                                          userInfo: [NSLocalizedDescriptionKey: "Unknown error generating DeviceCheck token."]))
                }
            }
        }
    }
}
