---
description: Jira integration for issue tracking and workflow management
---

# Jira Skill

Jira integration using Atlassian MCP.

## Configuration

**CloudId**: `835cc1c2-2cce-4b17-adb9-6c6c0097072d` (eigservices.atlassian.net)

## Actions

| Action | MCP Tool |
|--------|----------|
| Get Issue | `mcp__atlassian__getJiraIssue` |
| Create Issue | `mcp__atlassian__createJiraIssue` |
| Update Issue | `mcp__atlassian__editJiraIssue` |
| Add Comment | `mcp__atlassian__addCommentToJiraIssue` |
| Transition | `mcp__atlassian__transitionJiraIssue` |
| Search (JQL) | `mcp__atlassian__searchJiraIssuesUsingJql` |

## Field Formats

**Description**: Use markdown format - the MCP server converts to Atlassian Document Format (ADF).

```javascript
mcp__atlassian__editJiraIssue({
  cloudId: "835cc1c2-2cce-4b17-adb9-6c6c0097072d",
  issueIdOrKey: "INS-123",
  fields: {
    description: "## Summary\n\nMarkdown content here..."
  }
})
```

## Common Patterns

### Get Issue Details
```javascript
mcp__atlassian__getJiraIssue({
  cloudId: "835cc1c2-2cce-4b17-adb9-6c6c0097072d",
  issueIdOrKey: "INS-123"
})
```

### Create Issue
```javascript
mcp__atlassian__createJiraIssue({
  cloudId: "835cc1c2-2cce-4b17-adb9-6c6c0097072d",
  projectKey: "INS",
  issueTypeName: "Story",
  summary: "Feature title",
  description: "## Description\n\nFeature details..."
})
```

### Add Comment
```javascript
mcp__atlassian__addCommentToJiraIssue({
  cloudId: "835cc1c2-2cce-4b17-adb9-6c6c0097072d",
  issueIdOrKey: "INS-123",
  commentBody: "Implementation complete. PR: [#123](url)"
})
```

### Update Description
```javascript
mcp__atlassian__editJiraIssue({
  cloudId: "835cc1c2-2cce-4b17-adb9-6c6c0097072d",
  issueIdOrKey: "INS-123",
  fields: {
    description: "## Updated content\n\n..."
  }
})
```

### Transition Issue
```javascript
// First get available transitions
mcp__atlassian__getTransitionsForJiraIssue({
  cloudId: "835cc1c2-2cce-4b17-adb9-6c6c0097072d",
  issueIdOrKey: "INS-123"
})

// Then transition
mcp__atlassian__transitionJiraIssue({
  cloudId: "835cc1c2-2cce-4b17-adb9-6c6c0097072d",
  issueIdOrKey: "INS-123",
  transition: { id: "31" }  // ID from getTransitions
})
```

### Search Issues
```javascript
mcp__atlassian__searchJiraIssuesUsingJql({
  cloudId: "835cc1c2-2cce-4b17-adb9-6c6c0097072d",
  jql: "project = INS AND status = 'In Progress'"
})
```

## When to Use This Skill

- `/plan` - Create new issues
- `/implement` - Fetch issue details, update status
- `/ship` - Add PR link, transition status
- `/retrospective` - Read issue history
