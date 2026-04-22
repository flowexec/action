set -euo pipefail

echo "::group::Workspace Setup"

echo "Setting up flow workspaces..."

mkdir -p "${CHECKOUT_PATH:-.flow-workspaces}"

# Check if a path is absolute (Unix / or Windows C:/ drive letter)
is_absolute() {
    case "$1" in
        /*|[a-zA-Z]:*) return 0 ;;
        *)             return 1 ;;
    esac
}

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
        git_url="${repo_url/https:\/\/github.com\//https://x-access-token:${CLONE_TOKEN}@github.com/}"
    fi

    echo "Cloning $repo_url -> $repo_path (workspace: $workspace_name)"
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

    if ! is_absolute "$workspace_path"; then
        if [ "$workspace_path" = "." ]; then
            workspace_path="$(pwd)"
        else
            workspace_path="$(pwd)/$workspace_path"
        fi
    fi

    flow workspace add "$workspace_name" "$workspace_path" --set --output json 2>/dev/null || true

    echo "$workspace_name"
}

# Convert YAML to JSON if needed. Prefers jq (already JSON) then yq, with a
# clear error if neither can parse it.
to_json() {
    local input="$1"
    if echo "$input" | jq empty 2>/dev/null; then
        echo "$input"
    elif command -v yq &>/dev/null; then
        echo "$input" | yq -o json
    else
        echo "::error::Workspace input is YAML but yq is not installed. Use JSON format or install yq."
        exit 1
    fi
}

if [ -n "${WORKSPACES_INPUT:-}" ]; then
    echo "Processing workspaces configuration..."

    workspaces_json=$(to_json "$WORKSPACES_INPUT")

    # Track the last registered workspace for switching later
    last_workspace=""

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
                    echo "Warning: Workspace '$name' has no repo or path specified"
                fi
            fi
            last_workspace="$name"
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
            last_workspace="$name"
        done
    fi

    # Switch to the primary workspace based on executable reference
    if [[ "${EXECUTABLE_INPUT:-}" == *"/"* ]]; then
        # Extract workspace from reference like "VERB workspace/ns:name"
        ref_part="${EXECUTABLE_INPUT##* }"  # last token (the ref)
        if [[ "$ref_part" == *"/"* ]]; then
            primary_workspace="${ref_part%%/*}"
        else
            primary_workspace="${EXECUTABLE_INPUT%%/*}"
        fi
        flow workspace switch "$primary_workspace" --output json 2>/dev/null || true
    fi
else
    if [ "${WORKSPACE_PATH:-.}" = "." ]; then
        workspace_name="${WORKSPACE_NAME:-$(basename "$PWD")}"
    else
        workspace_name="${WORKSPACE_NAME:-$(basename "${WORKSPACE_PATH}")}"
    fi
    register_workspace "${WORKSPACE_PATH:-.}" "$workspace_name"
fi

echo "Syncing executables..."
sync_args="--output json"
if [ "${SYNC_GIT:-false}" = "true" ]; then
    sync_args="$sync_args --git"
fi
flow sync $sync_args

echo "Workspace setup completed"

echo "::endgroup::"
