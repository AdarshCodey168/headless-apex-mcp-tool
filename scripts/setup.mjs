#!/usr/bin/env node

/**
 * Full automated setup: creates scratch org, deploys everything, loads data,
 * and outputs the Claude connection details.
 *
 * Usage: node scripts/setup.mjs <DEVHUB_ALIAS>
 * Example: node scripts/setup.mjs TDXDevHub
 */

import { execSync } from "child_process";
import {
  cpSync,
  mkdirSync,
  rmSync,
  readFileSync,
  writeFileSync,
  readdirSync,
} from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_DIR = join(__dirname, "..");
const DEPLOY_DIR = join(PROJECT_DIR, ".deploy-tmp");
const DATA_DIR = join(PROJECT_DIR, "data");
const DATA_TMP_DIR = join(DATA_DIR, ".tmp");
const ORG_ALIAS = "custom-logic-mcp";

const devHub = process.argv[2];
if (!devHub) {
  console.log("Usage: node scripts/setup.mjs <DEVHUB_ALIAS>");
  console.log("Example: node scripts/setup.mjs TDXDevHub");
  process.exit(1);
}

function run(cmd) {
  execSync(cmd, { cwd: PROJECT_DIR, encoding: "utf-8", stdio: "inherit" });
}

function runJson(cmd) {
  const output = execSync(cmd, {
    cwd: PROJECT_DIR,
    encoding: "utf-8",
    stdio: "pipe",
  });
  return JSON.parse(output);
}

function cleanup() {
  rmSync(DEPLOY_DIR, { recursive: true, force: true });
  rmSync(DATA_TMP_DIR, { recursive: true, force: true });
}

function walkAndPatch(dir, replacements) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      walkAndPatch(fullPath, replacements);
    } else if (entry.name.endsWith(".xml") || entry.name.endsWith(".json")) {
      let content = readFileSync(fullPath, "utf-8");
      let changed = false;
      for (const [placeholder, value] of Object.entries(replacements)) {
        if (content.includes(placeholder)) {
          content = content.replaceAll(placeholder, value);
          changed = true;
        }
      }
      if (changed) {
        writeFileSync(fullPath, content, "utf-8");
      }
    }
  }
}

process.on("exit", cleanup);
process.on("SIGINT", () => {
  cleanup();
  process.exit(1);
});

console.log("============================================");
console.log(" Pipeline Intelligence MCP — Full Setup");
console.log("============================================\n");

// Step 1: Create Scratch Org
console.log("=== Step 1: Creating scratch org ===");
run(
  `sf org create scratch --definition-file config/project-scratch-def.json --alias ${ORG_ALIAS} --duration-days 30 --set-default --target-dev-hub ${devHub} --no-track-source`
);
console.log("Done.\n");

// Step 2: Generate password
console.log("=== Step 2: Generating password ===");
run(`sf org generate password --target-org ${ORG_ALIAS}`);
console.log("Done.\n");

// Step 3: Deploy metadata (Apex, MCP Server)
console.log("=== Step 3: Deploying metadata ===");
console.log("  - Apex class (AccountPipelineService)");
console.log("  - MCP Server Definition (Pipeline_Intelligence)\n");

const orgInfo = runJson(`sf org display --target-org ${ORG_ALIAS} --json`);

run(
  `sf project deploy start --source-dir force-app/main/default/classes --source-dir force-app/main/default/mcpServerDefinitions --target-org ${ORG_ALIAS}`
);
console.log("Done.\n");

// Step 4: Load sample data
console.log("=== Step 4: Loading sample data ===");

const standardPbResult = runJson(
  `sf data query --target-org ${ORG_ALIAS} --query "SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1" --result-format json`
);
const standardPbId = standardPbResult.result.records[0].Id;

console.log(`  Standard Pricebook ID: ${standardPbId}`);
run(
  `sf data update record --target-org ${ORG_ALIAS} --sobject Pricebook2 --record-id ${standardPbId} --values "IsActive=true"`
);

mkdirSync(DATA_TMP_DIR, { recursive: true });
cpSync(DATA_DIR, DATA_TMP_DIR, {
  recursive: true,
  filter: (src) => !src.includes(".tmp"),
});
walkAndPatch(DATA_TMP_DIR, { __STANDARD_PRICEBOOK_ID__: standardPbId });

run(`sf data import tree --plan ${join(DATA_TMP_DIR, "data-plan.json")} --target-org ${ORG_ALIAS}`);
console.log("Done.\n");

// Step 5: Output connection details
const orgUrl = orgInfo.result.instanceUrl;
const username = orgInfo.result.username;

console.log("============================================");
console.log(" Automated Setup Complete!");
console.log("============================================\n");
console.log(`Scratch Org: ${ORG_ALIAS}`);
console.log(`Org URL: ${orgUrl}`);
console.log(`Username: ${username}`);
console.log(`(Password shown above from Step 2)\n`);

console.log("Opening Setup for External Client App creation...\n");
run(`sf org open --target-org ${ORG_ALIAS} --path "/lightning/setup/ExternalClientAppManager/home"`);

console.log("\n--------------------------------------------");
console.log(" MANUAL STEP: Create External Client App");
console.log("--------------------------------------------\n");
console.log("In Setup, create a new External Client App:\n");
console.log("  1. Click 'New External Client App'");
console.log("  2. Label: Pipeline Intelligence MCP");
console.log("  3. Description: OAuth client for Claude MCP connection");
console.log("  4. Contact Email: (your email)");
console.log("  5. Save\n");
console.log("  Then configure OAuth:");
console.log("  6. Expand 'API (Enable OAuth Settings)' → check OAuth");
console.log("  7. Callback URL: https://claude.ai/api/mcp/auth_callback");
console.log("  8. Scopes: Add 'mcp_api' and 'refresh_token'");
console.log("  9. Check: 'Issue JWT-based access tokens for named users'");
console.log("  10. Check: 'Require PKCE'");
console.log("  11. Uncheck everything else");
console.log("  12. Save\n");
console.log("  Then copy the Consumer Key:");
console.log("  13. Go to Settings → Consumer Key and Secret");
console.log("  14. Copy the Consumer Key\n");
console.log("--------------------------------------------");
console.log(" Connect Claude to your MCP Server");
console.log("--------------------------------------------\n");
console.log("1. Open https://claude.ai → Customize → Connectors → + → Add custom connector\n");
console.log("2. Name: Pipeline Intelligence\n");
console.log("3. Server URL:");
console.log("   https://api.salesforce.com/platform/mcp/v1/sandbox/Pipeline_Intelligence\n");
console.log("4. Advanced Settings → OAuth Client ID: paste the Consumer Key\n");
console.log("5. Click Add → Connect → Log in with your scratch org credentials\n");
console.log("--------------------------------------------");
console.log(" Test it");
console.log("--------------------------------------------\n");
console.log('Ask Claude: "What\'s happening with Acme\'s pipeline?"\n');
console.log("Expected: Fuzzy matches 'Acme Corporation', returns 3 deals,");
console.log("          $320K pipeline, weighted value, risk levels, health summary.\n");
