import SwiftUI
import ServerLib

@main
struct ClaudeOpsApp: App {
    @StateObject private var serverManager: ServerManager
    @StateObject private var appState = AppState()

    init() {
        // Register default values before ServerManager checks them
        UserDefaults.standard.register(defaults: [
            "autoLaunchServer": true,
            "showNotifications": true,
            "serverPort": 5001,
            "defaultEditor": "vscode"
        ])
        _serverManager = StateObject(wrappedValue: ServerManager())
    }

    var body: some Scene {
        // Menu bar app
        MenuBarExtra {
            MenuBarView()
                .environmentObject(serverManager)
                .environmentObject(appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: serverManager.isRunning ? "server.rack" : "server.rack")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(serverManager.isRunning ? .green : .secondary)
                if serverManager.activeJobCount > 0 {
                    Text("\(serverManager.activeJobCount)")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(.blue))
                }
            }
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(serverManager)
                .environmentObject(appState)
        }

        // Logs window (opened on demand)
        Window("Job Logs", id: "logs") {
            LogsView()
                .environmentObject(serverManager)
                .environmentObject(appState)
        }
        .defaultSize(width: 800, height: 600)
    }
}

/// Global app state
@MainActor
class AppState: ObservableObject {
    @Published var selectedJobId: String?
    @Published var showingCreateIssue = false

    @AppStorage("serverPort") var serverPort: Int = 5001
    @AppStorage("autoLaunchServer") var autoLaunchServer: Bool = true
    @AppStorage("showNotifications") var showNotifications: Bool = true
    @AppStorage("defaultEditor") var defaultEditor: String = "vscode"
}
