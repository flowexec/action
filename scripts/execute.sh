set -euo pipefail

echo "::group::Execution"

if [ -n "${VAULT_KEY:-}" ]; then
    export FLOW_VAULT_GHA_KEY="$VAULT_KEY"
    echo "🔑 Vault key configured"
elif [ -n "${FLOW_VAULT_GHA_KEY:-}" ]; then
    echo "🔑 Using extracted vault key from setup"
fi

set +e

if [ "${ACTIONS_STEP_DEBUG:-false}" = "true" ]; then
    echo "🚀 Executing: flow $EXECUTABLE_INPUT --log-level debug"
    FLOW_CMD="flow $EXECUTABLE_INPUT --log-level debug"
else
    echo "🚀 Executing: flow $EXECUTABLE_INPUT"
    FLOW_CMD="flow $EXECUTABLE_INPUT"
fi

if [ "${CONTINUE_ON_ERROR:-false}" = "true" ]; then
    $FLOW_CMD 2>&1 | tee executable_output.txt
    exit_code=$?
    echo "📊 Executable completed with exit code: $exit_code (continue-on-error enabled)"
else
    $FLOW_CMD 2>&1 | tee executable_output.txt
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "❌ Executable failed with exit code $exit_code"
        echo "::endgroup::"
        exit $exit_code
    fi
    echo "✅ Executable completed successfully"
fi

echo "exit-code=$exit_code" >> "$GITHUB_OUTPUT"

if [ -f executable_output.txt ]; then
    output=$(head -c 65000 executable_output.txt)  # GitHub has 65KB limit
    {
        echo "output<<EOF"
        echo "$output"
        echo "EOF"
    } >> "$GITHUB_OUTPUT"
    echo "📄 Output captured ($(wc -c < executable_output.txt) bytes)"
fi

echo "::endgroup::"

exit $exit_code
