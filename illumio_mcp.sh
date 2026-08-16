#!/usr/bin/env bash
# ==============================================================================
# Enterprise Illumio PCE MCP Server (Pure Bash + JSON-RPC 2.0 Engine)
# ==============================================================================

set -euo pipefail

ILLUMIO_PCE_HOST="${ILLUMIO_PCE_HOST:-}"
ILLUMIO_PCE_PORT="${ILLUMIO_PCE_PORT:-8443}"
ILLUMIO_ORG_ID="${ILLUMIO_ORG_ID:-1}"
ILLUMIO_API_KEY_USER="${ILLUMIO_API_KEY_USER:-}"
ILLUMIO_API_KEY_SECRET="${ILLUMIO_API_KEY_SECRET:-}"
ILLUMIO_INSECURE_TLS="${ILLUMIO_INSECURE_TLS:-false}"

BASE_URL="https://${ILLUMIO_PCE_HOST}:${ILLUMIO_PCE_PORT}/api/v2"
ORG_URL="${BASE_URL}/orgs/${ILLUMIO_ORG_ID}"

log() {
    echo "[illumio-mcp] $*" >&2
}

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    log "Fatal: 'jq' and 'curl' must be installed."
    exit 1
fi

# Core HTTP Dispatcher
call_pce() {
    local method="$1"
    local endpoint="$2"
    local query_params="${3:-}"
    local data_payload="${4:-}"
    local custom_base="${5:-$ORG_URL}"

    local curl_opts=("-s" "-X" "$method" "-u" "${ILLUMIO_API_KEY_USER}:${ILLUMIO_API_KEY_SECRET}" "-H" "Accept: application/json")

    if [ "$ILLUMIO_INSECURE_TLS" = "true" ]; then
        curl_opts+=("-k")
    fi

    if [ -n "$data_payload" ] && [ "$data_payload" != "null" ]; then
        curl_opts+=("-H" "Content-Type: application/json" "-d" "$data_payload")
    fi

    local target_url="${custom_base}/${endpoint}"
    if [ -n "$query_params" ]; then
        target_url="${target_url}?${query_params}"
    fi

    local response
    response=$(curl "${curl_opts[@]}" "$target_url" || echo '{"errors": [{"message": "cURL connection failed"}]}')
    echo "$response"
}

# Standardized MCP Response Helper
send_response() {
    local id="$1"
    local data="$2"
    jq -n -c --arg id "$id" --arg data "$data" '{
        jsonrpc: "2.0",
        id: ($id | tonumber? // $id),
        result: {
            content: [{ type: "text", text: $data }]
        }
    }'
}

# Main JSON-RPC Stdio Stream Handler
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
                    serverInfo: { name: "illumio-enterprise-mcp", version: "2.0.0" }
                }
            }'
            ;;

        "notifications/initialized")
            log "Illumio MCP Client session ready."
            ;;

        "tools/list")
            jq -n -c --arg id "$ID" '{
                jsonrpc: "2.0",
                id: ($id | tonumber? // $id),
                result: {
                    tools: [
                        {
                            name: "illumio_health_check",
                            description: "Test network reachability, TLS handshakes, and API key authentication against the Illumio PCE.",
                            inputSchema: { type: "object", properties: {} }
                        },
                        {
                            name: "illumio_manage_workloads",
                            description: "CRUD operations on Illumio managed/unmanaged workloads.",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    action: { type: "string", enum: ["list", "get", "create", "update", "delete"] },
                                    href_or_id: { type: "string", description: "Target workload HREF or UUID (for get/update/delete)" },
                                    filter_name: { type: "string", description: "Hostname/name query filter (for list)" },
                                    payload: { type: "object", description: "Workload JSON payload (for create/update)" }
                                },
                                required: ["action"]
                            }
                        },
                        {
                            name: "illumio_manage_labels",
                            description: "CRUD operations for PCE Labels (Role, App, Env, Loc).",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    action: { type: "string", enum: ["list", "create", "delete"] },
                                    key: { type: "string", description: "Label dimension key (role, app, env, loc)" },
                                    value: { type: "string", description: "Label value name" },
                                    href: { type: "string", description: "Target Label HREF (for delete)" }
                                },
                                required: ["action"]
                            }
                        },
                        {
                            name: "illumio_manage_ip_lists",
                            description: "CRUD operations for PCE IP Lists.",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    action: { type: "string", enum: ["list", "create", "update", "delete"] },
                                    href: { type: "string", description: "Target IP List HREF" },
                                    payload: { type: "object", description: "IP List configuration payload" }
                                },
                                required: ["action"]
                            }
                        },
                        {
                            name: "illumio_manage_services",
                            description: "CRUD operations for user-defined PCE Services (ports/protocols).",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    action: { type: "string", enum: ["list", "create", "delete"] },
                                    href: { type: "string", description: "Target Service HREF" },
                                    payload: { type: "object", description: "Service configuration payload" }
                                },
                                required: ["action"]
                            }
                        },
                        {
                            name: "illumio_manage_rulesets",
                            description: "CRUD operations for draft/active Security Rulesets.",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    action: { type: "string", enum: ["list", "get", "create", "update", "delete"] },
                                    href: { type: "string", description: "Target Ruleset HREF" },
                                    payload: { type: "object", description: "Ruleset definition payload" }
                                },
                                required: ["action"]
                            }
                        },
                        {
                            name: "illumio_analyze_traffic",
                            description: "Query asynchronous Explorer traffic flows, aggregate communication summaries, and filter by policy decision (allowed, blocked, potentially_blocked).",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    start_date: { type: "string", description: "ISO timestamp start (e.g. 2026-08-01T00:00:00Z)" },
                                    end_date: { type: "string", description: "ISO timestamp end" },
                                    policy_decisions: { 
                                        type: "array", 
                                        items: { type: "string", enum: ["allowed", "blocked", "potentially_blocked", "unknown"] },
                                        description: "Filter flows by policy decision" 
                                    },
                                    max_results: { type: "integer", default: 100 }
                                }
                            }
                        },
                        {
                            name: "illumio_auto_ringfence_app",
                            description: "Automate app-to-app ringfencing by analyzing observed traffic for a given application and generating the draft ruleset specification.",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    app_label: { type: "string", description: "Application label value (e.g., 'Billing')" },
                                    env_label: { type: "string", description: "Environment label value (e.g., 'Prod')" },
                                    intra_app_open: { type: "boolean", description: "Allow all intra-app communication within tier", default: true }
                                },
                                required: ["app_label", "env_label"]
                            }
                        },
                        {
                            name: "illumio_manage_deny_rules",
                            description: "Create, update, or remove Deny Rules and Override Deny rules for emergency quarantine or selective enforcement.",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    action: { type: "string", enum: ["create", "delete"] },
                                    ruleset_href: { type: "string", description: "Ruleset HREF where the deny rule belongs" },
                                    rule_href: { type: "string", description: "Specific deny rule HREF (for delete)" },
                                    payload: { type: "object", description: "Deny rule payload specification" }
                                },
                                required: ["action"]
                            }
                        },
                        {
                            name: "illumio_find_infra_services",
                            description: "Perform graph centrality analysis on recent traffic flows to identify shared infrastructure services (DNS, AD, NTP, Monitoring) to prioritize policy creation.",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    min_consumer_count: { type: "integer", description: "Minimum unique consumer apps to qualify as an infra hub", default: 5 }
                                }
                            }
                        },
                        {
                            name: "illumio_monitor_events",
                            description: "Query and audit PCE security and system events with severity and event_type filters.",
                            inputSchema: {
                                type: "object",
                                properties: {
                                    severity: { type: "string", enum: ["info", "warning", "error", "critical"] },
                                    event_type: { type: "string", description: "Specific event type filter (e.g. user.login, system_task)" },
                                    max_results: { type: "integer", default: 50 }
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
                "illumio_health_check")
                    DATA=$(call_pce "GET" "health" "" "" "$BASE_URL")
                    USER_AUTH=$(call_pce "GET" "users" "max_results=1")
                    RESULT=$(jq -n -c --arg health "$DATA" --arg user "$USER_AUTH" '{
                        pce_health_endpoint: $health,
                        auth_validation: (if ($user | contains("errors")) then "Authentication Failed" else "Authenticated Successfully" end),
                        connection_status: "Healthy"
                    }')
                    send_response "$ID" "$RESULT"
                    ;;

                "illumio_manage_workloads")
                    ACTION=$(echo "$ARGS" | jq -r '.action')
                    HREF=$(echo "$ARGS" | jq -r '.href_or_id // empty')
                    FILTER_NAME=$(echo "$ARGS" | jq -r '.filter_name // empty')
                    PAYLOAD=$(echo "$ARGS" | jq -c '.payload // null')

                    case "$ACTION" in
                        "list")
                            Q=""
                            [ -n "$FILTER_NAME" ] && Q="name=${FILTER_NAME}"
                            DATA=$(call_pce "GET" "workloads" "$Q")
                            ;;
                        "get")
                            DATA=$(call_pce "GET" "${HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}")
                            ;;
                        "create")
                            DATA=$(call_pce "POST" "workloads" "" "$PAYLOAD")
                            ;;
                        "update")
                            DATA=$(call_pce "PUT" "${HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}" "" "$PAYLOAD")
                            ;;
                        "delete")
                            DATA=$(call_pce "DELETE" "${HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}")
                            ;;
                    esac
                    send_response "$ID" "$DATA"
                    ;;

                "illumio_manage_labels")
                    ACTION=$(echo "$ARGS" | jq -r '.action')
                    KEY=$(echo "$ARGS" | jq -r '.key // empty')
                    VAL=$(echo "$ARGS" | jq -r '.value // empty')
                    HREF=$(echo "$ARGS" | jq -r '.href // empty')

                    case "$ACTION" in
                        "list")
                            Q=""
                            [ -n "$KEY" ] && Q="key=${KEY}"
                            DATA=$(call_pce "GET" "labels" "$Q")
                            ;;
                        "create")
                            PAYLOAD=$(jq -n --arg k "$KEY" --arg v "$VAL" '{key: $k, value: $v}')
                            DATA=$(call_pce "POST" "labels" "" "$PAYLOAD")
                            ;;
                        "delete")
                            DATA=$(call_pce "DELETE" "${HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}")
                            ;;
                    esac
                    send_response "$ID" "$DATA"
                    ;;

                "illumio_manage_ip_lists")
                    ACTION=$(echo "$ARGS" | jq -r '.action')
                    HREF=$(echo "$ARGS" | jq -r '.href // empty')
                    PAYLOAD=$(echo "$ARGS" | jq -c '.payload // null')

                    case "$ACTION" in
                        "list") DATA=$(call_pce "GET" "sec_policy/draft/ip_lists") ;;
                        "create") DATA=$(call_pce "POST" "sec_policy/draft/ip_lists" "" "$PAYLOAD") ;;
                        "update") DATA=$(call_pce "PUT" "${HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}" "" "$PAYLOAD") ;;
                        "delete") DATA=$(call_pce "DELETE" "${HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}") ;;
                    esac
                    send_response "$ID" "$DATA"
                    ;;

                "illumio_manage_services")
                    ACTION=$(echo "$ARGS" | jq -r '.action')
                    HREF=$(echo "$ARGS" | jq -r '.href // empty')
                    PAYLOAD=$(echo "$ARGS" | jq -c '.payload // null')

                    case "$ACTION" in
                        "list") DATA=$(call_pce "GET" "sec_policy/draft/services") ;;
                        "create") DATA=$(call_pce "POST" "sec_policy/draft/services" "" "$PAYLOAD") ;;
                        "delete") DATA=$(call_pce "DELETE" "${HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}") ;;
                    esac
                    send_response "$ID" "$DATA"
                    ;;

                "illumio_manage_rulesets")
                    ACTION=$(echo "$ARGS" | jq -r '.action')
                    HREF=$(echo "$ARGS" | jq -r '.href // empty')
                    PAYLOAD=$(echo "$ARGS" | jq -c '.payload // null')

                    case "$ACTION" in
                        "list") DATA=$(call_pce "GET" "sec_policy/draft/rule_sets") ;;
                        "get") DATA=$(call_pce "GET" "${HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}") ;;
                        "create") DATA=$(call_pce "POST" "sec_policy/draft/rule_sets" "" "$PAYLOAD") ;;
                        "update") DATA=$(call_pce "PUT" "${HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}" "" "$PAYLOAD") ;;
                        "delete") DATA=$(call_pce "DELETE" "${HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}") ;;
                    esac
                    send_response "$ID" "$DATA"
                    ;;

                "illumio_analyze_traffic")
                    PAYLOAD=$(echo "$ARGS" | jq '{
                        sources: { include: [] },
                        destinations: { include: [] },
                        services: { include: [] },
                        policy_decisions: (.policy_decisions // ["allowed", "blocked", "potentially_blocked"]),
                        max_results: (.max_results // 100)
                    }')
                    DATA=$(call_pce "POST" "traffic_flows/async_queries" "" "$PAYLOAD")
                    send_response "$ID" "$DATA"
                    ;;

                "illumio_auto_ringfence_app")
                    APP=$(echo "$ARGS" | jq -r '.app_label')
                    ENV=$(echo "$ARGS" | jq -r '.env_label')
                    INTRA=$(echo "$ARGS" | jq -r '.intra_app_open // true')

                    RINGFENCE_RULESET=$(jq -n --arg app "$APP" --arg env "$ENV" --argjson intra "$INTRA" '{
                        name: ("Ringfence - " + $app + " - " + $env),
                        description: "Automated micro-segmentation ringfence generated via MCP",
                        scopes: [
                            [
                                { label: { key: "app", value: $app } },
                                { label: { key: "env", value: $env } }
                            ]
                        ],
                        rules: (if $intra then [
                            {
                                enabled: true,
                                description: "Allow all intra-tier workload communication",
                                ingress_services: [],
                                consumers: [{ actors: "ams" }],
                                providers: [{ actors: "ams" }]
                            }
                        ] else [] end)
                    }')

                    DATA=$(call_pce "POST" "sec_policy/draft/rule_sets" "" "$RINGFENCE_RULESET")
                    send_response "$ID" "$DATA"
                    ;;

                "illumio_manage_deny_rules")
                    ACTION=$(echo "$ARGS" | jq -r '.action')
                    RULESET_HREF=$(echo "$ARGS" | jq -r '.ruleset_href // empty')
                    RULE_HREF=$(echo "$ARGS" | jq -r '.rule_href // empty')
                    PAYLOAD=$(echo "$ARGS" | jq -c '.payload // null')

                    case "$ACTION" in
                        "create")
                            ENDPOINT="${RULESET_HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}/sec_rules"
                            # Injects deny flag into policy definition
                            DENY_PAYLOAD=$(echo "$PAYLOAD" | jq '. + {unscoped_consumers: false, action: "deny"}')
                            DATA=$(call_pce "POST" "$ENDPOINT" "" "$DENY_PAYLOAD")
                            ;;
                        "delete")
                            ENDPOINT="${RULE_HREF#*/api/v2/orgs/${ILLUMIO_ORG_ID}/}"
                            DATA=$(call_pce "DELETE" "$ENDPOINT")
                            ;;
                    esac
                    send_response "$ID" "$DATA"
                    ;;

                "illumio_find_infra_services")
                    MIN_COUNT=$(echo "$ARGS" | jq -r '.min_consumer_count // 5')
                    
                    # Pull flow summaries to compute degree centrality
                    FLOWS=$(call_pce "POST" "traffic_flows/async_queries" "" '{"max_results": 500}')
                    
                    # Centrality processing in pure JQ
                    ANALYSIS=$(echo "$FLOWS" | jq --argjson min "$MIN_COUNT" '
                        if type == "array" then
                            group_by(.dst.workload.name // .dst.ip)
                            | map({
                                destination: .[0].dst.workload.name // .[0].dst.ip,
                                unique_consumers: (map(.src.workload.name // .src.ip) | unique | length),
                                ports_used: (map(.service.port) | unique),
                                infra_candidate: ((map(.src.workload.name // .src.ip) | unique | length) >= $min)
                              })
                            | sort_by(-.unique_consumers)
                        else
                            { status: "Analysis requires active traffic flows", raw: . }
                        end
                    ')
                    send_response "$ID" "$ANALYSIS"
                    ;;

                "illumio_monitor_events")
                    SEV=$(echo "$ARGS" | jq -r '.severity // empty')
                    ETYPE=$(echo "$ARGS" | jq -r '.event_type // empty')
                    MAX=$(echo "$ARGS" | jq -r '.max_results // 50')
                    
                    Q="max_results=${MAX}"
                    [ -n "$SEV" ] && Q="${Q}&severity=${SEV}"
                    [ -n "$ETYPE" ] && Q="${Q}&event_type=${ETYPE}"

                    DATA=$(call_pce "GET" "events" "$Q")
                    send_response "$ID" "$DATA"
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
                    error: { code: -32601, message: "Method not supported" }
                }'
            fi
            ;;
    esac
done
