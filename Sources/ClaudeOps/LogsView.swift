import SwiftUI
import ServerLib

struct LogsView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var appState: AppState
    @State private var selectedJob: Job?
    @State private var logContent: String = ""
    @State private var searchText: String = ""
    @State private var statusFilter: JobStatus?
    @State private var autoRefresh = true

    var filteredJobs: [Job] {
        var jobs = serverManager.jobs

        if let filter = statusFilter {
            jobs = jobs.filter { $0.status == filter }
        }

        if !searchText.isEmpty {
            let search = searchText
            jobs = jobs.filter { job in
                job.issueTitle.localizedCaseInsensitiveContains(search) ||
                job.repoSlug.localizedCaseInsensitiveContains(search) ||
                job.id.localizedCaseInsensitiveContains(search)
            }
        }

        return jobs
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .navigationTitle("Job Logs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $autoRefresh) {
                    Image(systemName: autoRefresh ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                }
                .help("Auto-refresh logs")
            }
        }
        .onChange(of: selectedJob) { _, newJob in
            if let job = newJob {
                Task {
                    logContent = await serverManager.getJobLogs(job)
                }
            }
        }
        .onChange(of: appState.selectedJobId) { _, jobId in
            if let jobId = jobId {
                selectedJob = serverManager.jobs.first { $0.id == jobId }
            }
        }
        .task {
            await refreshLoop()
        }
    }

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            searchBar
            filterChips
            Divider()
            jobList
        }
        .frame(minWidth: 250)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search jobs...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(.background.secondary)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: statusFilter == nil) {
                    statusFilter = nil
                }
                FilterChip(title: "Active", isSelected: statusFilter == .running) {
                    statusFilter = .running
                }
                FilterChip(title: "Completed", isSelected: statusFilter == .completed) {
                    statusFilter = .completed
                }
                FilterChip(title: "Failed", isSelected: statusFilter == .failed) {
                    statusFilter = .failed
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var jobList: some View {
        List(filteredJobs, selection: $selectedJob) { job in
            JobListRow(job: job)
                .tag(job)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailContent: some View {
        if let job = selectedJob {
            JobDetailView(job: job, logContent: $logContent, autoRefresh: $autoRefresh)
        } else {
            ContentUnavailableView(
                "Select a Job",
                systemImage: "doc.text",
                description: Text("Choose a job from the sidebar to view its logs")
            )
        }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            if autoRefresh, let job = selectedJob {
                logContent = await serverManager.getJobLogs(job)
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct JobListRow: View {
    let job: Job

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("#\(job.issueNum)")
                        .font(.caption)
                        .fontWeight(.bold)
                    Text(job.shortCommand)
                        .font(.caption)
                }

                Text(job.issueTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack {
                    Text(job.repoSlug)
                    Text("•")
                    Text(job.formattedStartTime)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
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
        }
    }
}

struct JobDetailView: View {
    let job: Job
    @Binding var logContent: String
    @Binding var autoRefresh: Bool
    @EnvironmentObject var serverManager: ServerManager
    @State private var showingCopiedAlert = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            logSection
            Divider()
            footerSection
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(job.issueNum)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(job.shortCommand)
                        .font(.title2)
                    StatusBadge(status: job.status)
                }

                Text(job.issueTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(job.repo)
                    Text("•")
                    Text(job.formattedStartTime)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            actionButtons
        }
        .padding()
        .background(.background.secondary)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if job.status == .waitingApproval {
            Button {
                Task { await serverManager.approveJob(job) }
            } label: {
                Label("Approve", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button {
                Task { await serverManager.rejectJob(job) }
            } label: {
                Label("Reject", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }

        if job.status == .running {
            Button {
                Task { await serverManager.rejectJob(job) }
            } label: {
                Label("Cancel", systemImage: "stop.circle")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private var logSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(logContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .id("logBottom")
            }
            .onChange(of: logContent) { _, _ in
                if autoRefresh {
                    withAnimation {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Button {
                copyLogs()
            } label: {
                Label(showingCopiedAlert ? "Copied!" : "Copy Logs", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                openIssue()
            } label: {
                Label("Open Issue", systemImage: "arrow.up.forward")
            }
            .buttonStyle(.plain)

            Button {
                openFolder()
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logContent, forType: .string)
        showingCopiedAlert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingCopiedAlert = false
        }
    }

    private func openIssue() {
        let urlString = "https://github.com/\(job.repo)/issues/\(job.issueNum)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: job.localPath)
    }
}

struct StatusBadge: View {
    let status: JobStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.2))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .pending: return .orange
        case .waitingApproval: return .yellow
        case .rejected: return .gray
        case .interrupted: return .purple
        case .approvedResume: return .cyan
        }
    }
}
