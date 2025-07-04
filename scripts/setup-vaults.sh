set -euo pipefail

echo "Setting up flow vault and secrets..."

if [ "${SECRETS_INPUT:-{}}" != "{}" ]; then
    echo "🔐 Setting up vault..."

    if [ -z "${VAULT_KEY:-}" ]; then
        echo "🔑 Creating vault..."
        vault_output=$(flow vault create github-actions --key-env FLOW_VAULT_GHA_KEY 2>&1)

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
        flow vault create github-actions --key-env FLOW_VAULT_GHA_KEY 2>/dev/null || true

        echo "vault-key=$VAULT_KEY" >> "$GITHUB_OUTPUT"
    fi
    flow vault switch github-actions

    echo "📝 Setting secrets..."
    echo "$SECRETS_INPUT" | jq -r 'to_entries[] | "\(.key)=\(.value)"' | while IFS='=' read -r key value; do
        echo "Setting secret: $key"
        echo "$value" | flow secret set "$key"
    done

    echo "✅ Vault setup completed"
else
    echo "ℹ️  No secrets to configure"
fi