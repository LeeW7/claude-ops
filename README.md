# Claude Ops

A GitHub-triggered agent orchestration system that bridges GitHub issues with Claude Code CLI. When a GitHub issue is labeled with specific commands (e.g., `cmd:plan-headless`), the server executes Claude Code to analyze the issue and perform the requested action.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Claude Ops System                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   GitHub Issue          Swift Server           Claude CLI        │
│   ┌─────────┐          ┌───────────┐          ┌─────────┐       │
│   │  Label  │ ──────▶  │  Webhook  │ ──────▶  │  Plan   │       │
│   │  Added  │          │  Handler  │          │  Issue  │       │
│   └─────────┘          └───────────┘          └─────────┘       │
│        │                     │                      │            │
│        │                     ▼                      │            │
│        │              ┌───────────┐                 │            │
│        │              │   Jobs    │                 │            │
│        │              │  Storage  │                 │            │
│        │              └───────────┘                 │            │
│        │                     │                      │            │
│        ▼                     ▼                      ▼            │
│   ┌─────────┐          ┌───────────┐          ┌─────────┐       │
│   │ Flutter │ ◀─────── │   REST    │ ◀─────── │   PR    │       │
│   │   App   │          │    API    │          │ Created │       │
│   └─────────┘          └───────────┘          └─────────┘       │
│                                                                  │
│   macOS Menu Bar App                                             │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  🖥️ Claude Ops  ● ON                                     │   │
│   │  Server: Running on 5001 | Jobs: 2 active               │   │
│   │  ▶ house_backlog #70 - Planning...                      │   │
│   │  ⚙ Settings | 📋 Logs | Quit                            │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Running the Server](#running-the-server)
5. [macOS Menu Bar App](#macos-menu-bar-app)
6. [GitHub Webhook Setup](#github-webhook-setup)
7. [Workflow Commands](#workflow-commands)
8. [API Reference](#api-reference)
9. [Flutter Dashboard](#flutter-dashboard)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

| Software | Version | Installation |
|----------|---------|--------------|
| **macOS** | 14.0+ | - |
| **Xcode** | 15.0+ | App Store |
| **Swift** | 5.9+ | Included with Xcode |
| **GitHub CLI** | Latest | `brew install gh` |
| **Claude Code CLI** | Latest | `npm install -g @anthropic-ai/claude-code` |

### Verify Installation

```bash
# Check Swift
swift --version

# Check GitHub CLI (must be authenticated)
gh auth status

# Check Claude CLI
claude --version
```

### Authenticate GitHub CLI

```bash
gh auth login
# Follow prompts to authenticate with your GitHub account
```

---

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/claude-ops.git
cd claude-ops
```

### 2. Build the Project

```bash
# Build debug version (faster, for development)
swift build

# Build release version (optimized, for production)
swift build -c release
```

### 3. Create the macOS App Bundle (Optional)

```bash
./bundle-app.sh
```

This creates `Claude Ops.app` which you can:
- Move to `/Applications/` for system-wide access
- Double-click to run
- Add to Login Items for auto-start

---

## Configuration

### Repository Map (`repo_map.json`)

Create a `repo_map.json` file in the project root that maps local filesystem paths to GitHub repository URLs:

```json
{
    "/Users/yourname/Projects/my-app": "https://github.com/YOUR_USERNAME/my-app",
    "/Users/yourname/Projects/another-repo": "https://github.com/YOUR_USERNAME/another-repo"
}
```

**Important:**
- Local paths must be absolute paths
- Repositories must be cloned locally at the specified paths
- GitHub CLI must have access to these repositories

### Firebase Configuration (Optional)

For push notifications to work, create a `service-account.json` file with your Firebase service account credentials:

1. Go to Firebase Console → Project Settings → Service Accounts
2. Click "Generate new private key"
3. Save as `service-account.json` in the project root

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GEMINI_API_KEY` | No | API key for AI-enhanced issue descriptions |

Set in your shell profile or when running:

```bash
export GEMINI_API_KEY="your-api-key-here"
```

---

## Running the Server

### Option 1: Command Line (CLI)

```bash
# From the project directory
cd /path/to/claude-ops

# Run debug build
.build/debug/claude-ops-server

# Or run release build
.build/release/claude-ops-server
```

The server starts on port 5001 by default and binds to all interfaces (0.0.0.0).

### Option 2: macOS Menu Bar App

1. Build the app bundle: `./bundle-app.sh`
2. Open the app: `open "Claude Ops.app"`
3. Click the server icon in the menu bar
4. Click "Start" to start the server

### Verify Server is Running

```bash
# Check if server responds
curl http://localhost:5001/

# Should return: claude-ops server running

# Check repositories are loaded
curl http://localhost:5001/repos
```

---

## macOS Menu Bar App

The menu bar app provides a native macOS experience for managing the server.

### Features

| Feature | Description |
|---------|-------------|
| **Status Indicator** | Green dot when server is running |
| **Active Jobs** | See running jobs at a glance |
| **Approve/Reject** | Handle jobs waiting for approval |
| **Job Logs** | View detailed logs in a separate window |
| **Settings** | Configure port, auto-start, repositories |
| **Launch at Login** | Start automatically when you log in |

### Menu Bar Interface

```
┌─────────────────────────────┐
│ 🖥️ Claude Ops          ● ON │
├─────────────────────────────┤
│ Server: Running on 5001     │
│ Jobs: 2 active              │
├─────────────────────────────┤
│ ▶ house_backlog #70         │
│   Planning...               │
│ ▶ my-app #15                │
│   Implementing...           │
├─────────────────────────────┤
│ + Create Issue...           │
│ 📋 View All Logs...         │
├─────────────────────────────┤
│ Stop Server    Restart      │
├─────────────────────────────┤
│ ⚙ Settings...               │
│ Quit Claude Ops             │
└─────────────────────────────┘
```

### Settings

Access via menu bar → Settings or ⌘,

**General Tab:**
- Server port (default: 5001)
- Auto-start server on launch
- Launch at login
- Show notifications
- Default editor (VS Code, Cursor, Xcode, Terminal)

**Repositories Tab:**
- View configured repositories
- Add new repositories
- Open in Finder/Editor

**Health Tab:**
- Server status
- GitHub CLI status
- Claude CLI status
- Repository count

---

## GitHub Webhook Setup

To receive real-time notifications when issues are labeled, set up a GitHub webhook.

### 1. Expose Your Server

The server needs to be accessible from the internet. Options:

**Option A: Tailscale (Recommended for personal use)**
```bash
# Install Tailscale
brew install tailscale

# Connect to your Tailscale network
tailscale up

# Your server is now accessible at your Tailscale IP
# e.g., http://100.x.x.x:5001
```

**Option B: ngrok (For testing)**
```bash
ngrok http 5001
# Use the provided https URL for your webhook
```

**Option C: Deploy to a server**
Deploy to a cloud server with a public IP.

### 2. Configure Webhook in GitHub

1. Go to your repository → Settings → Webhooks
2. Click "Add webhook"
3. Configure:
   - **Payload URL:** `http://your-server:5001/webhook`
   - **Content type:** `application/json`
   - **Secret:** (optional, for security)
   - **Events:** Select "Issues" only
4. Click "Add webhook"

### 3. Verify Webhook

1. Label an issue with `cmd:plan-headless`
2. Check your server logs for the incoming webhook
3. The job should start automatically

### Fallback: Polling

If webhooks aren't configured, the server polls all repositories every 60 seconds for labeled issues.

---

## Workflow Commands

Labels trigger different actions. Add these labels to issues to start jobs:

### Available Commands

| Label | Action | Description |
|-------|--------|-------------|
| `cmd:plan-headless` | Plan | Claude analyzes the issue and creates an implementation plan |
| `cmd:implement-headless` | Implement | Claude implements the planned changes and creates a PR |
| `cmd:revise-headless` | Revise | Claude revises based on feedback |
| `cmd:retrospective-headless` | Retrospective | Claude analyzes what was done |

### Typical Workflow

```
1. Create Issue
   └─▶ Add label: cmd:plan-headless
       └─▶ Claude creates plan, comments on issue
           └─▶ Review plan
               └─▶ Add label: cmd:implement-headless
                   └─▶ Claude implements, creates PR
                       └─▶ Review PR
                           └─▶ Merge or request revisions
```

### Job States

| Status | Description |
|--------|-------------|
| `pending` | Job queued, waiting to start |
| `running` | Job currently executing |
| `waiting_approval` | Job needs user approval to continue |
| `completed` | Job finished successfully |
| `failed` | Job encountered an error |
| `rejected` | Job was cancelled by user |
| `interrupted` | Job was interrupted (e.g., server restart) |

---

## API Reference

### Health & Status

| Endpoint | Method | Description |
|----------|--------|-------------|
| `GET /` | GET | Health check, returns "claude-ops server running" |
| `GET /repos` | GET | List all configured repositories |
| `GET /jobs` | GET | List all jobs with last 50 log lines |
| `GET /api/status` | GET | Alias for /jobs |

### Job Management

| Endpoint | Method | Description |
|----------|--------|-------------|
| `GET /api/logs/:id` | GET | Get full logs for a specific job |
| `POST /jobs/:id/approve` | POST | Approve a job waiting for approval |
| `POST /jobs/:id/reject` | POST | Reject/cancel a job |

### Issue Management

| Endpoint | Method | Description |
|----------|--------|-------------|
| `POST /issues/create` | POST | Create a new GitHub issue |
| `POST /issues/enhance` | POST | Enhance issue description with AI |
| `GET /issues/:repo/:num` | GET | Get issue details |
| `GET /issues/:repo/:num/workflow` | GET | Get workflow state |
| `POST /issues/:repo/:num/proceed` | POST | Trigger next workflow phase |
| `POST /issues/:repo/:num/feedback` | POST | Submit revision feedback |
| `POST /issues/:repo/:num/merge` | POST | Merge the PR |
| `GET /issues/:repo/:num/pr` | GET | Get PR details |

### Webhook

| Endpoint | Method | Description |
|----------|--------|-------------|
| `POST /webhook` | POST | GitHub webhook receiver |

### Example Requests

**Create an Issue:**
```bash
curl -X POST http://localhost:5001/issues/create \
  -H "Content-Type: application/json" \
  -d '{
    "repo": "YOUR_USERNAME/my-repo",
    "title": "Add dark mode support",
    "body": "Implement a dark mode toggle in settings"
  }'
```

**Get Job Logs:**
```bash
curl http://localhost:5001/api/logs/my-repo-42-plan-headless
```

**Approve a Job:**
```bash
curl -X POST http://localhost:5001/jobs/my-repo-42-plan-headless/approve
```

---

## Flutter Dashboard

The Flutter companion app (`agent-command-center`) provides a mobile-friendly dashboard.

### Setup

1. Navigate to the Flutter app directory
2. Update the server URL in `lib/services/api_service.dart`:
   ```dart
   static const String baseUrl = 'http://your-server:5001';
   ```
3. Run the app:
   ```bash
   flutter run
   ```

### Features

- View all jobs across repositories
- Approve/reject jobs needing confirmation
- Create new issues with AI-assisted descriptions
- Receive push notifications via Firebase
- Kanban-style board for issue tracking

---

## Troubleshooting

### Server Won't Start

**Port already in use:**
```bash
# Find process using port 5001
lsof -i:5001

# Kill it
lsof -ti:5001 | xargs kill -9
```

**Missing repo_map.json:**
```bash
# Create the file in the project root
echo '{}' > repo_map.json
```

### Jobs Not Starting

**Check GitHub CLI authentication:**
```bash
gh auth status
```

**Check Claude CLI:**
```bash
claude --version
```

**Check repository path exists:**
```bash
ls -la /path/to/your/repo
```

### Webhook Not Working

1. Check webhook delivery in GitHub (Settings → Webhooks → Recent Deliveries)
2. Verify your server is accessible from the internet
3. Check server logs for incoming requests

### Logs Not Appearing

Log files are stored in `/tmp/claude_job_*.log`. Check:
```bash
ls -la /tmp/claude_job_*
cat /tmp/claude_job_your-job-id.log
```

### App Crashes on Launch

**Notification error (when running unbundled):**
```
bundleProxyForCurrentProcess is nil
```
This happens when running the executable directly. Use the bundled app instead:
```bash
./bundle-app.sh
open "Claude Ops.app"
```

### Reset Everything

```bash
# Stop server
pkill -f claude-ops-server
pkill -f ClaudeOps

# Clear job history
rm jobs.json

# Clear logs
rm /tmp/claude_job_*.log

# Restart
./bundle-app.sh
open "Claude Ops.app"
```

---

## Architecture

### Project Structure

```
claude-ops/
├── Package.swift              # Swift package manifest
├── Sources/
│   ├── ServerLib/             # Shared server library
│   │   ├── configure.swift    # Server configuration
│   │   ├── routes.swift       # Route registration
│   │   ├── entrypoint.swift   # Server startup functions
│   │   ├── Controllers/       # API endpoint handlers
│   │   ├── Models/            # Data models
│   │   ├── Services/          # Business logic
│   │   └── Jobs/              # Background jobs
│   ├── Server/                # CLI server executable
│   │   └── main.swift
│   └── ClaudeOps/             # macOS menu bar app
│       ├── ClaudeOpsApp.swift
│       ├── ServerManager.swift
│       ├── MenuBarView.swift
│       ├── SettingsView.swift
│       └── LogsView.swift
├── repo_map.json              # Repository configuration
├── jobs.json                  # Job persistence (auto-created)
└── bundle-app.sh              # App bundling script
```

### Data Flow

1. **Issue Labeled** → GitHub sends webhook to `/webhook`
2. **Job Created** → Server creates job entry, starts Claude CLI
3. **Claude Runs** → Output streamed to log file
4. **Job Completes** → Status updated, notification sent
5. **Client Polls** → Flutter app / menu bar app shows status

---

## License

MIT

---

## Support

- **Issues:** [GitHub Issues](https://github.com/YOUR_USERNAME/claude-ops/issues)
- **Documentation:** This README
