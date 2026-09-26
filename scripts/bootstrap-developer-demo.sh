#!/usr/bin/env bash
# Create local desktop-client configurations from a deployed DevSpace identity.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-developer-demo.sh --user <name> [options]

Options:
  --namespace <namespace>       DevSpace namespace (default: <user>-devspaces)
  --workspace <name>            DevWorkspace name (default: code-workspace-1)
  --output <directory>          Output directory (default: .demo/<user>)
  --openai-base-url <url>       Desktop-reachable MaaS URL, including /v1
  --anthropic-base-url <url>    Override MaaS root URL for Claude Code
  -h, --help                    Show this help

The generated files contain a developer-scoped MaaS API key. They are created
with mode 600 and must stay outside source control.
EOF
}

user=""
namespace=""
workspace="code-workspace-1"
output=""
openai_base_url_override=""
anthropic_base_url=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) user=${2:?missing value for --user}; shift 2 ;;
    --namespace) namespace=${2:?missing value for --namespace}; shift 2 ;;
    --workspace) workspace=${2:?missing value for --workspace}; shift 2 ;;
    --output) output=${2:?missing value for --output}; shift 2 ;;
    --openai-base-url) openai_base_url_override=${2:?missing value for --openai-base-url}; shift 2 ;;
    --anthropic-base-url) anthropic_base_url=${2:?missing value for --anthropic-base-url}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$user" ]] || { printf '%s\n' '--user is required' >&2; usage >&2; exit 2; }
command -v oc >/dev/null || { printf '%s\n' 'oc is required in PATH' >&2; exit 1; }
command -v jq >/dev/null || { printf '%s\n' 'jq is required in PATH' >&2; exit 1; }

namespace=${namespace:-"${user}-devspaces"}
output=${output:-".demo/${user}"}

workspace_json=$(oc get devworkspace "$workspace" -n "$namespace" -o json)
openai_base_url=$(jq -r '[.spec.template.components[]?.container.env[]? | select(.name == "OPENAI_BASE_URL") | .value][0] // empty' <<<"$workspace_json")
model=$(jq -r '[.spec.template.components[]?.container.env[]? | select(.name == "VLLM_MODEL_ID") | .value][0] // empty' <<<"$workspace_json")
api_key=$(oc get secret pca-maas-apikey -n "$namespace" -o jsonpath='{.data.api_key}' | base64 -d)

if [[ -n "$openai_base_url_override" ]]; then
  openai_base_url=${openai_base_url_override%/}
fi

[[ -n "$openai_base_url" ]] || { printf '%s\n' 'DevWorkspace has no OPENAI_BASE_URL' >&2; exit 1; }
[[ -n "$model" ]] || { printf '%s\n' 'DevWorkspace has no VLLM_MODEL_ID' >&2; exit 1; }
[[ -n "$api_key" ]] || { printf '%s\n' 'pca-maas-apikey/api_key is empty' >&2; exit 1; }
[[ "$openai_base_url" == https://* || "$openai_base_url" == http://* ]] || { printf '%s\n' 'MaaS URL must start with http:// or https://' >&2; exit 1; }
[[ "${openai_base_url%/}" == */v1 ]] || { printf '%s\n' 'MaaS OpenAI URL must end with /v1' >&2; exit 1; }
if [[ "$openai_base_url" == *".svc.cluster.local"* ]]; then
  printf '%s\n' 'The workspace MaaS URL is cluster-internal. Pass --openai-base-url https://<desktop-maas-host>/v1.' >&2
  exit 1
fi

umask 077
mkdir -p "$output"

{
  printf '%s\n' '# Source this file before starting Codex, Claude Code, or OpenCode.'
  printf 'export MAAS_OPENAI_BASE_URL=%q\n' "$openai_base_url"
  printf 'export MAAS_API_KEY=%q\n' "$api_key"
  printf 'export MAAS_MODEL=%q\n' "$model"
} >"$output/env.sh"

cat >"$output/codex-config.toml" <<EOF
# Copy into ~/.codex/config.toml, then: source $output/env.sh
model = "${model}"
model_provider = "private-maas"

[model_providers.private-maas]
name = "Private MaaS gateway"
base_url = "${openai_base_url}"
env_key = "MAAS_API_KEY"
wire_api = "chat"
EOF

jq -n --arg base_url "$openai_base_url" --arg model "$model" '
  {
    "$schema": "https://opencode.ai/config.json",
    provider: {
      "private-maas": {
        npm: "@ai-sdk/openai-compatible",
        name: "Private MaaS gateway",
        options: {baseURL: $base_url, apiKey: "{env:MAAS_API_KEY}"},
        models: {
          ($model): {
            name: "Private coding model",
            tool_call: true,
            limit: {context: 15000, output: 2048},
            options: {truncate_prompt_tokens: 14000}
          }
        }
      }
    },
    model: "private-maas/\($model)",
    agent: {
      demo: {
        description: "One-step MaaS readiness check",
        mode: "primary",
        model: "private-maas/\($model)",
        prompt: "Answer the user directly in one short sentence. Do not call tools.",
        steps: 1,
        tools: {
          bash: false, edit: false, write: false, read: false, grep: false,
          glob: false, list: false, task: false, todowrite: false,
          question: false, webfetch: false, skill: false, lsp: false
        }
      }
    }
  }
' >"$output/opencode.json"
rm -f "$output/opencode-auth.json" "$output/opencode-maas-proxy.mjs"

cat >"$output/continue-config.yaml" <<EOF
name: Private MaaS Coding Assistant
version: 1.0.0
schema: v1
models:
  - name: Private coding model
    provider: openai
    model: ${model}
    apiBase: ${openai_base_url}
    apiKey: ${api_key}
    roles: [chat, edit]
EOF

gateway_origin=${openai_base_url%/}
gateway_origin=${gateway_origin%/v1}
anthropic_base_url=${anthropic_base_url:-"$gateway_origin"}
cat >"$output/claude-code.env" <<EOF
# Source this file after sourcing env.sh, then run claude.
# Verify the selected vLLM runtime accepts Anthropic Messages requests first.
export ANTHROPIC_BASE_URL=${anthropic_base_url%/}
export ANTHROPIC_AUTH_TOKEN=\$MAAS_API_KEY
EOF

chmod 600 "$output"/*
printf 'Generated desktop client configuration in %s\n' "$output"
printf 'Source %s/env.sh before starting Codex or OpenCode.\n' "$output"
printf 'Before using Claude Code, validate POST /v1/messages on the selected vLLM runtime.\n'
