import SwiftUI
import Combine

/// A simple logger that captures console output.
final class ConsoleLogger: ObservableObject {
    static let shared = ConsoleLogger()
    @Published private(set) var log: String = ""

    /// Appends a new message to the log.
    func appendLog(_ message: String) {
        DispatchQueue.main.async {
            self.log.append("\(message)\n")
        }
    }
}

func logOutput(_ message: String) {
    // Append the message to the custom console log
    ConsoleLogger.shared.appendLog(message)
    // Print the message to Xcode's console
    print(message)
}

/// A view that displays captured console output.
struct ConsoleView: View {
    @StateObject private var logger = ConsoleLogger.shared

    var body: some View {
        NavigationView {
            ScrollView {
                Text(logger.log)
                    .font(.system(.footnote, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Console")
            .onAppear {
                // Test log to verify onAppear is working.
                // logOutput("Test output: ConsoleView appeared")
            }
        }
    }
}

#Preview {
    ConsoleView()
}
