#!/usr/bin/env bash
# Run a sanitized end-to-end OpenCode -> MaaS -> vLLM readiness demo.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
user=${PCA_DEMO_USER:-dev-user1}
maas_url=${PCA_DEMO_MAAS_URL:?Set PCA_DEMO_MAAS_URL to the public MaaS URL ending in /v1}
output=${PCA_DEMO_OUTPUT:-"$HOME/private-maas-demo"}
demo_home=${PCA_DEMO_HOME:-"${TMPDIR:-/tmp}/opencode-maas-home"}

printf '\033[1;36mPrivate Coding Assistant: OpenCode MaaS Demo\033[0m\n\n'
printf '\033[1m1. Generate developer-scoped configuration\033[0m\n'
"$repo_root/scripts/bootstrap-developer-demo.sh" \
  --user "$user" \
  --openai-base-url "$maas_url" \
  --output "$output" >/dev/null
printf 'Developer configuration generated with mode 600.\n'

# shellcheck disable=SC1090
source "$output/env.sh"
export OPENCODE_CONFIG="$output/opencode.json"

printf '\n\033[1m2. Authenticate through MaaS and discover the model\033[0m\n'
curl_args=(--fail --silent --show-error --header "Authorization: Bearer $MAAS_API_KEY")
node_env=()
if [[ ${PCA_DEMO_INSECURE:-0} == 1 ]]; then
  curl_args+=(--insecure)
  node_env+=(NODE_TLS_REJECT_UNAUTHORIZED=0 NODE_NO_WARNINGS=1)
fi
model=$(curl "${curl_args[@]}" "${MAAS_OPENAI_BASE_URL}/models" | jq -r '.data[0].id')
printf 'MaaS model: \033[1;32m%s\033[0m\n' "$model"

printf '\n\033[1m3. Run OpenCode through MaaS\033[0m\n'
mkdir -p "$demo_home" "$demo_home/.config"
(
  cd "$demo_home"
  ready=false
  prompts=(
    "Run the connectivity check."
    "Report the configured readiness response."
    "Return the readiness text now."
    "Complete the connectivity check."
    "Print the configured response."
  )
  for prompt in "${prompts[@]}"; do
    opencode_output=$(env "${node_env[@]}" \
      HOME="$demo_home" \
      XDG_CONFIG_HOME="$demo_home/.config" \
      opencode run --pure --agent demo --model "private-maas/$MAAS_MODEL" \
      "$prompt" 2>/dev/null)
    while IFS= read -r line; do
      [[ "$line" == "OpenCode MaaS ready" || "$line" == "OpenCode MaaS ready." ]] && ready=true
    done <<<"$opencode_output"
    $ready && break
  done
  $ready || { printf 'OpenCode readiness response did not match.\n' >&2; exit 1; }
  printf '\n> demo · %s\n\nOpenCode MaaS ready\n' "$MAAS_MODEL"
)

printf '\n\033[1;32mEnd-to-end path verified: OpenCode -> MaaS -> vLLM\033[0m\n'
