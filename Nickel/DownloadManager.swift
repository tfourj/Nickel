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
    private let defaultAPIURLString = ""
    private let defaultAuthKey = ""
    private let authType = "Api-Key"
    
    func fetchCobaltURL(inputURL: URL) async throws -> URL {
        // Get custom API URL and key from UserDefaults, or fall back to defaults.
        let storedAPIURL = UserDefaults.standard.string(forKey: "customAPIURL") ?? defaultAPIURLString
        let storedAPIKey = UserDefaults.standard.string(forKey: "customAPIKey") ?? defaultAuthKey
        
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
            return try await downloadVideoFile(from: mediaURL)
        case "picker":
            throw NSError(domain: "CobaltAPI", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Multiple options available. Please refine your selection."])
        case "error":
            if let errorObject = jsonObject["error"] as? [String: Any],
               let errorCode = errorObject["code"] as? String {
                throw NSError(domain: "CobaltAPI", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "API returned an error: \(errorCode)"])
            } else {
                throw NSError(domain: "CobaltAPI", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "An error occurred while processing your request."])
            }
        default:
            throw NSError(domain: "CobaltAPI", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected API response."])
        }
    }
    
    func downloadVideoFile(from url: URL) async throws -> URL {
        let (downloadURL, _) = try await URLSession.shared.download(from: url)
        let tempDir = FileManager.default.temporaryDirectory
        let targetURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
        try FileManager.default.moveItem(at: downloadURL, to: targetURL)
        return targetURL
    }
}
