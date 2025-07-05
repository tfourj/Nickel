//
//  DebugView.swift
//  Nickel
//
//  Created by TfourJ on 28. 4. 25.
//

import SwiftUI

#if DEBUG
struct DebugView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var showRemoveAlert = false
    @State private var tempKey: String? = UserDefaults.standard.string(forKey: "TempKey")
    @State private var tempFolderContents: [FolderItem] = []
    @State private var documentsFolderContents: [FolderItem] = []
    @State private var cachesFolderContents: [FolderItem] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Temporary Auth Key Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Temporary Auth Key")
                        .font(.headline)
                    if let key = tempKey, !key.isEmpty {
                        Text(key)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        HStack {
                            Button("Refresh") {
                                tempKey = UserDefaults.standard.string(forKey: "TempKey")
                            }
                            .padding(.trailing, 10)
                            Button("Remove Auth Key") {
                                showRemoveAlert = true
                            }
                            .foregroundColor(.red)
                        }
                        .alert("Remove Auth Key?", isPresented: $showRemoveAlert) {
                            Button("Remove", role: .destructive) {
                                UserDefaults.standard.removeObject(forKey: "TempKey")
                                tempKey = nil
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Are you sure you want to remove the temporary auth key?")
                        }
                    } else {
                        Text("No temporary auth key set.")
                            .foregroundColor(.secondary)
                        Button("Refresh") {
                            tempKey = UserDefaults.standard.string(forKey: "TempKey")
                        }
                    }
                }
                
                Divider()
                
                // Folder Browser Section
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text("Download Folders")
                            .font(.headline)
                        Spacer()
                        Button("Refresh All") {
                            loadAllFolderContents()
                        }
                        .disabled(isLoading)
                    }
                    
                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading folder contents...")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Temporary Directory
                    FolderSection(
                        title: "Temporary Directory",
                        subtitle: "Main download and processing folder",
                        path: FileManager.default.temporaryDirectory.path,
                        items: tempFolderContents,
                        onRefresh: { loadTempFolderContents() }
                    )
                    
                    // Documents Directory
                    FolderSection(
                        title: "Documents Directory",
                        subtitle: "App documents folder",
                        path: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "Unknown",
                        items: documentsFolderContents,
                        onRefresh: { loadDocumentsFolderContents() }
                    )
                    
                    // Caches Directory
                    FolderSection(
                        title: "Caches Directory",
                        subtitle: "App cache folder",
                        path: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path ?? "Unknown",
                        items: cachesFolderContents,
                        onRefresh: { loadCachesFolderContents() }
                    )
                }
            }
            .padding()
        }
        .onAppear {
            loadAllFolderContents()
        }
    }
    
    private func loadAllFolderContents() {
        isLoading = true
        loadTempFolderContents()
        loadDocumentsFolderContents()
        loadCachesFolderContents()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isLoading = false
        }
    }
    
    private func loadTempFolderContents() {
        tempFolderContents = getFolderContents(url: FileManager.default.temporaryDirectory)
    }
    
    private func loadDocumentsFolderContents() {
        if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            documentsFolderContents = getFolderContents(url: documentsURL)
        }
    }
    
    private func loadCachesFolderContents() {
        if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cachesFolderContents = getFolderContents(url: cachesURL)
        }
    }
    
    private func getFolderContents(url: URL) -> [FolderItem] {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [URLResourceKey.fileSizeKey, URLResourceKey.creationDateKey, URLResourceKey.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            return fileURLs.compactMap { fileURL in
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [URLResourceKey.fileSizeKey, URLResourceKey.creationDateKey, URLResourceKey.contentModificationDateKey])
                    let size = resourceValues.fileSize ?? 0
                    let creationDate = resourceValues.creationDate
                    let modificationDate = resourceValues.contentModificationDate
                    
                    return FolderItem(
                        name: fileURL.lastPathComponent,
                        size: size,
                        creationDate: creationDate,
                        modificationDate: modificationDate,
                        isDirectory: resourceValues.isDirectory ?? false
                    )
                } catch {
                    return FolderItem(
                        name: fileURL.lastPathComponent,
                        size: 0,
                        creationDate: nil,
                        modificationDate: nil,
                        isDirectory: false
                    )
                }
            }.sorted { $0.name < $1.name }
        } catch {
            return []
        }
    }
}

struct FolderItem: Identifiable {
    let id = UUID()
    let name: String
    let size: Int
    let creationDate: Date?
    let modificationDate: Date?
    let isDirectory: Bool
    
    var formattedSize: String {
        if isDirectory {
            return "Directory"
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    var formattedDate: String {
        if let date = modificationDate ?? creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return "Unknown"
    }
}

struct FolderSection: View {
    let title: String
    let subtitle: String
    let path: String
    let items: [FolderItem]
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    onRefresh()
                }
                .font(.caption)
            }
            
            Text(path)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(4)
            
            if items.isEmpty {
                Text("No files found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        HStack {
                            Image(systemName: item.isDirectory ? "folder" : "doc")
                                .foregroundColor(item.isDirectory ? .blue : .gray)
                                .frame(width: 16)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                HStack {
                                    Text(item.formattedSize)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(item.formattedDate)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}
#endif

