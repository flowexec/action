set -euo pipefail

echo "::group::CLI Setup"

echo "Installing flow CLI..."

if [ "${FLOW_VERSION:-latest}" = "latest" ]; then
    echo "Installing latest version of flow..."
    curl -sSL https://raw.githubusercontent.com/jahvon/flow/main/scripts/install.sh | bash
elif [ "${FLOW_VERSION}" = "main" ]; then
    echo "Building flow from main branch..."

    if ! command -v go &> /dev/null; then
        echo "Go required for main builds"
        exit 1
    fi

    git clone https://github.com/jahvon/flow.git /tmp/flow
    cd /tmp/flow
    go build -o flow .
    sudo mv flow /usr/local/bin/flow
    cd -
    rm -rf /tmp/flow
else
    echo "Installing flow version: $FLOW_VERSION"
    export VERSION="$FLOW_VERSION"
    curl -sSL https://raw.githubusercontent.com/jahvon/flow/main/scripts/install.sh | bash
fi

echo "Verifying flow installation..."
flow --version

flow config set tui false
flow config set log-mode text
flow config set timeout "${TIMEOUT:-30m}"


echo "✅ flow CLI installed successfully"

echo "::endgroup::"