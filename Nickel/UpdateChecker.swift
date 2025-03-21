import Foundation

// GitHub repository info
let githubRepoURL = "https://github.com/tfourj/Nickel/releases"
let versionCheckURL = "https://raw.githubusercontent.com/tfourj/Nickel/refs/heads/main/Nickel.xcodeproj/project.pbxproj"

// Function to check for updates
func checkForUpdates(appVersion: String, completion: @escaping (String?, String?) -> Void) {
    guard let url = URL(string: versionCheckURL) else {
        completion(nil, "Invalid update check URL")
        return
    }

    URLSession.shared.dataTask(with: url) { data, response, error in
        if let error = error {
            completion(nil, "Update check failed: \(error.localizedDescription)")
            return
        }

        guard let data = data, let fileContent = String(data: data, encoding: .utf8) else {
            completion(nil, "Unable to read version information")
            return
        }

        // Extract version number using regex
        let pattern = "SHARED_VERSION_NUMBER\\s*=\\s*([0-9]+\\.[0-9]+\\.[0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: fileContent, range: NSRange(fileContent.startIndex..., in: fileContent)),
              let versionRange = Range(match.range(at: 1), in: fileContent) else {
            completion(nil, "Unable to parse version information")
            return
        }

        let remoteVersion = String(fileContent[versionRange])
        completion(remoteVersion, nil)
    }.resume()
}

// Helper function to compare semantic versions
func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
    // Check if either version has a beta indicator (e.g., "b")
    let v1IsBeta = version1.contains("b")
    let v2IsBeta = version2.contains("b")
    
    // If user is on stable release and remote is beta, don't suggest update
    if !v1IsBeta && v2IsBeta {
        return .orderedDescending // Consider current version "newer" to avoid update
    }
    
    // Extract base version numbers without beta indicators
    let cleanV1 = version1.split(separator: "b")[0]
    let cleanV2 = version2.split(separator: "b")[0]
    
    let v1Components = cleanV1.components(separatedBy: ".").compactMap { Int($0) }
    let v2Components = cleanV2.components(separatedBy: ".").compactMap { Int($0) }

    for i in 0..<min(v1Components.count, v2Components.count) {
        if v1Components[i] < v2Components[i] {
            return .orderedAscending
        } else if v1Components[i] > v2Components[i] {
            return .orderedDescending
        }
    }

    if v1Components.count < v2Components.count {
        return .orderedAscending
    } else if v1Components.count > v2Components.count {
        return .orderedDescending
    }
    
    // If base versions are the same but one is beta, the beta is "older"
    if v1IsBeta && !v2IsBeta {
        return .orderedAscending
    } else if !v1IsBeta && v2IsBeta {
        return .orderedDescending
    }
    
    // If both are beta, compare beta numbers
    if v1IsBeta && v2IsBeta {
        let v1BetaNum = Int(version1.split(separator: "b").last ?? "0") ?? 0
        let v2BetaNum = Int(version2.split(separator: "b").last ?? "0") ?? 0
        
        if v1BetaNum < v2BetaNum {
            return .orderedAscending
        } else if v1BetaNum > v2BetaNum {
            return .orderedDescending
        }
    }

    return .orderedSame
}
