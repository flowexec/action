set -euo pipefail

echo "Installing flow CLI..."

if [ "${FLOW_VERSION:-latest}" = "latest" ]; then
    echo "Installing latest version of flow..."
    curl -sSL https://raw.githubusercontent.com/jahvon/flow/main/scripts/install.sh | bash
else
    echo "Installing flow version: $FLOW_VERSION"
    curl -sSL "https://github.com/jahvon/flow/releases/download/$FLOW_VERSION/flow_linux_amd64.tar.gz" | tar -xz
    sudo mv flow /usr/local/bin/flow
fi

echo "Verifying flow installation..."
flow --version

flow config set tui false
flow config set log-mode text
flow config set timeout "${TIMEOUT:30m}"


echo "✅ Flow CLI installed successfully"