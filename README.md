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

Capabilities OverviewCategoryAvailable MCP ToolFunctional ScopePCE Diagnosticsillumio_health_checkValidates API credentials, network reachability, and PCE status.Object CRUDillumio_manage_workloadsillumio_manage_labelsillumio_manage_ip_listsillumio_manage_servicesillumio_manage_rulesetsFull GET, POST, PUT, DELETE operations across all core segmentation building blocks.Traffic & Visibilityillumio_analyze_trafficQueries asynchronous flow queries with policy decision filtering (allowed, blocked, potentially_blocked).Automated Policyillumio_auto_ringfence_appTakes app_label and env_label to auto-construct scoped draft rulesets in one command.Enforcement & Denyillumio_manage_deny_rulesCreates or removes explicit deny rules and override quarantine rules for selective enforcement.Graph Intelligenceillumio_find_infra_servicesUses graph consumer centrality on traffic patterns to surface common infrastructure hubs (Active Directory, DNS, NTP) to prioritize foundational policies.Auditing & SIEMillumio_monitor_eventsQueries PCE audit logs filtered by severity (info, warning, error, critical) and event types.
