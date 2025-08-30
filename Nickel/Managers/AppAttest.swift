//
//  AppAttest.swift
//  Nickel
//
//  Created by TfourJ on 12. 4. 25.
//
import Foundation
import DeviceCheck
import CryptoKit
import UIKit

class AppAttestClient {
    var settings: SettingsModel = SettingsModel()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    var serverURL: URL {
        if !settings.customAuthServerURL.isEmpty,
           let customURL = URL(string: settings.customAuthServerURL),
           settings.authMethod == "Nickel-Auth (Custom)" {
            logOutput("Using custom authentication server: \(customURL)")
            return customURL
        }
        return URL(string: "https://auth.getnickel.site")!
    }

    func attestKey() async throws -> String {
        // Start background task to ensure completion even if app goes to background
        beginBackgroundTask()
        defer { endBackgroundTask() }
        
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            logOutput("❌ App Attest not supported on this device.")
            throw NSError(domain: "AppAttest", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Attest not supported on this device."])
        }
        logOutput("✅ App Attest is supported on this device.")

        // Send progress update
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Fetching authentication challenge..."])
        }

        let challenge = try await fetchChallenge()

        // Send progress update
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Generating device key..."])
        }

        let keyId = try await service.generateKey()

        // Send progress update
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Creating device attestation..."])
        }

        let clientDataHash = Data(SHA256.hash(data: challenge.data(using: .utf8)!))

        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)

        // Send progress update
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Validating with authentication server..."])
        }

        let tempKey = try await sendAttestationToServer(attestation: attestation, challenge: challenge, keyId: keyId)

        UserDefaults.standard.set(tempKey, forKey: "TempKey")

        return tempKey
    }

    func buildEndpointURL(path: String) -> URL {
        let baseURL = serverURL.absoluteString
        let cleanBaseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return URL(string: cleanBaseURL + "/" + path)!
    }

    private func fetchChallenge() async throws -> String {
        let challengeURL = buildEndpointURL(path: "ios-challenge")
        logOutput("Fetching challenge from: \(challengeURL.absoluteString)")
        
        var request = URLRequest(url: challengeURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30 // Increase timeout for background operations

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                logOutput("❌ Server responded with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw NSError(domain: "AppAttest", code: 5, userInfo: [NSLocalizedDescriptionKey: "Server is unavailable."])
            }

            let json = try JSONDecoder().decode([String: String].self, from: data)
            guard let challenge = json["challenge"] else {
                logOutput("❌ Failed to fetch challenge from server.")
                throw NSError(domain: "AppAttest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch challenge from server."])
            }

            logOutput("✅ Challenge fetched successfully")
            return challenge
        } catch {
            logOutput("❌ Failed to reach server: \(error.localizedDescription)")
            throw NSError(domain: "AppAttest", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to reach server."])
        }
    }

    private func sendAttestationToServer(attestation: Data, challenge: String, keyId: String) async throws -> String {
        let url = buildEndpointURL(path: "ios-auth")
        logOutput("Sending attestation to server")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30 // Increase timeout for background operations

        let body: [String: Any] = [
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge,
            "keyId": keyId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            logOutput("❌ Failed to validate attestation with server. Status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw NSError(domain: "AppAttest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to validate attestation with server."])
        }

        let json = try JSONDecoder().decode([String: String].self, from: data)
        guard let tempKey = json["tempKey"] else {
            logOutput("❌ Server did not return a temporary key.")
            throw NSError(domain: "AppAttest", code: 4, userInfo: [NSLocalizedDescriptionKey: "Server did not return a temporary key."])
        }

        return tempKey
    }

    func validateTempKey(_ tempKey: String) async throws -> Bool {
        // Start background task for validation
        beginBackgroundTask()
        defer { endBackgroundTask() }
        
        // Send progress update
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Validating authentication token..."])
        }
        
        let validateURL = buildEndpointURL(path: "ios-validate")
        
        var request = URLRequest(url: validateURL)
        request.httpMethod = "POST"
        request.setValue("Nickel-Auth \(tempKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30 // Increase timeout for background operations

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
            // Check if response is JSON (API error) or HTML (Cloudflare/other errors)
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            let isJSONResponse = contentType.contains("application/json")

            if isJSONResponse {
                // Parse JSON error response
                let errorDetails = String(data: data, encoding: .utf8) ?? "Unknown error"
                logOutput("❌ TempKey validation failed with JSON error: \(errorDetails)")
                throw NSError(domain: "ValidationError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorDetails])
            } else {
                // HTML response (likely Cloudflare or server error)
                logOutput("❌ TempKey validation failed with HTML error (likely Cloudflare): Status \(httpResponse.statusCode)")
                let genericError = "Authentication server temporarily unavailable. Please try again later."
                throw NSError(domain: "ValidationError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: genericError])
            }
        }
    }

    func regenerateTempKey() async throws -> String {
        // Start background task for regeneration
        beginBackgroundTask()
        defer { endBackgroundTask() }
        
        // Send progress update
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Generating new authentication key..."])
        }
        
        let newTempKey = try await attestKey()
        logOutput("Generated new TempKey")
        UserDefaults.standard.set(newTempKey, forKey: "TempKey")
        return newTempKey
    }
    
    // MARK: - Background Task Management
    
    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AppAttestOperation") { [weak self] in
            self?.endBackgroundTask()
        }
        
        if backgroundTaskID != .invalid {
            logOutput("🔵 Started background task for AppAttest operation")
        }
    }
    
    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        logOutput("🔵 Ended background task for AppAttest operation")
    }
    
    // MARK: - Background-Safe Operations
    
    /// Validates or regenerates temp key with background support and retry logic
    func ensureValidTempKey() async throws -> String {
        // Check if we have a stored temp key
        if let existingTempKey = UserDefaults.standard.string(forKey: "TempKey") {
            // Send progress update
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("ShowMessageUI"), object: nil, userInfo: ["text": "Checking existing authentication..."])
            }
            
            do {
                let isValid = try await validateTempKey(existingTempKey)
                if isValid {
                    logOutput("✅ Existing TempKey is valid")
                    return existingTempKey
                }
            } catch {
                logOutput("⚠️ TempKey validation failed, will regenerate: \(error.localizedDescription)")
            }
        }
        
        // Regenerate if no key exists or validation failed
        logOutput("🔄 Regenerating TempKey...")
        return try await regenerateTempKey()
    }
}
