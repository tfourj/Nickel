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
    private let serverURL = URL(string: "https://getnickel.site")!

    func attestKey() async throws -> String {
        let service = DCAppAttestService.shared
        guard service.isSupported else {
            logOutput("❌ App Attest not supported on this device.")
            throw NSError(domain: "AppAttest", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Attest not supported on this device."])
        }
        logOutput("✅ App Attest is supported on this device.")

        guard try await isServerAvailable() else {
            logOutput("❌ Server is unavailable.")
            throw NSError(domain: "AppAttest", code: 5, userInfo: [NSLocalizedDescriptionKey: "Server is unavailable."])
        }
        logOutput("✅ Server is available.")

        let challenge = try await fetchChallenge()

        let keyId = try await service.generateKey()

        let clientDataHash = Data(SHA256.hash(data: challenge.data(using: .utf8)!))

        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)

        let tempKey = try await sendAttestationToServer(attestation: attestation, challenge: challenge, keyId: keyId)

        UserDefaults.standard.set(tempKey, forKey: "TempKey")

        return tempKey
    }

    private func isServerAvailable() async throws -> Bool {
        let healthCheckURL = serverURL.appendingPathComponent("/ios-challenge")
        logOutput("Checking server availability at: \(healthCheckURL.absoluteString)")

        var request = URLRequest(url: healthCheckURL)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                logOutput("✅ Server responded with status code 200.")
                return true
            } else {
                logOutput("❌ Server responded with status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return false
            }
        } catch {
            logOutput("❌ Failed to reach server: \(error.localizedDescription)")
            return false
        }
    }

    private func fetchChallenge() async throws -> String {
        let challengeURL = serverURL.appendingPathComponent("/ios-challenge")

        let (data, _) = try await URLSession.shared.data(from: challengeURL)

        let json = try JSONDecoder().decode([String: String].self, from: data)
        guard let challenge = json["challenge"] else {
            logOutput("❌ Failed to fetch challenge from server.")
            throw NSError(domain: "AppAttest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch challenge from server."])
        }

        logOutput("Challenge fetched successfully")
        return challenge
    }

    private func sendAttestationToServer(attestation: Data, challenge: String, keyId: String) async throws -> String {
        let url = serverURL.appendingPathComponent("/ios-auth")
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
}
