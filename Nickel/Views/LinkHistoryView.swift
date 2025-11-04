//
//  LinkHistoryView.swift
//  Nickel
//
//  Created by TfourJ
//

import SwiftUI

struct LinkHistoryView: View {
    @State private var entries: [LinkHistoryEntry] = []
    @State private var showClearAllAlert = false
    
    // Callbacks from ContentView
    var onCopyLink: ((String) -> Void)?
    var onInputWithoutDownload: ((String) -> Void)?
    var onDownload: ((String, String) -> Void)?
    var onDismiss: (() -> Void)?
    
    var body: some View {
        NavigationView {
            Group {
                if entries.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No Link History")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                        Text("Downloaded links will appear here")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(entries) { entry in
                            LinkHistoryRow(
                                entry: entry,
                                onCopy: {
                                    UIPasteboard.general.string = entry.url
                                    onCopyLink?(entry.url)
                                },
                                onInput: {
                                    onInputWithoutDownload?(entry.url)
                                    onDismiss?()
                                },
                                onRemove: {
                                    LinkHistoryManager.shared.removeEntry(id: entry.id)
                                    loadEntries()
                                },
                                onTap: {
                                    onDownload?(entry.url, entry.downloadMode)
                                    onDismiss?()
                                }
                            )
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Link History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        onDismiss?()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !entries.isEmpty {
                        Button("Clear All") {
                            showClearAllAlert = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .alert("Clear All History", isPresented: $showClearAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    LinkHistoryManager.shared.clearAll()
                    loadEntries()
                }
            } message: {
                Text("Are you sure you want to clear all link history? This cannot be undone.")
            }
        }
        .onAppear {
            loadEntries()
        }
        .preferredColorScheme(.dark)
    }
    
    private func loadEntries() {
        entries = LinkHistoryManager.shared.getAllEntries()
    }
}

struct LinkHistoryRow: View {
    let entry: LinkHistoryEntry
    let onCopy: () -> Void
    let onInput: () -> Void
    let onRemove: () -> Void
    let onTap: () -> Void
    
    private var downloadModeDisplay: String {
        switch entry.downloadMode {
        case "audio":
            return "Audio"
        case "mute":
            return "Mute"
        default:
            return "Auto"
        }
    }
    
    private var downloadModeColor: Color {
        switch entry.downloadMode {
        case "audio":
            return .green
        case "mute":
            return .orange
        default:
            return .blue
        }
    }
    
    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    // Title or URL
                    if let title = entry.title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Text(entry.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(entry.title != nil ? 1 : 2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 8) {
                        // Download mode badge
                        Text(downloadModeDisplay)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(downloadModeColor)
                            .cornerRadius(6)
                        
                        // Timestamp
                        Text(formattedTimestamp)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Dropdown menu button
                Menu {
                    Button(action: onCopy) {
                        Label("Copy Link", systemImage: "doc.on.clipboard")
                    }
                    
                    Button(action: onInput) {
                        Label("Input Without Download", systemImage: "text.cursor")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                        .padding(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    LinkHistoryView()
}

