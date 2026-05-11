# Custom Logic as Hosted MCP on Salesforce

This project demonstrates how to expose custom Apex business logic as a Hosted MCP Server on Salesforce, making it available to AI clients like Claude.

The example exposes a **Pipeline Intelligence** tool that takes an account name and returns a rich analysis — deal risk scoring, weighted forecasts, and pipeline health assessment — by traversing Salesforce's native business object graph (Account → Opportunity → OpportunityLineItem → Product2).

## What This Demonstrates

- Custom Apex logic exposed as an MCP tool via `@InvocableMethod`
- Cross-object graph traversal that only Salesforce provides out-of-the-box
- Business intelligence computed server-side (risk levels, weighted pipeline, health summary)
- Fuzzy account name matching
- Field-level security enforced automatically via `WITH SECURITY_ENFORCED`

## Prerequisites

- Node.js (v18+)
- Salesforce CLI (`sf`) installed
- A DevHub-enabled org
- Claude.ai account (Pro or Team) for testing the MCP connection

## Quick Start

One command does everything — creates the org, deploys metadata, loads data, and opens the browser for the one manual step.

**macOS / Linux:**
```bash
./scripts/setup.sh <YOUR_DEVHUB_ALIAS>
```

**Windows (or any OS with Node.js):**
```bash
node scripts/setup.mjs <YOUR_DEVHUB_ALIAS>
```

## Manual Setup (Step by Step)

### 1. Create a Scratch Org

```bash
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias custom-logic-mcp \
  --duration-days 30 \
  --set-default \
  --target-dev-hub <YOUR_DEVHUB_ALIAS> \
  --no-track-source
```

### 2. Deploy the Apex Class

```bash
sf project deploy start --source-dir force-app --target-org custom-logic-mcp
```

### 3. Load Sample Data

```bash
node scripts/setup-data.mjs custom-logic-mcp
```

This creates:
- 2 Accounts (Acme Corporation, Globox Industries)
- 5 open Opportunities across both accounts
- 9 Opportunity Line Items with products (Enterprise License, Premium Support, Data Storage, Implementation Services)

### 4. Register the MCP Server

1. In your scratch org, go to **Setup → Integration → Salesforce MCP Servers**
2. Create a new Custom MCP Server:
   - **Name**: `Pipeline_Intelligence`
   - **Label**: Pipeline Intelligence
   - **Description**: Analyzes account pipeline health with deal risk scoring and weighted forecasts by traversing Salesforce's native business object graph.
3. Add a tool:
   - **Backing Type**: Apex Action
   - **Action**: Get Account Pipeline
   - **Tool Name**: `getAccountPipeline`
   - **Tool Description**: Returns open deals with products, risk levels, and pipeline health summary for any account. Supports partial name matching.

### 5. Create an External Client App

1. Go to **Setup → External Client App Manager → New External Client App**
2. Fill in basic info
3. Under **API (Enable OAuth Settings)**:
   - **Callback URL**: `https://claude.ai/api/mcp/auth_callback`
   - **OAuth Scopes**: Add `mcp_api` and `refresh_token`
4. Under **Security**:
   - Check: "Issue JSON Web Token (JWT)-based access tokens for named users"
   - Check: "Require Proof Key for Code Exchange (PKCE) extension"
   - Uncheck everything else
5. Save and wait a few minutes for activation
6. Go to **Settings → Consumer Key and Secret** and copy the **Consumer Key**

### 6. Connect Claude to the MCP Server

In **Claude.ai** (web):

1. Left sidebar → **Customize**
2. Click **Connectors** → the **+** button
3. Select **Add custom connector**
4. Enter a name (e.g., "Pipeline Intelligence")
5. Copy the **Server URL** from Salesforce Setup:
   - Go to **Setup → Integrations → MCP Servers**
   - Click your MCP Server name ("Pipeline Intelligence")
   - Under **Authentication Details**, copy the **Server URL**
   
   > **Note:** Sandbox/scratch orgs use `https://api.salesforce.com/platform/mcp/v1/sandbox/custom/<NAME>`. Production/Developer Edition orgs use `https://api.salesforce.com/platform/mcp/v1/custom/<NAME>`.

6. Paste the Server URL into the connector configuration
6. In **Advanced settings**, paste your **OAuth Consumer Key** into the "OAuth Client ID" field
7. Click **Add**, then click **Connect**
8. Log in with your scratch org credentials when redirected
9. After auth succeeds, configure tool permissions

### 7. Test It

In a Claude conversation, ask:

> "What's happening with Acme's pipeline?"

Claude will invoke the `get_account_pipeline` tool and return a rich analysis including:
- Account matched via fuzzy search ("Acme" → "Acme Corporation")
- 3 open deals totaling ~$320K
- Weighted pipeline value (~$204K based on probability)
- Risk level per deal (Low/Medium/High)
- Overall pipeline health assessment ("Strong — high confidence, low risk")

## Project Structure

```
force-app/main/default/classes/
└── AccountPipelineService.cls       # The MCP tool implementation

data/
├── data-plan.json                   # Import plan (dependency order)
├── Product2.json                    # 4 products
├── PricebookEntry.json              # Standard Pricebook entries
├── Account.json                     # 2 accounts
├── Opportunity.json                 # 5 open opportunities
└── OpportunityLineItem.json         # 9 line items

scripts/
├── setup.sh                         # Full setup (macOS/Linux)
├── setup.mjs                        # Full setup (Windows/cross-platform)
└── setup-data.sh                    # Data-only setup (macOS/Linux)

config/
└── project-scratch-def.json         # Scratch org definition with AI features

.claude/skills/mcp-naming/
└── skill.md                         # MCP naming conventions for Claude Code
```

## How the Apex Works

The `AccountPipelineService` class is a **deep module** (per John Ousterhout's "A Philosophy of Software Design"):

- **Simple interface**: One input (account name) → rich structured output
- **Complex internals hidden**: Fuzzy matching, multi-object traversal, risk algorithms, weighted math, health assessment
- **Errors defined out of existence**: Partial name matching means "not found" is rare

The class uses `global` access on the method and input/output types (required for MCP tool discovery) while keeping all business logic in `private` helper methods.
