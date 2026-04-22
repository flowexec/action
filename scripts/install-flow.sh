set -euo pipefail

detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)                     echo "unix" ;;
    esac
}

RUNNER_OS_TYPE=$(detect_os)

# Ensure $HOME/bin is on PATH for Windows installs
if [ "$RUNNER_OS_TYPE" = "windows" ] && [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    export PATH="$HOME/bin:$PATH"
    echo "$HOME/bin" >> "$GITHUB_PATH"
fi

if [ "${CACHE_HIT:-}" = "true" ] && command -v flow &>/dev/null; then
    echo "Using cached flow binary"
else
    echo "Installing flow CLI..."

    if [ "${FLOW_VERSION:-latest}" = "latest" ]; then
        echo "Installing latest version of flow..."
        curl -sSL https://raw.githubusercontent.com/flowexec/flow/main/scripts/install.sh | bash
    elif [ "${FLOW_VERSION}" = "main" ]; then
        echo "Building flow from main branch..."

        if ! command -v go &> /dev/null; then
            echo "Go required for main builds"
            exit 1
        fi

        build_dir=$(mktemp -d)
        git clone https://github.com/flowexec/flow.git "$build_dir"
        cd "$build_dir"

        if [ "$RUNNER_OS_TYPE" = "windows" ]; then
            go build -o flow.exe .
            install_dir="$HOME/bin"
            mkdir -p "$install_dir"
            mv flow.exe "$install_dir/flow.exe"
        else
            go build -o flow .
            sudo mv flow /usr/local/bin/flow
        fi

        cd -
        rm -rf "$build_dir"
    else
        echo "Installing flow version: $FLOW_VERSION"
        export VERSION="$FLOW_VERSION"
        curl -sSL https://raw.githubusercontent.com/flowexec/flow/main/scripts/install.sh | bash
    fi
fi

flow config set interactive false
flow config set tui false
flow config set log-mode text
flow config set timeout "${TIMEOUT:-30m}"

echo "Verifying flow installation..."
flow --version

echo "flow CLI installed successfully"
