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

    var body: some View {
        VStack(spacing: 20) {
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
            Spacer()
        }
        .padding()
    }
}
#endif

