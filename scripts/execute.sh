set -euo pipefail

echo "::group::Execution"

# Vault key setup
if [ -n "${VAULT_KEY:-}" ]; then
    export FLOW_VAULT_GHA_KEY="$VAULT_KEY"
elif [ -n "${FLOW_VAULT_GHA_KEY:-}" ]; then
    echo "Using extracted vault key from setup"
fi

# Build --param flags from PARAMS_INPUT
param_flags=""
if [ -n "${PARAMS_INPUT:-}" ]; then
    # Support both newline-separated and comma-separated KEY=VALUE pairs
    params=$(echo "$PARAMS_INPUT" | tr ',' '\n')
    while IFS= read -r param; do
        param=$(echo "$param" | xargs) # trim whitespace
        if [ -n "$param" ]; then
            param_flags="$param_flags --param $param"
        fi
    done <<< "$params"
fi

# Export user-provided environment variables
if [ -n "${ENV_INPUT:-}" ]; then
    while IFS= read -r line; do
        line=$(echo "$line" | xargs) # trim whitespace
        if [ -n "$line" ] && [[ "$line" == *"="* ]]; then
            export "$line"
        fi
    done <<< "$ENV_INPUT"
fi

set +e

echo "Executing: flow $EXECUTABLE_INPUT $param_flags"

if [ "$CAPTURE" = "true" ]; then
    flow $EXECUTABLE_INPUT $param_flags > >(tee executable_output.txt) 2>executable_stderr.txt
    exit_code=${PIPESTATUS[0]}
else
    flow $EXECUTABLE_INPUT $param_flags 2>executable_stderr.txt
    exit_code=$?
fi

# Extract structured error code from stderr if the command failed
error_code=""
if [ $exit_code -ne 0 ] && [ -f executable_stderr.txt ]; then
    error_code=$(cat executable_stderr.txt | jq -r '.error.code // empty' 2>/dev/null || echo "")
fi

set -e

echo "exit-code=$exit_code" >> "$GITHUB_OUTPUT"

if [ -n "$error_code" ]; then
    echo "error-code=$error_code" >> "$GITHUB_OUTPUT"
fi

if [ -f executable_output.txt ]; then
    output=$(head -c 65000 executable_output.txt)  # GitHub has 65KB limit
    {
        echo "output<<EOF"
        echo "$output"
        echo "EOF"
    } >> "$GITHUB_OUTPUT"
    echo "Output captured ($(wc -c < executable_output.txt | xargs) bytes)"
fi

if [ "${CONTINUE_ON_ERROR:-false}" = "true" ]; then
    echo "Executable completed with exit code: $exit_code (continue-on-error enabled)"
else
    if [ $exit_code -ne 0 ]; then
        echo "::error::Executable failed with exit code $exit_code${error_code:+ ($error_code)}"
        echo "::endgroup::"
        exit $exit_code
    fi
    echo "Executable completed successfully"
fi

echo "::endgroup::"

exit $exit_code
