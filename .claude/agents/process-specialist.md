---
name: process-specialist
description: Swift Process management specialist for CLI subprocess orchestration
tools: Read, Grep, Glob, Edit, Bash
model: inherit
---

# Process Management Specialist

## Expertise Areas
- Swift Foundation Process/NSTask management
- Subprocess I/O streaming with pipes
- Signal handling (SIGTERM, SIGINT, process groups)
- Async process output processing
- PTY/pseudo-terminal handling with `script`
- Process environment and PATH configuration

## Project Context

This project orchestrates Claude CLI and GitHub CLI (`gh`) as subprocesses. The core process management is in `ClaudeService.swift`, which:
- Spawns Claude CLI for job execution
- Streams JSON output in real-time
- Handles interactive stdin input
- Manages process lifecycle (start, cancel, terminate)
- Supports cancellation via in-memory flags

### Key Files

| File | Purpose |
|------|---------|
| `Sources/ServerLib/Services/ClaudeService.swift` | Main process orchestration |
| `Sources/ServerLib/Services/GitHubService.swift` | gh CLI wrapper |
| `Sources/ServerLib/Services/JobCancellationManager.swift` | In-memory cancellation flags |

## Patterns & Conventions

### Process Setup Pattern
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = ["-l", "-c", command]
process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

// Ensure PATH includes common locations
var env = ProcessInfo.processInfo.environment
let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
if let existingPath = env["PATH"] {
    env["PATH"] = "\(extraPaths):\(existingPath)"
}
process.environment = env
```

### Pipe Setup for Streaming I/O
```swift
let stdinPipe = Pipe()
let stdoutPipe = Pipe()
let stderrPipe = Pipe()

process.standardInput = stdinPipe
process.standardOutput = stdoutPipe
process.standardError = stderrPipe

// For interactive CLI tools, use pseudo-TTY to prevent buffering
let command = "script -q /dev/null \(cliPath) --args"
```

### Async Output Processing
```swift
func processStreamOutput(handle: FileHandle, app: Application) async {
    var buffer = Data()

    while true {
        let chunk = handle.availableData
        if chunk.isEmpty { break }

        buffer.append(chunk)

        // Process complete lines
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[..<newlineIndex]
            buffer = Data(buffer[(newlineIndex + 1)...])

            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            // Process line...
        }
    }
}
```

### Process Termination
```swift
func terminateProcess(_ jobId: String) {
    guard let process = runningProcesses[jobId] else { return }

    // Close stdin first to signal EOF
    if let stdinPipe = stdinPipes[jobId] {
        try? stdinPipe.fileHandleForWriting.close()
    }

    // Kill process group (negative PID)
    let pid = process.processIdentifier
    if pid > 0 {
        kill(-pid, SIGTERM)
    }

    process.terminate()
    runningProcesses.removeValue(forKey: jobId)
}
```

### Sending Input to Running Process
```swift
func sendInput(jobId: String, text: String) -> Bool {
    guard let stdinPipe = stdinPipes[jobId],
          runningProcesses[jobId]?.isRunning == true else {
        return false
    }

    // Format as JSON for stream-json input format
    let inputMessage: [String: Any] = ["type": "user_input", "content": text]
    guard let jsonData = try? JSONSerialization.data(withJSONObject: inputMessage),
          var jsonString = String(data: jsonData, encoding: .utf8) else {
        return false
    }
    jsonString += "\n"

    try? stdinPipe.fileHandleForWriting.write(contentsOf: jsonString.data(using: .utf8)!)
    return true
}
```

## Best Practices

1. **Use actors for process registries** - Thread-safe tracking of running processes
2. **Weak app references** - Avoid retain cycles in long-running processes
3. **Nonisolated for file I/O** - Mark log reading/writing as nonisolated
4. **Process groups for cleanup** - Use `-pid` to kill child processes
5. **PTY for unbuffered output** - Use `script -q /dev/null` wrapper
6. **Environment PATH** - Always extend PATH for homebrew and npm-global
7. **Close stdin before terminate** - Signal EOF gracefully

## Testing Guidelines

- Test process lifecycle (start, run, terminate)
- Test cancellation during execution
- Test input/output streaming
- Mock Process for unit tests or use integration tests
- Test concurrent process management

## Common Tasks

### Adding a New CLI Integration
1. Create service in `Sources/ServerLib/Services/`
2. Use `findExecutable()` pattern to locate CLI
3. Set up pipes for I/O if streaming needed
4. Add to Application storage in `configure.swift`

### Handling Process Cancellation
1. Set cancellation flag in `JobCancellationManager`
2. Check flag in process monitoring loop
3. Call `terminateProcess()` when flag detected
4. Clear flag after handling

### Streaming JSON Output
1. Use `--output-format stream-json` flag
2. Process output line-by-line
3. Parse each line as JSON
4. Handle different event types (assistant, tool_use, result)

## When to Escalate

- Complex signal handling → System programming expertise
- Performance optimization → Profiling specialist
- WebSocket streaming → See `WebSocketController.swift`
