# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

Claude Ops is a GitHub-triggered agent orchestration system that bridges GitHub issues with Claude Code CLI. The project consists of:

1. **Swift/Vapor Server** - REST API backend that handles webhooks and job execution
2. **macOS Menu Bar App** - Native SwiftUI app for managing the server
3. **Flutter Dashboard** - Mobile/desktop companion app (in `agent-command-center/`)

## Quick Commands

```bash
# Build debug
swift build

# Build release
swift build -c release

# Run CLI server
.build/debug/claude-ops-server

# Create app bundle
./bundle-app.sh

# Run bundled app
open "Claude Ops.app"
```

## Architecture

### Targets

- `ServerLib` - Shared library with all server code
- `Server` (claude-ops-server) - CLI executable for running server
- `ClaudeOps` - macOS menu bar app

### Key Files

| File | Purpose |
|------|---------|
| `Sources/ServerLib/configure.swift` | Server initialization, service setup |
| `Sources/ServerLib/routes.swift` | API route registration |
| `Sources/ServerLib/Services/ClaudeService.swift` | Claude CLI process management |
| `Sources/ServerLib/Services/FirestoreService.swift` | Job persistence (JSON file) |
| `Sources/ServerLib/Services/GitHubService.swift` | GitHub CLI wrapper |
| `Sources/ClaudeOps/ServerManager.swift` | App-server lifecycle management |
| `Sources/ClaudeOps/MenuBarView.swift` | Menu bar dropdown UI |

### Data Models

- `Job` - Represents a Claude execution job
- `Repository` - GitHub repository info
- `RepoMap` - Maps local paths to GitHub URLs
- `WorkflowState` - Issue workflow phase tracking

## API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/webhook` | POST | GitHub webhook receiver |
| `/jobs` | GET | List all jobs |
| `/api/logs/:id` | GET | Get job logs |
| `/jobs/:id/approve` | POST | Approve waiting job |
| `/jobs/:id/reject` | POST | Reject/cancel job |
| `/issues/create` | POST | Create GitHub issue |
| `/issues/:repo/:num/workflow` | GET | Get workflow state |

## Configuration

- `repo_map.json` - Maps local paths to GitHub repos
- `service-account.json` - Firebase credentials (optional)
- `GEMINI_API_KEY` env var - For AI issue enhancement

## External Dependencies

- **GitHub CLI (`gh`)** - Must be installed and authenticated
- **Claude Code CLI (`claude`)** - Must be installed and in PATH
- **Vapor** - Swift web framework
- **Firebase iOS SDK** - For notifications (optional)

## Code Style

- Use Swift actors for thread-safe services
- All public API types need `public` access modifier
- Models conform to `Content` (Vapor), `Codable`, `Identifiable`
- Use `async/await` throughout

## Common Tasks

### Adding a New API Endpoint

1. Add route in `Sources/ServerLib/routes.swift`
2. Create handler in appropriate Controller
3. Add any needed DTOs in `Models/DTOs/`

### Adding a New Service

1. Create service in `Sources/ServerLib/Services/`
2. Make it `public actor` or `public struct`
3. Add storage key in `configure.swift`
4. Initialize in `configure()` function

### Modifying the Menu Bar App

1. UI is in `Sources/ClaudeOps/`
2. State management via `ServerManager`
3. Use `@EnvironmentObject` for shared state
