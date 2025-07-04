set -euo pipefail

echo "Installing flow CLI..."

if [ "${FLOW_VERSION:-latest}" = "latest" ]; then
    echo "Installing latest version of flow..."
    curl -sSL https://raw.githubusercontent.com/jahvon/flow/main/scripts/install.sh | bash
else
    echo "Installing flow version: $FLOW_VERSION"

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    curl -sSL "https://github.com/jahvon/flow/releases/download/$FLOW_VERSION/flow_${OS}_${ARCH}.tar.gz" | tar -xz
    sudo mv flow /usr/local/bin/flow
fi

echo "Verifying flow installation..."
flow --version

flow config set tui false
flow config set log-mode text
flow config set timeout "${TIMEOUT:-30m}"


echo "✅ flow CLI installed successfully"