import Foundation

// Test function to verify version comparison logic
func testVersionComparisons() {
    // Test cases - simplified to focus on update needed or not
    let testCases: [(current: String, remote: String, betaEnabled: Bool, shouldUpdate: Bool, description: String)] = [
        // Basic version comparisons
        ("1.0.0", "1.0.1", false, true, "Regular update"),
        ("1.0.1", "1.0.0", false, false, "Current newer than remote"),
        ("1.0.0", "1.0.0", false, false, "Same version"),
        
        // Beta vs Stable
        ("1.4.1", "1.4.2b2", true, true, "Beta update available with beta enabled"),
        ("1.4.1", "1.4.2b2", false, false, "No update needed (beta disabled)"),
        ("1.4.2b1", "1.4.2", false, true, "Stable update from beta"),
        
        // Beta vs Beta
        ("1.4.2b1", "1.4.2b2", true, true, "Newer beta available"),
        ("1.4.2b2", "1.4.2b1", true, false, "Current beta newer than remote"),
        
        // Same version, beta vs stable
        ("1.4.2b3", "1.4.2", false, true, "Stable update from same version beta"),
        ("1.4.2", "1.4.2b3", true, false, "No update from stable to same version beta"),
        
        // Edge cases
        ("1.5.0", "1.4.9b10", true, false, "Newer version to older beta"),
        ("1.4.0", "1.5.0b1", true, true, "Beta update with higher major version"),
        ("1.4.0", "1.5.0b1", false, false, "Beta disabled for higher major version")
    ]
    
    print("==== VERSION UPDATE TEST CASES ====")
    for (index, testCase) in testCases.enumerated() {
        UserDefaults.standard.set(testCase.betaEnabled, forKey: "enableBetaUpdates")
        let result = compareVersions(testCase.current, testCase.remote)
        let updateNeeded = result == .orderedAscending
        
        let passOrFail = (updateNeeded == testCase.shouldUpdate) ? "✅ PASS" : "❌ FAIL"
        
        print("Test \(index + 1): Current \(testCase.current) vs Remote \(testCase.remote) [Beta: \(testCase.betaEnabled)]")
        print("  Expected: \(testCase.shouldUpdate ? "Update needed" : "No update needed") - \(testCase.description)")
        print("  Actual: \(updateNeeded ? "Update needed" : "No update needed")")
        print("  Result: \(passOrFail)")
        print("---")
    }
    print("================================")
}
