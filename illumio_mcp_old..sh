#!/usr/bin/env bash
# ==============================================================================
# Illumio PCE Model Context Protocol (MCP) Server (Bash / Stdio JSON-RPC)
# ==============================================================================

set -euo pipefail

# Configuration defaults
ILLUMIO_PCE_HOST="${ILLUMIO_PCE_HOST:-}"
ILLUMIO_PCE_PORT="${ILLUMIO_PCE_PORT:-8443}"
ILLUMIO_ORG_ID="${ILLUMIO_ORG_ID:-1}"
ILLUMIO_API_KEY_USER="${ILLUMIO_API_KEY_USER:-}"
ILLUMIO_API_KEY_SECRET="${ILLUMIO_API_KEY_SECRET:-}"
ILLUMIO_INSECURE_TLS="${ILLUMIO_INSECURE_TLS:-false}"

BASE_URL="https://${ILLUMIO_PCE_HOST}:${ILLUMIO_PCE_PORT}/api/v2/orgs/${ILLUMIO_ORG_ID}"

log() {
    # Strictly output logs to stderr to preserve standard JSON-RPC 2.0 stdout stream
    echo "[illumio-mcp] $*" >&2
}

# Pre-flight check
if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    log "Error: Dependencies 'jq' and 'curl' are required."
    exit 1
fi

if [ -z "$ILLUMIO_PCE_HOST" ] || [ -z "$ILLUMIO_API_KEY_USER" ] || [ -z "$ILLUMIO_API_KEY_SECRET" ]; then
    log "Warning: Missing ILLUMIO_PCE_HOST, ILLUMIO_API_KEY_USER, or ILLUMIO_API_KEY_SECRET."
fi

call_illumio() {
    local endpoint="$1"
    local query_params="${2:-}"
    local curl_opts=("-s" "-X" "GET" "-u" "${ILLUMIO_API_KEY_USER}:${ILLUMIO_API_KEY_SECRET}" "-H" "Accept: application/json")

    if [ "$ILLUMIO_INSECURE_TLS" = "true" ]; then
        curl_opts+=("-k")
    fi

    local target_url="${BASE_URL}/${endpoint}"
    if [ -n "$query_params" ]; then
        target_url="${target_url}?${query_params}"
    fi

    local response
    response=$(curl "${curl_opts[@]}" "$target_url" || echo '{"error": "cURL execution failed"}')
    echo "$response"
}

# Main JSON-RPC Event Loop
while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue

    METHOD=$(echo "$line" | jq -r '.method // empty')
    ID=$(echo "$line" | jq -r '.id // empty')

    case "$METHOD" in
        "initialize")
            jq -n -c --arg id "$ID" '{
                jsonrpc: "2.0",
                id: ($id | tonumber? // $id),
                result: {
                    protocolVersion: "2024-11-05",
                    capabilities: { tools: {} },
                    serverInfo: { name: "illumio-bash-mcp", version: "1.0.0" }
                }
            }'
            ;;

        "notifications/initialized")
            log "Client connected and initialized."
            ;;

        "tools/list")
            jq -n -c --arg id "$ID" '{
                jsonrpc: "2.0",
                id: ($id | tonumber? // $id),
                result: {
                    tools: [
                        {
                            name: "illumio_get_workloads",
                            description: "Fetch managed workloads, VEN status, and labels from Illumio PCE.",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    name: { type: "string", description: "Filter workloads by hostname/name" },
                                    max_results: { type: "integer", description: "Max results to return (default: 50)", default: 50 }
                                }
                            }
                        },
                        {
                            name: "illumio_get_rulesets",
                            description: "Retrieve micro-segmentation rulesets and policy definitions.",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    name: { type: "string", description: "Filter by ruleset name" }
                                }
                            }
                        },
                        {
                            name: "illumio_get_labels",
                            description: "Retrieve all provisioned policy labels (Role, App, Env, Loc).",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    key: { type: "string", description: "Filter label key (role, app, env, loc)" }
                                }
                            }
                        }
                    ]
                }
            }'
            ;;

        "tools/call")
            TOOL_NAME=$(echo "$line" | jq -r '.params.name // empty')
            ARGS=$(echo "$line" | jq -c '.params.arguments // {}')

            case "$TOOL_NAME" in
                "illumio_get_workloads")
                    MAX_RESULTS=$(echo "$ARGS" | jq -r '.max_results // 50')
                    NAME_FILTER=$(echo "$ARGS" | jq -r '.name // empty')
                    QUERY="max_results=${MAX_RESULTS}"
                    [ -n "$NAME_FILTER" ] && QUERY="${QUERY}&name=${NAME_FILTER}"

                    DATA=$(call_illumio "workloads" "$QUERY")

                    jq -n -c --arg id "$ID" --arg data "$DATA" '{
                        jsonrpc: "2.0",
                        id: ($id | tonumber? // $id),
                        result: {
                            content: [{ type: "text", text: $data }]
                        }
                    }'
                    ;;

                "illumio_get_rulesets")
                    DATA=$(call_illumio "sec_policy/draft/rule_sets" "")

                    jq -n -c --arg id "$ID" --arg data "$DATA" '{
                        jsonrpc: "2.0",
                        id: ($id | tonumber? // $id),
                        result: {
                            content: [{ type: "text", text: $data }]
                        }
                    }'
                    ;;

                "illumio_get_labels")
                    KEY_FILTER=$(echo "$ARGS" | jq -r '.key // empty')
                    QUERY=""
                    [ -n "$KEY_FILTER" ] && QUERY="key=${KEY_FILTER}"

                    DATA=$(call_illumio "labels" "$QUERY")

                    jq -n -c --arg id "$ID" --arg data "$DATA" '{
                        jsonrpc: "2.0",
                        id: ($id | tonumber? // $id),
                        result: {
                            content: [{ type: "text", text: $data }]
                        }
                    }'
                    ;;

                *)
                    jq -n -c --arg id "$ID" --arg tool "$TOOL_NAME" '{
                        jsonrpc: "2.0",
                        id: ($id | tonumber? // $id),
                        error: { code: -32601, message: ("Unknown tool: " + $tool) }
                    }'
                    ;;
            esac
            ;;

        *)
            if [ -n "$ID" ]; then
                jq -n -c --arg id "$ID" '{
                    jsonrpc: "2.0",
                    id: ($id | tonumber? // $id),
                    error: { code: -32601, message: "Method not found" }
                }'
            fi
            ;;
    esac
done
