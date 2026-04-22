set -euo pipefail

echo "Setting up flow workspaces..."

# Configure git credential helper so flow's internal clone picks up the token
setup_git_auth() {
    if [ -z "${CLONE_TOKEN:-}" ]; then
        return
    fi
    echo "Configuring git credentials..."
    git config --global credential.helper store
    # Pre-seed the credential store for github.com
    echo "https://x-access-token:${CLONE_TOKEN}@github.com" >> "$HOME/.git-credentials"
}

# Check if a path is absolute (Unix / or Windows C:/ drive letter)
is_absolute() {
    case "$1" in
        /*|[a-zA-Z]:*) return 0 ;;
        *)             return 1 ;;
    esac
}

# Return the current directory as a native path.
# On Windows Git Bash, pwd returns /d/a/... but native Windows binaries
# need D:/a/... — pwd -W gives the Windows-native form.
native_pwd() {
    if pwd -W &>/dev/null; then
        pwd -W
    else
        pwd
    fi
}

# Register a local directory as a workspace
register_local_workspace() {
    local workspace_path="$1"
    local workspace_name="$2"

    if ! is_absolute "$workspace_path"; then
        if [ "$workspace_path" = "." ]; then
            workspace_path="$(native_pwd)"
        else
            workspace_path="$(native_pwd)/$workspace_path"
        fi
    fi

    flow workspace add "$workspace_name" "$workspace_path" --set --output json 2>/dev/null || true
}

# Register a git URL as a workspace (flow handles the clone)
register_git_workspace() {
    local workspace_name="$1"
    local repo_url="$2"
    local repo_ref="$3"
    local depth="${CLONE_DEPTH:-1}"

    add_args="$workspace_name $repo_url --set --output json"
    if [ -n "$repo_ref" ]; then
        add_args="$add_args --branch $repo_ref"
    fi
    if [ "$depth" -gt 0 ] 2>/dev/null; then
        add_args="$add_args --depth $depth"
    fi

    echo "Adding git workspace: $workspace_name ($repo_url)"
    flow workspace add $add_args
}

# Determine if a string looks like a git URL
is_git_url() {
    case "$1" in
        git*|http*|ssh*) return 0 ;;
        *.git)           return 0 ;;
        *)               return 1 ;;
    esac
}

# Convert YAML to JSON if needed
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

setup_git_auth

if [ -n "${WORKSPACES_INPUT:-}" ]; then
    echo "Processing workspaces configuration..."

    workspaces_json=$(to_json "$WORKSPACES_INPUT")

    if echo "$workspaces_json" | jq -e 'type == "object"' >/dev/null 2>&1; then
        # object format: {"workspace-name": "config", ...}
        echo "$workspaces_json" | jq -r 'to_entries[] | "\(.key) \(.value)"' | while read -r name config; do
            if echo "$config" | jq -e 'type == "string"' >/dev/null 2>&1; then
                config_str=$(echo "$config" | jq -r '.')
                if is_git_url "$config_str"; then
                    register_git_workspace "$name" "$config_str" ""
                else
                    register_local_workspace "$config_str" "$name"
                fi
            else
                repo_url=$(echo "$config" | jq -r '.repo // .url // empty')
                local_path=$(echo "$config" | jq -r '.path // empty')
                repo_ref=$(echo "$config" | jq -r '.ref // .branch // empty')

                if [ -n "$repo_url" ]; then
                    register_git_workspace "$name" "$repo_url" "$repo_ref"
                elif [ -n "$local_path" ]; then
                    register_local_workspace "$local_path" "$name"
                else
                    echo "Warning: Workspace '$name' has no repo or path specified"
                fi
            fi
        done
    else
        # array format: [{"name": "...", "repo": "..."}, ...]
        echo "$workspaces_json" | jq -c '.[]' | while read -r entry; do
            name=$(echo "$entry" | jq -r '.name')
            repo_url=$(echo "$entry" | jq -r '.repo // .url // empty')
            local_path=$(echo "$entry" | jq -r '.path // empty')
            repo_ref=$(echo "$entry" | jq -r '.ref // .branch // empty')

            if [ -n "$repo_url" ]; then
                register_git_workspace "$name" "$repo_url" "$repo_ref"
            elif [ -n "$local_path" ]; then
                register_local_workspace "$local_path" "$name"
            fi
        done
    fi

    # Switch to the primary workspace based on executable reference
    if [[ "${EXECUTABLE_INPUT:-}" == *"/"* ]]; then
        ref_part="${EXECUTABLE_INPUT##* }"
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
    register_local_workspace "${WORKSPACE_PATH:-.}" "$workspace_name"
fi

echo "Syncing executables..."
flow sync --output json

echo "Workspace setup completed"
