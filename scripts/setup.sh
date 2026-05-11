#!/bin/bash

# Full automated setup: creates scratch org, deploys everything, loads data,
# and outputs the Claude connection details.
#
# Usage: ./scripts/setup.sh <DEVHUB_ALIAS>
# Example: ./scripts/setup.sh TDXDevHub

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DEVHUB=${1:-}
if [ -z "$DEVHUB" ]; then
  echo "Usage: ./scripts/setup.sh <DEVHUB_ALIAS>"
  echo "Example: ./scripts/setup.sh TDXDevHub"
  exit 1
fi

ORG_ALIAS="custom-logic-mcp"

echo "============================================"
echo " Pipeline Intelligence MCP — Full Setup"
echo "============================================"
echo ""

# Step 1: Create Scratch Org
echo "=== Step 1: Creating scratch org ==="
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias "$ORG_ALIAS" \
  --duration-days 30 \
  --set-default \
  --target-dev-hub "$DEVHUB" \
  --no-track-source
echo "Done."
echo ""

# Step 2: Deploy metadata (Apex, MCP Server)
echo "=== Step 2: Deploying metadata ==="
echo "  - Apex class (AccountPipelineService)"
echo "  - MCP Server Definition (Pipeline_Intelligence)"
sf project deploy start \
  --source-dir force-app/main/default/classes \
  --source-dir force-app/main/default/mcpServerDefinitions \
  --target-org "$ORG_ALIAS"
echo "Done."
echo ""

# Step 3: Generate password
echo "=== Step 3: Generating password ==="
sf org generate password --target-org "$ORG_ALIAS"
echo ""

# Step 4: Load sample data
echo "=== Step 4: Loading sample data ==="
"$SCRIPT_DIR/setup-data.sh" "$ORG_ALIAS"
echo ""

# Step 5: Open Setup for External Client App creation
ORG_URL=$(sf org display --target-org "$ORG_ALIAS" --json | jq -r '.result.instanceUrl')

echo ""
echo "============================================"
echo " Automated Setup Complete!"
echo "============================================"
echo ""
echo "Scratch Org: $ORG_ALIAS"
echo "Org URL: $ORG_URL"
echo ""
echo "--------------------------------------------"
echo " MANUAL STEP: Create External Client App"
echo "--------------------------------------------"
echo ""
echo "Opening Setup in your browser..."
sf org open --target-org "$ORG_ALIAS" \
  --path "/lightning/setup/ExternalClientAppManager/home"
echo ""
echo "In Setup, create a new External Client App:"
echo ""
echo "  1. Click 'New External Client App'"
echo "  2. Label: Pipeline Intelligence MCP"
echo "  3. Description: OAuth client for Claude MCP connection"
echo "  4. Contact Email: (your email)"
echo "  5. Save"
echo ""
echo "  Then configure OAuth:"
echo "  6. Expand 'API (Enable OAuth Settings)' → check OAuth"
echo "  7. Callback URL: https://claude.ai/api/mcp/auth_callback"
echo "  8. Scopes: Add 'mcp_api' and 'refresh_token'"
echo "  9. Check: 'Issue JWT-based access tokens for named users'"
echo "  10. Check: 'Require PKCE'"
echo "  11. Uncheck everything else"
echo "  12. Save"
echo ""
echo "  Then copy the Consumer Key:"
echo "  13. Go to Settings → Consumer Key and Secret"
echo "  14. Copy the Consumer Key"
echo ""
echo "--------------------------------------------"
echo " Connect Claude to your MCP Server"
echo "--------------------------------------------"
echo ""
echo "1. Open https://claude.ai → Customize → Connectors → + → Add custom connector"
echo ""
echo "2. Name: Pipeline Intelligence"
echo ""
echo "3. Server URL:"
echo "   https://api.salesforce.com/platform/mcp/v1/sandbox/Pipeline_Intelligence"
echo ""
echo "4. Advanced Settings → OAuth Client ID: paste the Consumer Key"
echo ""
echo "5. Click Add → Connect → Log in with your scratch org credentials"
echo ""
echo "--------------------------------------------"
echo " Test it"
echo "--------------------------------------------"
echo ""
echo "Ask Claude: \"What's happening with Acme's pipeline?\""
echo ""
echo "Expected: Fuzzy matches 'Acme Corporation', returns 3 deals,"
echo "          \$320K pipeline, weighted value, risk levels, health summary."
echo ""
