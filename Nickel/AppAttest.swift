//
//  AppAttest.swift
//  Nickel
//
//  Created by TfourJ on 12. 4. 25.
//
import Foundation
import DeviceCheck
import CryptoKit

class AppAttestClient {
    var settings: SettingsModel = SettingsModel()

    var serverURL: URL {
        if !settings.customAuthServerURL.isEmpty,
           let customURL = URL(string: settings.customAuthServerURL),
           settings.authMethod == "Nickel-Auth (Custom)" {
            logOutput("Using custom authentication server: \(customURL)")
            return customURL
        }
        return URL(string: "https://getnickel.site")!
    }

    func attestKey() async throws -> String {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            logOutput("❌ App Attest not supported on this device.")
            throw NSError(domain: "AppAttest", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Attest not supported on this device."])
        }
        logOutput("✅ App Attest is supported on this device.")

        let challenge = try await fetchChallenge()

        let keyId = try await service.generateKey()

        let clientDataHash = Data(SHA256.hash(data: challenge.data(using: .utf8)!))

        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)

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
        let validateURL = buildEndpointURL(path: "ios-validate")
        
        var request = URLRequest(url: validateURL)
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

    func regenerateTempKey() async throws -> String {
        let newTempKey = try await attestKey()
        logOutput("Generated new TempKey")
        UserDefaults.standard.set(newTempKey, forKey: "TempKey")
        return newTempKey
    }
}
