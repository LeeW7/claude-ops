import SwiftUI
import ServerLib

struct MenuBarView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection

            Divider()

            // Server Status
            serverStatusSection

            if serverManager.isRunning {
                Divider()

                // Active Jobs
                if !serverManager.activeJobs.isEmpty {
                    activeJobsSection
                    Divider()
                }

                // Recent Jobs (if no active)
                if serverManager.activeJobs.isEmpty && !serverManager.recentJobs.isEmpty {
                    recentJobsSection
                    Divider()
                }

                // Quick Actions
                quickActionsSection
                Divider()
            }

            // Footer
            footerSection
        }
        .frame(width: 320)
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading) {
                Text("Claude Ops")
                    .font(.headline)
                Text(serverManager.isRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(serverManager.isRunning ? .green : .secondary)
            }

            Spacer()

            if serverManager.isRunning {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding()
    }

    private var serverStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if serverManager.isRunning {
                HStack {
                    Label("Port 5001", systemImage: "network")
                    Spacer()
                    Text(formatUptime(serverManager.serverUptime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("\(serverManager.repositories.count) repos", systemImage: "folder")
                    Spacer()
                    Label("\(serverManager.jobs.count) jobs", systemImage: "list.bullet")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Server is not running")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Start") {
                        Task {
                            await serverManager.startServer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding()
    }

    private var activeJobsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Active Jobs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            ForEach(serverManager.activeJobs) { job in
                JobRowView(job: job)
            }
        }
    }

    private var recentJobsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Jobs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            ForEach(serverManager.recentJobs.prefix(5)) { job in
                JobRowView(job: job)
            }
        }
    }

    private var quickActionsSection: some View {
        VStack(spacing: 4) {
            Button {
                appState.showingCreateIssue = true
            } label: {
                Label("Create Issue...", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 6)

            Button {
                openWindow(id: "logs")
            } label: {
                Label("View All Logs...", systemImage: "doc.text")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 4)
    }

    private var footerSection: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    openSettings()
                } label: {
                    Label("Settings...", systemImage: "gear")
                }
                .buttonStyle(.plain)

                Spacer()

                // Server toggle + Quit
                if serverManager.isRunning {
                    Button {
                        Task {
                            await serverManager.stopServer()
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        Task {
                            await serverManager.startServer()
                        }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("Quit") {
                    Task {
                        await serverManager.stopServer()
                        await MainActor.run {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func formatUptime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

struct JobRowView: View {
    let job: Job
    @EnvironmentObject var serverManager: ServerManager
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("#\(job.issueNum) \(job.shortCommand)")
                    .font(.caption)
                    .fontWeight(.medium)

                Text(job.repoSlug)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions for waiting jobs
            if job.status == .waitingApproval {
                Button {
                    Task {
                        await serverManager.approveJob(job)
                    }
                } label: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await serverManager.rejectJob(job)
                    }
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            // Status badge
            Text(job.status.displayName)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedJobId = job.id
            openWindow(id: "logs")
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .pending: return .orange
        case .waitingApproval: return .yellow
        case .rejected: return .gray
        case .interrupted: return .purple
        case .approvedResume: return .cyan
        case .blocked: return .orange
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(ServerManager())
        .environmentObject(AppState())
}
