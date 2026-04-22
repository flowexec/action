set -euo pipefail

echo "::group::Vault Setup"

echo "Setting up flow vault and secrets..."

has_secrets() {
    local input="${SECRETS_INPUT:-}"
    [ -n "$input" ]
}

if has_secrets || [ -n "${VAULT_KEY:-}" ]; then
    echo "Setting up vault..."

    if [ -z "${VAULT_KEY:-}" ]; then
        echo "Creating vault..."
        vault_output=$(flow vault create github-actions --key-env FLOW_VAULT_GHA_KEY --output json 2>&1)

        # Extract the generated key from structured JSON output
        extracted_key=$(echo "$vault_output" | jq -r '.result.data.generatedKey // empty' 2>/dev/null || echo "")

        if [ -z "$extracted_key" ]; then
            # Fallback: try the plain-text pattern for older versions
            extracted_key=$(echo "$vault_output" | grep -o "Your vault encryption key is: .*" | cut -d':' -f2- | xargs || echo "")
        fi

        if [ -n "$extracted_key" ]; then
            export FLOW_VAULT_GHA_KEY="$extracted_key"
            echo "Generated vault key"
            echo "::add-mask::$extracted_key"
            echo "vault-key=$extracted_key" >> "$GITHUB_OUTPUT"
        else
            echo "::error::Could not extract vault key from output"
            echo "$vault_output"
            exit 1
        fi
    else
        export FLOW_VAULT_GHA_KEY="$VAULT_KEY"
        echo "Using provided vault key"
        flow vault create github-actions --key-env FLOW_VAULT_GHA_KEY --output json 2>/dev/null || true

        echo "vault-key=$VAULT_KEY" >> "$GITHUB_OUTPUT"
    fi
    flow vault switch github-actions --output json

    if has_secrets; then
        echo "Setting secrets..."

        secrets_input="$SECRETS_INPUT"
        trimmed="${secrets_input#"${secrets_input%%[![:space:]]*}"}"

        if [[ "$trimmed" == "{"* ]]; then
            # JSON object format (backwards compatible)
            echo "$secrets_input" | jq -r 'to_entries[] | "\(.key)\n\(.value)"' | while read -r key && read -r value; do
                echo "  Setting secret: $key"
                flow secret set "$key" "$value" --output json
            done
        else
            # KEY=VALUE format (one per line)
            while IFS= read -r line; do
                line=$(echo "$line" | xargs) # trim whitespace
                [ -z "$line" ] && continue
                key="${line%%=*}"
                value="${line#*=}"
                if [ "$key" = "$line" ]; then
                    echo "::warning::Skipping invalid secret line (missing '='): $key"
                    continue
                fi
                echo "  Setting secret: $key"
                flow secret set "$key" "$value" --output json
            done <<< "$secrets_input"
        fi
    fi

    echo "Vault setup completed"
else
    echo "No secrets to configure"
fi

echo "::endgroup::"
