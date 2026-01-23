# Contributing to Claude Ops

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/claude-ops.git`
3. Create a branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Push and create a Pull Request

## Development Setup

### Prerequisites

- macOS (required for the menu bar app)
- Swift 5.10+
- Xcode 15+ (optional, for IDE support)
- GitHub CLI (`gh`) installed and authenticated
- Claude Code CLI installed

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run the server
.build/debug/claude-ops-server
```

## Code Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Keep functions focused and small
- Add comments for complex logic

## Pull Request Process

1. Ensure your code builds without errors
2. Update documentation if needed
3. Fill out the PR template completely
4. Link any related issues

## Reporting Bugs

Use the GitHub issue tracker with the Bug Report template. Include:
- Clear description of the issue
- Steps to reproduce
- Expected vs actual behavior
- Environment details

## Security

Please report security vulnerabilities privately. See [SECURITY.md](SECURITY.md) for details.

## Questions?

Open a GitHub Discussion or Issue for questions about contributing.
