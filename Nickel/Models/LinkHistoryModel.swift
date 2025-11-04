//
//  LinkHistoryModel.swift
//  Nickel
//
//  Created by TfourJ
//

import Foundation

struct LinkHistoryEntry: Codable, Identifiable {
    let id: UUID
    let url: String
    let downloadMode: String // "audio", "auto", or "mute"
    let timestamp: Date
    
    init(id: UUID = UUID(), url: String, downloadMode: String, timestamp: Date = Date()) {
        self.id = id
        self.url = url
        self.downloadMode = downloadMode
        self.timestamp = timestamp
    }
}

class LinkHistoryManager {
    static let shared = LinkHistoryManager()
    private let maxEntries = 10
    private let userDefaultsKey = "linkHistoryEntries"
    
    private init() {}
    
    func saveEntry(_ entry: LinkHistoryEntry) {
        var entries = getAllEntries()
        
        // Remove entry if it already exists (to avoid duplicates)
        entries.removeAll { $0.id == entry.id }
        
        // Add new entry at the beginning (most recent first)
        entries.insert(entry, at: 0)
        
        // Remove oldest entries if over limit
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            logOutput("Saved link history entry: \(entry.url) (mode: \(entry.downloadMode))")
        }
    }
    
    func getAllEntries() -> [LinkHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let entries = try? JSONDecoder().decode([LinkHistoryEntry].self, from: data) else {
            return []
        }
        // Return sorted by timestamp (most recent first)
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
    
    func removeEntry(id: UUID) {
        var entries = getAllEntries()
        entries.removeAll { $0.id == id }
        
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            logOutput("Removed link history entry: \(id)")
        }
    }
    
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        logOutput("Cleared all link history entries")
    }
    
    func addEntry(url: String, downloadMode: String) {
        let entry = LinkHistoryEntry(url: url, downloadMode: downloadMode)
        saveEntry(entry)
    }
}

