set -euo pipefail

echo "::group::Workspace Setup"

echo "Setting up flow workspaces..."

mkdir -p "${CHECKOUT_PATH:-.flow-workspaces}"

clone_repository() {
    local repo_url="$1"
    local workspace_name="$2"
    local repo_ref="$3"
    local repo_path="$4"

    if [ -z "$repo_path" ]; then
        repo_path="${CHECKOUT_PATH:-.flow-workspaces}/$workspace_name"
    fi

    git_url="$repo_url"
    if [ -n "${CLONE_TOKEN:-}" ]; then
        if [[ "$repo_url" == *"github.com"* ]]; then
            git_url=$(echo "$repo_url" | sed "s|https://github.com/|https://x-access-token:${CLONE_TOKEN}@github.com/|")
        fi
    fi

    echo "🔄 Cloning $repo_url -> $repo_path (workspace: $workspace_name)"
    git clone \
        --depth="${CLONE_DEPTH:-1}" \
        ${repo_ref:+--branch="$repo_ref"} \
        "$git_url" \
        "$repo_path"

    echo "$repo_path"
}

register_workspace() {
    local workspace_path="$1"
    local workspace_name="$2"

    if [[ ! "$workspace_path" = /* ]]; then
        if [ "$workspace_path" = "." ]; then
            workspace_path="$(pwd)"
        else
            workspace_path="$(pwd)/$workspace_path"
        fi
    fi

    if [ "${ACTIONS_RUNNER_DEBUG:-false}" = "true" ]; then
        flow workspace create "$workspace_name" "$workspace_path" --log-level debug 2>/dev/null || true
    else
        flow workspace create "$workspace_name" "$workspace_path" 2>/dev/null || true
    fi

    echo "$workspace_name"
}

if [ -n "${WORKSPACES_INPUT:-}" ]; then
    echo "🔍 Processing workspaces configuration..."

    workspaces_input="$WORKSPACES_INPUT"

    # check if it's JSON or YAML and convert to JSON if needed
    if echo "$workspaces_input" | jq empty 2>/dev/null; then
        workspaces_json="$workspaces_input"
    else
        workspaces_json=$(echo "$workspaces_input" | yq -o json)
    fi

    if echo "$workspaces_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
        # object format: {"workspace-name": "config", ...}
        echo "$workspaces_json" | jq -r 'to_entries[] | "\(.key) \(.value)"' | while read -r name config; do
            if echo "$config" | jq -e 'type == "string"' >/dev/null 2>&1; then
                config_str=$(echo "$config" | jq -r '.')
                # check for git or local
                if [[ "$config_str" == git* ]] || [[ "$config_str" == http* ]] || [[ "$config_str" == *".git" ]]; then
                    cloned_path=$(clone_repository "$config_str" "$name" "" "")
                    register_workspace "$cloned_path" "$name"
                else
                    register_workspace "$config_str" "$name"
                fi
            else
                # object with detailed configuration
                repo_url=$(echo "$config" | jq -r '.repo // .url // empty')
                local_path=$(echo "$config" | jq -r '.path // empty')
                repo_ref=$(echo "$config" | jq -r '.ref // .branch // empty')
                clone_path=$(echo "$config" | jq -r '.clone-path // empty')

                if [ -n "$repo_url" ]; then
                    cloned_path=$(clone_repository "$repo_url" "$name" "$repo_ref" "$clone_path")
                    register_workspace "$cloned_path" "$name"
                elif [ -n "$local_path" ]; then
                    register_workspace "$local_path" "$name"
                else
                    echo "⚠️  Warning: Workspace '$name' has no repo or path specified"
                fi
            fi
        done
    else
        # array format: [{"name": "...", "repo": "..."}, ...]
        echo "$workspaces_json" | jq -r '.[] | "\(.name) \(.repo // .url // .path) \(.ref // .branch // "") \(.clone-path // "") \(.path // "")"' | \
        while read -r name source ref clone_path local_path; do
            if [[ "$source" == git* ]] || [[ "$source" == http* ]] || [[ "$source" == *".git" ]]; then
                # repository workspace
                cloned_path=$(clone_repository "$source" "$name" "$ref" "$clone_path")
                register_workspace "$cloned_path" "$name"
            elif [ -n "$local_path" ]; then
                # local workspace with separate path
                register_workspace "$local_path" "$name"
            else
                # local workspace
                register_workspace "$source" "$name"
            fi
        done
    fi
else
    if [ "${WORKSPACE_PATH:-.}" = "." ]; then
        workspace_name="${WORKSPACE_NAME:-$(basename "$PWD")}"
    else
        workspace_name="${WORKSPACE_NAME:-$(basename "${WORKSPACE_PATH}")}"
    fi
    register_workspace "${WORKSPACE_PATH:-.}" "$workspace_name"
fi

if [[ "${EXECUTABLE_INPUT:-}" == *"/"* ]]; then
    # Extract workspace from executable reference (e.g., "build backend/api:service")
    primary_workspace=$(echo "$EXECUTABLE_INPUT" | cut -d'/' -f1)
    if [ "${ACTIONS_RUNNER_DEBUG:-false}" = "true" ]; then
        flow workspace set "$primary_workspace" --log-level debug 2>/dev/null || true
    else
        flow workspace set "$primary_workspace" 2>/dev/null || true
    fi
else
    if [ "${ACTIONS_RUNNER_DEBUG:-false}" = "true" ]; then
        flow workspace set "$workspace_name" --log-level debug 2>/dev/null || true
    else
        flow workspace set "$workspace_name" 2>/dev/null || true
    fi
fi

echo "🔄 Syncing..."
if [ "${ACTIONS_RUNNER_DEBUG:-false}" = "true" ]; then
    flow sync --log-level debug
else
    flow sync
fi

echo "✅ Workspace setup completed"

echo "::endgroup::"