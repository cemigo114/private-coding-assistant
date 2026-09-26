# Desktop Developer Demo

This guide demonstrates the same private coding model from VS Code, Codex CLI,
Claude Code, and OpenCode. All supported requests use the developer's
`pca-maas-apikey` and flow through MaaS, llm-d, and vLLM. Do not give a desktop
client a raw vLLM or llm-d address.

## Prerequisites

- A deployed DevSpace for the developer, such as `dev-user1-devspaces`.
- `oc` logged into the target cluster and `jq` installed on the demo machine.
- A MaaS listener address reachable from the demo machine. The default
  `*.svc.cluster.local` address in a DevWorkspace only works inside the cluster.
- A trusted TLS certificate for the desktop-reachable gateway hostname. Do not
  disable certificate verification for a customer demonstration.

If the existing deployment has only an in-cluster listener, use the Dev Spaces
terminal for the demo or add a properly authenticated desktop-reachable MaaS
listener before proceeding.

## Generate Per-Developer Files

The bootstrap reads the deployed workspace's `OPENAI_BASE_URL`, model ID, and
the matching `pca-maas-apikey` Secret. It writes files with mode `600` and does
not modify a user's home-directory configuration automatically.

```bash
scripts/bootstrap-developer-demo.sh --user dev-user1 \
  --openai-base-url https://maas.apps.example.com/v1 \
  --output "$HOME/private-maas-demo"
```

Source the generated environment before using Codex or OpenCode:

```bash
source "$HOME/private-maas-demo/env.sh"
export OPENCODE_CONFIG="$HOME/private-maas-demo/opencode.json"
```

`--openai-base-url` is mandatory when the DevWorkspace value is an in-cluster
`*.svc.cluster.local` URL. It must use the same MaaS Gateway listener and
route, not an llm-d or vLLM endpoint.

Rotate the DevSpace API key after a live demonstration that used a shared
screen, and delete the generated directory when it is no longer needed.

## VS Code With Continue

Install the Continue extension in VS Code. In its local configuration, use the
generated `continue-config.yaml` model entry. The file contains a developer API
key, so do not add it to a repository or VS Code profile that syncs settings.

Ask Continue to explain or refactor a small project. This exercises the
OpenAI-compatible MaaS Chat Completions route.

## Codex CLI

Copy the generated provider section into `~/.codex/config.toml` and source
`env.sh` before starting Codex:

```bash
mkdir -p ~/.codex
cp "$HOME/private-maas-demo/codex-config.toml" ~/.codex/config.toml
source "$HOME/private-maas-demo/env.sh"
codex
```

The generated configuration explicitly uses `wire_api = "chat"`, which matches
the PCA MaaS `/v1/chat/completions` route. It does not rely on a public OpenAI
account or API key.

## OpenCode

Use the generated configuration for the current shell rather than overwriting
an existing global OpenCode profile:

```bash
source "$HOME/private-maas-demo/env.sh"
export OPENCODE_CONFIG="$HOME/private-maas-demo/opencode.json"
opencode
```

The generated config reads `MAAS_API_KEY` from the sourced environment rather
than persisting it in an OpenCode auth file. For the full live-demo procedure,
screenshots, capacity prerequisites, and traffic diagram, see
[OpenCode MaaS demo](opencode-maas-demo.md).

## Claude Code

Claude Code uses the Anthropic Messages API, not OpenAI Chat Completions. The
PCA MaaS HTTPRoute authenticates and forwards the `/v1` path prefix, which
includes `POST /v1/messages`. Claude Code can use the MaaS host without the
`/v1` suffix. Before the demonstration, verify that the selected vLLM runtime
accepts Anthropic Messages requests, including streaming and tool calls needed
by the Claude Code workflow. Generate the Claude environment file:

```bash
scripts/bootstrap-developer-demo.sh --user dev-user1 \
  --openai-base-url https://maas.apps.example.com/v1 \
  --output "$HOME/private-maas-demo"
source "$HOME/private-maas-demo/env.sh"
source "$HOME/private-maas-demo/claude-code.env"
claude
```

If the cluster uses a separate public MaaS hostname for the Messages API, pass
it as `--anthropic-base-url https://maas.apps.example.com`. Do not route Claude
directly to vLLM; the MaaS route keeps the API key policy and metering boundary
in the demonstration.

## Presenter Sequence

1. Show the configured MaaS endpoint and model catalog with the cluster smoke
   test: `make smoke COMPONENT=ai_gateway DEV_USER=dev-user1`.
2. Open the same small repository in VS Code and ask Continue for a change.
3. Run the equivalent request in Codex and OpenCode.
4. If the Messages route is enabled, repeat it in Claude Code.
5. Show MaaS request attribution and token metrics, then explain llm-d routing:
   prefix-cache locality, KV-cache headroom, and queue depth select a vLLM pod.

## Related

- [IDE and extensions](ide-and-extensions.md)
- [Models and routing](models-and-routing.md)
- [Cluster smoke tests](../tests/cluster-smoke/README.md)
