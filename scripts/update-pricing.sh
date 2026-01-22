#!/bin/bash
# Update Claude model pricing from Anthropic's website
# Run manually or via cron: 0 0 * * 0 /path/to/update-pricing.sh
#
# Usage: ./update-pricing.sh [output-path]
# Default output: ../pricing.json (relative to script location)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${1:-$SCRIPT_DIR/../pricing.json}"

echo "Fetching pricing from Anthropic..."

# Fetch pricing page
PRICING_HTML=$(curl -sL "https://claude.com/pricing" 2>/dev/null || curl -sL "https://docs.anthropic.com/en/docs/about-claude/models" 2>/dev/null)

if [ -z "$PRICING_HTML" ]; then
    echo "Error: Failed to fetch pricing page"
    exit 1
fi

# Create pricing JSON using Claude to parse the HTML
# This uses Claude Code's ability to understand the pricing structure
cat > /tmp/pricing_prompt.txt << 'EOF'
Parse the following HTML and extract Claude model pricing into JSON format.
Output ONLY valid JSON with this structure (no markdown, no explanation):
{
  "model-key": {"input": X.XX, "output": X.XX, "cacheRead": X.XX, "cacheWrite": X.XX}
}

Model keys should be lowercase with dashes, like: opus-4-5, sonnet-4-5, haiku-4-5, opus-4, sonnet-4, etc.
Prices are per million tokens in USD.

HTML content:
EOF

echo "$PRICING_HTML" >> /tmp/pricing_prompt.txt

# Use Claude to parse (if available), otherwise use fallback
if command -v claude &> /dev/null; then
    echo "Using Claude to parse pricing..."
    PRICING_JSON=$(claude --print -p "$(cat /tmp/pricing_prompt.txt)" 2>/dev/null | grep -v '^$' | tail -1)

    # Validate JSON
    if echo "$PRICING_JSON" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        echo "$PRICING_JSON" | python3 -m json.tool > "$OUTPUT_FILE"
        echo "Updated pricing saved to: $OUTPUT_FILE"
        cat "$OUTPUT_FILE"
    else
        echo "Error: Claude output was not valid JSON, using fallback"
        USE_FALLBACK=1
    fi
else
    echo "Claude CLI not available, using fallback pricing"
    USE_FALLBACK=1
fi

# Fallback: use hardcoded pricing
if [ "$USE_FALLBACK" = "1" ]; then
    cat > "$OUTPUT_FILE" << 'FALLBACK'
{
  "haiku-3": {"input": 0.25, "output": 1.25, "cacheRead": 0.03, "cacheWrite": 0.3},
  "haiku-3-5": {"input": 0.8, "output": 4.0, "cacheRead": 0.08, "cacheWrite": 1.0},
  "haiku-4-5": {"input": 1.0, "output": 5.0, "cacheRead": 0.1, "cacheWrite": 1.25},
  "opus-3": {"input": 15.0, "output": 75.0, "cacheRead": 1.5, "cacheWrite": 18.75},
  "opus-4": {"input": 15.0, "output": 75.0, "cacheRead": 1.5, "cacheWrite": 18.75},
  "opus-4-1": {"input": 15.0, "output": 75.0, "cacheRead": 1.5, "cacheWrite": 18.75},
  "opus-4-5": {"input": 5.0, "output": 25.0, "cacheRead": 0.5, "cacheWrite": 6.25},
  "sonnet-3-5": {"input": 3.0, "output": 15.0, "cacheRead": 0.3, "cacheWrite": 3.75},
  "sonnet-4": {"input": 3.0, "output": 15.0, "cacheRead": 0.3, "cacheWrite": 3.75},
  "sonnet-4-5": {"input": 3.0, "output": 15.0, "cacheRead": 0.3, "cacheWrite": 3.75}
}
FALLBACK
    echo "Fallback pricing saved to: $OUTPUT_FILE"
fi

rm -f /tmp/pricing_prompt.txt
echo "Done!"
