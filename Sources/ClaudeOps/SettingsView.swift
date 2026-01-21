import SwiftUI
import ServiceManagement
import ServerLib

struct SettingsView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            RepositoriesSettingsView()
                .tabItem {
                    Label("Repositories", systemImage: "folder")
                }

            HealthSettingsView()
                .tabItem {
                    Label("Health", systemImage: "heart")
                }
        }
        .frame(width: 500, height: 480)
        .environmentObject(serverManager)
        .environmentObject(appState)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Server") {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", text: Binding(
                        get: { String(appState.serverPort) },
                        set: { if let val = Int($0) { appState.serverPort = val } }
                    ))
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Auto-start server on launch", isOn: $appState.autoLaunchServer)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Notifications") {
                Toggle("Show notifications", isOn: $appState.showNotifications)
            }

            Section("Editor") {
                Picker("Default editor", selection: $appState.defaultEditor) {
                    Text("VS Code").tag("vscode")
                    Text("Cursor").tag("cursor")
                    Text("Xcode").tag("xcode")
                    Text("Terminal").tag("terminal")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}

// MARK: - Repositories Settings

struct RepositoriesSettingsView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var showingAddSheet = false
    @State private var newLocalPath = ""
    @State private var newGitHubUrl = ""

    var body: some View {
        VStack {
            List {
                ForEach(serverManager.repositories) { repo in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(repo.fullName)
                                .font(.headline)
                            Text(repo.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            openInFinder(repo.path)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)

                        Button {
                            openInEditor(repo.path)
                        } label: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Button("Add Repository...") {
                    showingAddSheet = true
                }

                Spacer()

                Button("Refresh") {
                    Task {
                        await serverManager.refreshData()
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddRepositorySheet(
                localPath: $newLocalPath,
                gitHubUrl: $newGitHubUrl,
                isPresented: $showingAddSheet
            )
        }
    }

    private func openInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    @AppStorage("defaultEditor") private var defaultEditor = "vscode"

    private func openInEditor(_ path: String) {
        let url = URL(fileURLWithPath: path)

        switch defaultEditor {
        case "vscode":
            let appUrl = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appUrl, configuration: config)
        case "cursor":
            let appUrl = URL(fileURLWithPath: "/Applications/Cursor.app")
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appUrl, configuration: config)
        case "xcode":
            let appUrl = URL(fileURLWithPath: "/Applications/Xcode.app")
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: appUrl, configuration: config)
        default:
            // Open terminal at path
            let script = "tell application \"Terminal\" to do script \"cd '\(path)'\""
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
    }
}

struct AddRepositorySheet: View {
    @Binding var localPath: String
    @Binding var gitHubUrl: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Repository")
                .font(.headline)

            Form {
                TextField("Local Path", text: $localPath)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    TextField("", text: $localPath)
                        .hidden()

                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false

                        if panel.runModal() == .OK, let url = panel.url {
                            localPath = url.path
                        }
                    }
                }

                TextField("GitHub URL", text: $gitHubUrl)
                    .textFieldStyle(.roundedBorder)

                Text("e.g., https://github.com/owner/repo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Spacer()

                Button("Add") {
                    // Note: Adding repositories requires manual edit of repo_map.json
                    // See README.md for configuration instructions
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(localPath.isEmpty || gitHubUrl.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// MARK: - Health Settings

struct HealthSettingsView: View {
    @EnvironmentObject var serverManager: ServerManager

    var body: some View {
        Form {
            Section("Status") {
                HealthRow(
                    title: "Server",
                    status: serverManager.healthStatus.serverRunning,
                    detail: serverManager.healthStatus.serverRunning ? "Running on port 5001" : "Not running"
                )

                HealthRow(
                    title: "GitHub CLI (gh)",
                    status: serverManager.healthStatus.ghCliInstalled,
                    detail: serverManager.healthStatus.ghCliInstalled ? "Installed" : "Not found"
                )

                HealthRow(
                    title: "Claude CLI",
                    status: serverManager.healthStatus.claudeCliInstalled,
                    detail: serverManager.healthStatus.claudeCliInstalled ? "Installed" : "Not found"
                )

                HealthRow(
                    title: "Repositories",
                    status: serverManager.healthStatus.repoCount > 0,
                    detail: "\(serverManager.healthStatus.repoCount) configured"
                )
            }

            Section("Jobs") {
                HStack {
                    Text("Active Jobs")
                    Spacer()
                    Text("\(serverManager.healthStatus.activeJobs)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Total Jobs")
                    Spacer()
                    Text("\(serverManager.jobs.count)")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Clear Job History") {
                    // Job history is stored in Firestore
                    // Clearing requires Firestore admin access
                }
                .foregroundStyle(.red)
                .disabled(true)
            }
        }
        .formStyle(.grouped)
    }
}

struct HealthRow: View {
    let title: String
    let status: Bool
    let detail: String

    var body: some View {
        HStack {
            Image(systemName: status ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status ? .green : .red)

            Text(title)

            Spacer()

            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ServerManager())
        .environmentObject(AppState())
}
