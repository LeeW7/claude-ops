# Quick Tasks Server Implementation Spec

> Server-side implementation for the Quick Tasks feature in ops-deck mobile app.
> The Flutter client is already implemented and waiting for these endpoints.

## Overview

Quick Tasks provides a direct chat interface to Claude Code for quick tasks without creating GitHub issues. Users can interact with Claude in a specific repo's context for simple tasks like "update this class" or "fix this bug".

**Key Features:**
- Session-based conversations with Claude
- Git worktree isolation (like regular jobs)
- Real-time streaming via WebSocket
- Auto-cleanup (24h expiry, max 10 per repo)

---

## API Endpoints

### POST `/sessions/start`

Create a new quick task session.

**Request:**
```json
{
  "repo": "owner/repo"
}
```

**Response (201):**
```json
{
  "id": "quick-1706300000",
  "repo": "owner/repo",
  "status": "idle",
  "worktree_path": "/path/to/worktrees/quick-1706300000",
  "claude_session_id": null,
  "created_at": "2026-01-26T10:00:00Z",
  "last_activity": "2026-01-26T10:00:00Z",
  "message_count": 0,
  "total_cost_usd": 0.0
}
```

**Actions:**
1. Generate session ID: `quick-{unix_timestamp}`
2. Create git worktree for the repo
3. Create QuickSession record in database
4. Return session

---

### POST `/sessions/:id/message`

Send a message to Claude in the session context.

**Request:**
```json
{
  "content": "Add error handling to the login function"
}
```

**Response (200):**
```json
{
  "id": "uuid-string",
  "session_id": "quick-1706300000",
  "role": "user",
  "content": "Add error handling to the login function",
  "timestamp": "2026-01-26T10:01:00Z",
  "cost_usd": null,
  "tool_name": null,
  "tool_input": null
}
```

**Actions:**
1. Save user message to database
2. Update session status to `running`
3. Execute Claude CLI (see below)
4. Stream response via WebSocket
5. Save assistant message(s) to database
6. Update session: status=`idle`, message_count++, total_cost_usd+=cost
7. Store `claude_session_id` from CLI output for `--resume`

---

### GET `/sessions`

List all quick task sessions.

**Response (200):**
```json
[
  {
    "id": "quick-1706300000",
    "repo": "owner/repo",
    "status": "idle",
    "worktree_path": "/path/to/worktrees/quick-1706300000",
    "claude_session_id": "abc123",
    "created_at": "2026-01-26T10:00:00Z",
    "last_activity": "2026-01-26T10:05:00Z",
    "message_count": 5,
    "total_cost_usd": 0.0234
  }
]
```

**Notes:**
- Sort by `last_activity` descending
- Include all sessions (cleanup happens separately)

---

### GET `/sessions/:id`

Get a specific session with its message history.

**Response (200):**
```json
{
  "id": "quick-1706300000",
  "repo": "owner/repo",
  "status": "idle",
  "worktree_path": "/path/to/worktrees/quick-1706300000",
  "claude_session_id": "abc123",
  "created_at": "2026-01-26T10:00:00Z",
  "last_activity": "2026-01-26T10:05:00Z",
  "message_count": 5,
  "total_cost_usd": 0.0234,
  "messages": [
    {
      "id": "uuid-1",
      "session_id": "quick-1706300000",
      "role": "user",
      "content": "Add error handling",
      "timestamp": "2026-01-26T10:01:00Z",
      "cost_usd": null,
      "tool_name": null,
      "tool_input": null
    },
    {
      "id": "uuid-2",
      "session_id": "quick-1706300000",
      "role": "assistant",
      "content": "I'll add try-catch blocks...",
      "timestamp": "2026-01-26T10:01:30Z",
      "cost_usd": 0.012,
      "tool_name": null,
      "tool_input": null
    }
  ]
}
```

---

### DELETE `/sessions/:id`

Delete a session and clean up resources.

**Response:** 204 No Content

**Actions:**
1. Delete all QuickMessage records for session
2. Remove git worktree
3. Delete QuickSession record

---

## WebSocket Endpoint

### WS `/ws/sessions/:id`

Real-time streaming for session events.

#### Server → Client Events

**Connected:**
```json
{"type": "connected"}
```

**Status Change:**
```json
{"type": "statusChange", "data": {"status": "running"}}
```

**Assistant Text (streaming):**
```json
{"type": "assistantText", "content": "I'll add error handling to..."}
```

**Tool Use:**
```json
{
  "type": "toolUse",
  "data": {
    "tool": "Read",
    "input": "/path/to/file.swift"
  }
}
```

**Result (completion):**
```json
{
  "type": "result",
  "content": "I've added try-catch blocks to the login function...",
  "data": {
    "cost_usd": 0.0156,
    "input_tokens": 1234,
    "output_tokens": 567
  }
}
```

**Error:**
```json
{"type": "error", "content": "Claude CLI failed: ..."}
```

#### Client → Server Events

**User Input (alternative to POST):**
```json
{"type": "user_input", "content": "Now add logging too"}
```

---

## Data Models

### QuickSession

| Field | Type | Description |
|-------|------|-------------|
| id | String | Primary key, format: `quick-{timestamp}` |
| repo | String | Repository slug, e.g., `owner/repo` |
| status | Enum | `idle`, `running`, `failed`, `expired` |
| worktree_path | String? | Path to git worktree |
| claude_session_id | String? | Claude CLI session ID for `--resume` |
| created_at | DateTime | When session was created |
| last_activity | DateTime | Last message timestamp |
| message_count | Int | Number of messages in session |
| total_cost_usd | Double | Cumulative API cost |

### QuickMessage

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| session_id | String | Foreign key to QuickSession |
| role | Enum | `user`, `assistant`, `system`, `tool` |
| content | String | Message text |
| timestamp | DateTime | When message was created |
| cost_usd | Double? | Cost for assistant messages |
| tool_name | String? | Tool name for tool messages |
| tool_input | String? | Tool input JSON for tool messages |

---

## Claude CLI Integration

### First Message (New Session)

```bash
cd /path/to/worktree
claude -p "<user_prompt>" \
  --print \
  --output-format stream-json \
  --dangerously-skip-permissions
```

### Follow-up Messages (Resume Session)

```bash
cd /path/to/worktree
claude -p "<user_prompt>" \
  --resume "<claude_session_id>" \
  --print \
  --output-format stream-json \
  --dangerously-skip-permissions
```

### Parsing Stream Output

The `--output-format stream-json` outputs newline-delimited JSON:

```json
{"type": "assistant", "message": {"content": [{"type": "text", "text": "I'll..."}]}}
{"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {...}}]}}
{"type": "result", "cost_usd": 0.015, "session_id": "abc123", ...}
```

Key fields to extract:
- `session_id` from result → store as `claude_session_id`
- `cost_usd` from result → add to `total_cost_usd`
- Text content → stream as `assistantText` events
- Tool use → stream as `toolUse` events

---

## Session Cleanup

### Rules
1. Delete sessions older than **24 hours**
2. Keep at most **10 sessions per repo**
3. When deleting: remove messages, worktree, then session

### Schedule
- Run on server startup
- Run every 6 hours via scheduled task

### Implementation

```swift
func cleanupSessions() async {
    // Delete expired sessions (> 24h)
    let expiredDate = Date().addingTimeInterval(-24 * 60 * 60)
    let expired = try await QuickSession.query(on: db)
        .filter(\.$createdAt < expiredDate)
        .all()

    for session in expired {
        await deleteSession(session)
    }

    // Enforce per-repo limit (keep newest 10)
    let repos = try await QuickSession.query(on: db)
        .unique()
        .all(\.$repo)

    for repo in repos {
        let sessions = try await QuickSession.query(on: db)
            .filter(\.$repo == repo)
            .sort(\.$lastActivity, .descending)
            .all()

        if sessions.count > 10 {
            for session in sessions.dropFirst(10) {
                await deleteSession(session)
            }
        }
    }
}
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `Models/QuickSession.swift` | Session model + Fluent schema |
| `Models/QuickMessage.swift` | Message model + Fluent schema |
| `Migrations/CreateQuickSessions.swift` | Database migration |
| `Migrations/CreateQuickMessages.swift` | Database migration |
| `Controllers/QuickSessionController.swift` | REST endpoints |
| `Services/QuickSessionService.swift` | Business logic + Claude CLI |

## Files to Modify

| File | Changes |
|------|---------|
| `configure.swift` | Register migrations, add cleanup scheduled job |
| `routes.swift` | Register `/sessions` routes |
| `Controllers/WebSocketController.swift` | Add `/ws/sessions/:id` handler |
| `Services/ClaudeService.swift` | Add `-p` prompt execution method |

---

## Testing

```bash
# Create session
curl -X POST http://localhost:5001/sessions/start \
  -H "Content-Type: application/json" \
  -d '{"repo": "owner/repo"}'

# Send message
curl -X POST http://localhost:5001/sessions/quick-123/message \
  -H "Content-Type: application/json" \
  -d '{"content": "List the files in this repo"}'

# List sessions
curl http://localhost:5001/sessions

# Get session with messages
curl http://localhost:5001/sessions/quick-123

# Connect WebSocket
websocat ws://localhost:5001/ws/sessions/quick-123

# Delete session
curl -X DELETE http://localhost:5001/sessions/quick-123
```
