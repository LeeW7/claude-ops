#!/bin/bash
# Pre-commit security check for claude-ops
# Install: cp scripts/pre-commit-security-check.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "Running security check..."

BLOCKED=0
WARNED=0

# Get list of staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
    echo -e "${GREEN}No files staged for commit${NC}"
    exit 0
fi

# Check for files that should never be committed
FORBIDDEN_FILES="service-account.json repo_map.json .env jobs.json"
for file in $FORBIDDEN_FILES; do
    if echo "$STAGED_FILES" | grep -q "^${file}$"; then
        echo -e "${RED}BLOCKED: $file should not be committed${NC}"
        BLOCKED=1
    fi
done

# Check for database files
if echo "$STAGED_FILES" | grep -qE '\.db$|\.db-shm$|\.db-wal$'; then
    echo -e "${RED}BLOCKED: Database files should not be committed${NC}"
    BLOCKED=1
fi

# Check staged content for secrets (only added lines, excluding docs, examples, and this script)
STAGED_CONTENT=$(git diff --cached -- ':(exclude)*.example' ':(exclude)*.md' ':(exclude)README*' ':(exclude)scripts/pre-commit*' ':(exclude).claude/commands/*' | grep -E '^\+' || true)

if [ -n "$STAGED_CONTENT" ]; then
    # Check for real API key assignments (not placeholders or references)
    if echo "$STAGED_CONTENT" | grep -qiE 'GEMINI_API_KEY\s*=\s*"[a-zA-Z0-9_-]{20,}"'; then
        echo -e "${RED}BLOCKED: Hardcoded GEMINI_API_KEY value found${NC}"
        BLOCKED=1
    fi

    # Check for private keys (the actual key content, not pattern descriptions)
    # Look for the actual base64-encoded key data that follows the header
    if echo "$STAGED_CONTENT" | grep -q 'BEGIN RSA PRIVATE KEY' || \
       echo "$STAGED_CONTENT" | grep -q 'BEGIN EC PRIVATE KEY' || \
       echo "$STAGED_CONTENT" | grep -q 'BEGIN OPENSSH PRIVATE KEY' || \
       echo "$STAGED_CONTENT" | grep -qE 'BEGIN PRIVATE KEY-----\\n[A-Za-z0-9+/=]'; then
        echo -e "${RED}BLOCKED: Private key found in staged changes${NC}"
        BLOCKED=1
    fi

    # Check for firebase service account credentials (actual JSON with private_key field)
    if echo "$STAGED_CONTENT" | grep -qE '"private_key_id":\s*"[a-f0-9]{40}"'; then
        echo -e "${RED}BLOCKED: Firebase service account credentials found${NC}"
        BLOCKED=1
    fi

    # Check for hardcoded passwords (not placeholders)
    if echo "$STAGED_CONTENT" | grep -qiE 'password\s*[=:]\s*"[^"${\}]{8,}"'; then
        echo -e "${YELLOW}WARNING: Possible hardcoded password${NC}"
        WARNED=1
    fi
fi

# Check for personal paths in Swift source files only
SWIFT_CHANGES=$(git diff --cached -- '*.swift' | grep -E '^\+' || true)
if [ -n "$SWIFT_CHANGES" ]; then
    # Check for hardcoded personal paths (not in comments)
    if echo "$SWIFT_CHANGES" | grep -v '//' | grep -qE '"/Users/[a-zA-Z]+/[^"]*"'; then
        echo -e "${YELLOW}WARNING: Hardcoded personal path found in Swift code${NC}"
        echo "Check: git diff --cached -- '*.swift' | grep -E '/Users/'"
        WARNED=1
    fi
fi

# Check for real email addresses in code (not common safe ones)
if [ -n "$STAGED_CONTENT" ]; then
    EMAILS=$(echo "$STAGED_CONTENT" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | grep -vE 'example\.com|noreply|test|anthropic\.com|localhost|placeholder|iam\.gserviceaccount\.com' | sort -u || true)
    if [ -n "$EMAILS" ]; then
        echo -e "${YELLOW}WARNING: Email address(es) found: $EMAILS${NC}"
        WARNED=1
    fi
fi

# Retrospective commit validation
# If commit message indicates a retrospective, ensure ONLY .claude/retrospectives/ files are modified
# This is checked via a prepare-commit-msg or by examining the branch name
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

# Check if this appears to be a retrospective commit (branch contains retrospective or commit is docs-only)
if echo "$CURRENT_BRANCH" | grep -qi "retrospective"; then
    echo "Validating retrospective commit (docs-only)..."

    # Check if any staged files are outside .claude/retrospectives/
    NON_RETRO_FILES=$(echo "$STAGED_FILES" | grep -v "^\.claude/retrospectives/" || true)

    if [ -n "$NON_RETRO_FILES" ]; then
        echo -e "${RED}BLOCKED: Retrospective commits can only modify .claude/retrospectives/${NC}"
        echo -e "${RED}The following files are not allowed:${NC}"
        echo "$NON_RETRO_FILES" | while read -r file; do
            echo -e "  ${RED}- $file${NC}"
        done
        echo ""
        echo "Retrospective branches should only contain documentation changes."
        echo "If you need to modify code, use a different branch."
        BLOCKED=1
    else
        echo -e "${GREEN}Retrospective validation passed (docs-only)${NC}"
    fi
fi

# Final result
echo ""
if [ $BLOCKED -eq 1 ]; then
    echo -e "${RED}=== COMMIT BLOCKED ===${NC}"
    echo "Sensitive data detected. Please remove before committing."
    echo "To bypass (NOT RECOMMENDED): git commit --no-verify"
    exit 1
elif [ $WARNED -eq 1 ]; then
    echo -e "${YELLOW}=== WARNINGS FOUND ===${NC}"
    echo "Review the warnings above. Continuing with commit..."
    echo "For thorough review, run: claude /security-review"
fi

echo -e "${GREEN}Security check passed${NC}"
exit 0
