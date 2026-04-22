set -euo pipefail

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

stderr_file=$(mktemp)
output_file=$(mktemp)

set +e

echo "Executing: flow $EXECUTABLE_INPUT $param_flags"

if [ "$CAPTURE" = "true" ]; then
    flow $EXECUTABLE_INPUT $param_flags > >(tee "$output_file") 2>"$stderr_file"
    exit_code=${PIPESTATUS[0]}
else
    flow $EXECUTABLE_INPUT $param_flags 2>"$stderr_file"
    exit_code=$?
fi

# Extract structured error code from stderr if the command failed
error_code=""
if [ $exit_code -ne 0 ] && [ -s "$stderr_file" ]; then
    error_code=$(jq -r '.error.code // empty' < "$stderr_file" 2>/dev/null || echo "")
fi

set -e

echo "exit-code=$exit_code" >> "$GITHUB_OUTPUT"

if [ -n "$error_code" ]; then
    echo "error-code=$error_code" >> "$GITHUB_OUTPUT"
fi

if [ "$CAPTURE" = "true" ] && [ -s "$output_file" ]; then
    output=$(head -c 65000 "$output_file")  # GitHub has 65KB limit
    {
        echo "output<<EOF"
        echo "$output"
        echo "EOF"
    } >> "$GITHUB_OUTPUT"
    echo "Output captured ($(wc -c < "$output_file" | xargs) bytes)"
    # Copy to working directory for artifact upload
    cp "$output_file" executable_output.txt
fi

rm -f "$stderr_file" "$output_file"

if [ "${CONTINUE_ON_ERROR:-false}" = "true" ]; then
    echo "Executable completed with exit code: $exit_code (continue-on-error enabled)"
else
    if [ $exit_code -ne 0 ]; then
        echo "::error::Executable failed with exit code $exit_code${error_code:+ ($error_code)}"
        exit $exit_code
    fi
    echo "Executable completed successfully"
fi

exit $exit_code
