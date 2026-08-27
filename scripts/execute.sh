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

# Surface stderr. It was previously captured only to mine an error code and then
# discarded, so anything flow wrote there - notably the structured error envelope
# under --output json - never reached the log at all.
error_code=""
error_message=""
if [ -s "$stderr_file" ]; then
    if [ $exit_code -ne 0 ]; then
        error_code=$(jq -r '.error.code // empty' < "$stderr_file" 2>/dev/null || echo "")
        error_message=$(jq -r '.error.message // empty' < "$stderr_file" 2>/dev/null || echo "")
    fi
    cat "$stderr_file" >&2
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

# Write a step summary so the outcome is visible on the run page itself. flow
# collapses a multi-task run's output into a log group, so without this a reader
# has to expand the log just to learn whether the step passed.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    if [ $exit_code -eq 0 ]; then
        printf '### ✅ `flow %s`\n\n' "$EXECUTABLE_INPUT" >> "$GITHUB_STEP_SUMMARY"
    else
        {
            printf '### ❌ `flow %s`\n\n' "$EXECUTABLE_INPUT"
            printf 'Exit code `%s`' "$exit_code"
            [ -n "$error_code" ] && printf ' · `%s`' "$error_code"
            printf '\n'
            if [ -n "$error_message" ]; then
                printf '\n```\n%s\n```\n' "$error_message"
            fi
        } >> "$GITHUB_STEP_SUMMARY"
    fi
fi

if [ "${CONTINUE_ON_ERROR:-false}" = "true" ]; then
    echo "Executable completed with exit code: $exit_code (continue-on-error enabled)"
else
    if [ $exit_code -ne 0 ]; then
        # Annotations render on the run page and in the PR, where a collapsed log
        # group does not. Carry the message, not just the exit code.
        annotation="flow $EXECUTABLE_INPUT failed with exit code $exit_code${error_code:+ ($error_code)}"
        [ -n "$error_message" ] && annotation="$annotation: $error_message"
        # A literal newline would end the workflow command early.
        annotation=${annotation//$'\n'/ }
        echo "::error::$annotation"
        exit $exit_code
    fi
    echo "Executable completed successfully"
fi

exit $exit_code
