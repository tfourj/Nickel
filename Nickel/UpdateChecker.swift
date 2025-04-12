import Foundation

// GitHub repository info
let githubRepoURL = "https://github.com/tfourj/Nickel/releases"
let versionCheckURL = "https://raw.githubusercontent.com/tfourj/Nickel/refs/heads/main/nickel_ver"

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

        guard let data = data, let remoteVersion = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            completion(nil, "Unable to read version information")
            return
        }

        completion(remoteVersion, nil)
    }.resume()
}

// Helper function to compare semantic versions
func compareVersions(_ version1: String, _ version2: String) -> ComparisonResult {
    let enableBetaUpdates = UserDefaults.standard.bool(forKey: "enableBetaUpdates")
    
    // Check if either version has a beta indicator (e.g., "b")
    let v1IsBeta = version1.contains("b")
    let v2IsBeta = version2.contains("b")
    
    // Extract base version numbers without beta indicators
    let cleanV1 = String(version1.split(separator: "b")[0])
    let cleanV2 = String(version2.split(separator: "b")[0])
    
    // Compare base version numbers first
    let v1Components = cleanV1.components(separatedBy: ".").compactMap { Int($0) }
    let v2Components = cleanV2.components(separatedBy: ".").compactMap { Int($0) }

    // Compare each component of the version number
    for i in 0..<min(v1Components.count, v2Components.count) {
        if v1Components[i] < v2Components[i] {
            // Remote version has higher base number
            // If remote is beta and beta updates aren't enabled, don't suggest update
            if v2IsBeta && !enableBetaUpdates && !v1IsBeta {
                return .orderedDescending // Don't suggest beta update to stable user
            }
            return .orderedAscending // Remote version is newer
        } else if v1Components[i] > v2Components[i] {
            return .orderedDescending // Current version is newer
        }
    }

    // If one version has more components and previous components are equal
    if v1Components.count < v2Components.count {
        if v2IsBeta && !enableBetaUpdates && !v1IsBeta {
            return .orderedDescending // Don't suggest beta update to stable user
        }
        return .orderedAscending // Remote version is newer
    } else if v1Components.count > v2Components.count {
        return .orderedDescending // Current version is newer
    }
    
    // At this point, base versions are the same, handle beta status
    
    // Rule: If base versions are equal but current is beta and remote is stable
    if v1IsBeta && !v2IsBeta {
        return .orderedAscending // Suggest upgrade to stable
    }
    
    // Rule: If base versions are equal but current is stable and remote is beta
    if !v1IsBeta && v2IsBeta {
        // Never suggest downgrade from stable to beta of the same base version
        return .orderedDescending
    }
    
    // Rule: If both are beta, compare beta numbers
    if v1IsBeta && v2IsBeta {
        let v1BetaNum = Int(version1.split(separator: "b").last ?? "0") ?? 0
        let v2BetaNum = Int(version2.split(separator: "b").last ?? "0") ?? 0
        
        if v1BetaNum < v2BetaNum {
            return .orderedAscending // Remote beta is newer
        } else if v1BetaNum > v2BetaNum {
            return .orderedDescending // Current beta is newer
        }
    }

    return .orderedSame // Versions are identical
}