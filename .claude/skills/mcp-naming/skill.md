---
name: mcp-naming
description: Naming conventions for Salesforce Hosted MCP Servers and Tools
---

# MCP Naming Conventions for Salesforce

## MCP Server
- **API Name / Developer Name**: PascalCase with underscores (e.g., `Pipeline_Intelligence`). Salesforce requires: alphanumeric + underscores only, must start with a letter, no consecutive underscores, no trailing underscore.
- **Label**: Title Case with spaces (e.g., `Pipeline Intelligence`)
- **File name**: matches API name (e.g., `Pipeline_Intelligence.mcpServerDefinition-meta.xml`)

## MCP Tool (within a server)
- **Tool Name (toolName)**: camelCase (e.g., `getAccountPipeline`)
- **Tool Title (toolTitle)**: Title Case with spaces (e.g., `Get Account Pipeline`)
- **Description**: Plain English sentence describing what it does and what inputs it takes

## URL Pattern
- Production: `https://api.salesforce.com/platform/mcp/v1/platform/<server-api-name>`
- Sandbox/Scratch: `https://api.salesforce.com/platform/mcp/v1/sandbox/<server-api-name>`
- Example: `https://api.salesforce.com/platform/mcp/v1/sandbox/Pipeline_Intelligence`

## External Client App (for OAuth)
- **API Name**: PascalCase with underscores (e.g., `Pipeline_Intelligence_MCP`)
- **Label**: Title Case (e.g., `Pipeline Intelligence MCP`)
