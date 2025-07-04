set -euo pipefail

echo "::group::Vault Setup"

echo "Setting up flow vault and secrets..."

if [ "${SECRETS_INPUT:-{}}" != "{}" ]; then
    echo "🔐 Setting up vault..."

    if [ -z "${VAULT_KEY:-}" ]; then
        echo "🔑 Creating vault..."
        if [ "${ACTIONS_STEP_DEBUG:-false}" = "true" ]; then
            vault_output=$(flow vault create github-actions --key-env FLOW_VAULT_GHA_KEY --log-level debug 2>&1)
        else
            vault_output=$(flow vault create github-actions --key-env FLOW_VAULT_GHA_KEY 2>&1)
        fi

        # extract from pattern: "Your vault encryption key is: <key>"
        extracted_key=$(echo "$vault_output" | grep -o "Your vault encryption key is: .*" | cut -d':' -f2- | xargs || echo "")

        if [ -n "$extracted_key" ]; then
            export FLOW_VAULT_GHA_KEY="$extracted_key"
            echo "Generated vault key"
            echo "::add-mask::$extracted_key"
            echo "vault-key=$extracted_key" >> "$GITHUB_OUTPUT"
        else
            echo "⚠️  Could not extract vault key from output:"
            echo "$vault_output"
        fi
    else
        export FLOW_VAULT_GHA_KEY="$VAULT_KEY"
        echo "Using provided vault key"
        if [ "${ACTIONS_STEP_DEBUG:-false}" = "true" ]; then
            flow vault create github-actions --key-env FLOW_VAULT_GHA_KEY --log-level debug 2>/dev/null || true
        else
            flow vault create github-actions --key-env FLOW_VAULT_GHA_KEY 2>/dev/null || true
        fi

        echo "vault-key=$VAULT_KEY" >> "$GITHUB_OUTPUT"
    fi
    if [ "${ACTIONS_STEP_DEBUG:-false}" = "true" ]; then
        flow vault switch github-actions --log-level debug
    else
        flow vault switch github-actions
    fi

    echo "📝 Setting secrets..."
    echo "$SECRETS_INPUT" | jq -r 'to_entries[] | "\(.key)=\(.value)"' | while IFS='=' read -r key value; do
        echo "Setting secret: $key"
        if [ "${ACTIONS_STEP_DEBUG:-false}" = "true" ]; then
            echo "$value" | flow secret set "$key" --log-level debug
        else
            echo "$value" | flow secret set "$key"
        fi
    done

    echo "✅ Vault setup completed"
else
    echo "ℹ️  No secrets to configure"
fi

echo "::endgroup::"