# illumio-mcp-server

# Illumio PCE Model Context Protocol (MCP) Server

A lightweight, zero-dependency **Bash MCP Server** designed to connect LLM clients (Claude Desktop, Cursor, Gemini CLI, ChatGPT MCP clients) directly to your **Illumio PCE REST API v2**.

## Features

- **Pure Bash + JSON-RPC 2.0**: No Node.js, Python runtime, or heavy containers required.
- **Stdio Transport**: Communicates via standard input/output with proper stderr log segregation.
- **Available Tools**:
  - `illumio_get_workloads`: Query workloads, labels, and VEN enforcement states.
  - `illumio_get_rulesets`: Inspect micro-segmentation policies.
  - `illumio_get_labels`: Fetch all configured PCE labels (Role, App, Env, Loc).

## Prerequisites

- `bash` (v4.0+)
- `curl`
- `jq`

```bash
# Ubuntu / Debian
sudo apt-get update && sudo apt-get install -y curl jq

# RHEL / CentOS / Rocky
sudo dnf install -y curl jq

# macOS (Homebrew)
brew install curl jq


---

### Step-by-Step Commands to Push to GitHub

```bash
mkdir illumio-mcp-server && cd illumio-mcp-server
git init -b main

# Create the files above, then stage and commit:
git add .
git commit -m "feat: initial commit for Illumio bash MCP server"

# Link to your GitHub repo and push
git remote add origin git@github.com:<your-username>/illumio-mcp-server.git
git push -u origin main

