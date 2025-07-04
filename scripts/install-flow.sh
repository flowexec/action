set -euo pipefail

echo "::group::Setup"

echo "Installing flow CLI..."

if [ "${FLOW_VERSION:-latest}" = "latest" ]; then
    echo "Installing latest version of flow..."
else
    echo "Installing flow version: $FLOW_VERSION"
    export VERSION="$FLOW_VERSION"
fi

curl -sSL https://raw.githubusercontent.com/jahvon/flow/main/scripts/install.sh | bash

echo "Verifying flow installation..."
flow --version

flow config set tui false
flow config set log-mode text
flow config set timeout "${TIMEOUT:-30m}"


echo "✅ flow CLI installed successfully"

echo "::endgroup::"