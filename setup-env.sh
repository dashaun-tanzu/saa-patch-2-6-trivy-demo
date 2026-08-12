#!/bin/bash

# Environment Setup Helper Script
# Configures the environment for the Spring Application Advisor + Trivy demo.

set -e

echo "=== Spring Application Advisor + Trivy Demo - Environment Setup ==="
echo ""

check_command() {
    command -v "$1" > /dev/null 2>&1
}

echo "Checking prerequisites..."

# `sdk` is a shell function exposed by sourcing sdkman-init.sh — `command -v sdk`
# from a clean subshell will not see it. Probe the install dir + init script instead.
SDKMAN_INIT="${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh"
if [ ! -s "$SDKMAN_INIT" ]; then
    echo "SDKMAN is not installed at ${SDKMAN_DIR:-$HOME/.sdkman}"
    echo "Please install SDKMAN first: https://sdkman.io/install"
    exit 1
fi
# shellcheck disable=SC1090
source "$SDKMAN_INIT"
if ! command -v sdk > /dev/null 2>&1; then
    echo "SDKMAN init script found but 'sdk' function not defined after sourcing"
    exit 1
fi
echo "SDKMAN is installed"

JAVA8_VERSION=$(grep '^java=8' .sdkmanrc | cut -d'=' -f2)
JAVA17_VERSION=$(grep '^java=17' .sdkmanrc | cut -d'=' -f2)

echo ""
echo "Checking Java versions..."

if ! sdk list java | grep -q "$JAVA8_VERSION"; then
    echo "Installing Java $JAVA8_VERSION..."
    sdk install java "$JAVA8_VERSION"
fi

if ! sdk list java | grep -q "$JAVA17_VERSION"; then
    echo "Installing Java $JAVA17_VERSION..."
    sdk install java "$JAVA17_VERSION"
fi

echo "Java $JAVA8_VERSION and Java $JAVA17_VERSION are installed"

echo ""
echo "Checking Trivy CLI..."

if ! check_command trivy; then
    echo "Trivy is not installed"
    if [ "$(uname)" = "Darwin" ]; then
        echo "Install with: brew install trivy"
    else
        echo "Install via: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
    fi
    exit 1
fi
echo "Trivy is installed: $(trivy --version | head -n1)"

echo ""
echo "Checking vendir..."

if ! check_command vendir; then
    echo "vendir is not installed"
    echo "Install with: brew tap carvel-dev/carvel && brew install vendir"
    exit 1
fi
echo "vendir is installed"

echo ""
echo "Checking other dependencies..."

for cmd in http jq bc git tar; do
    if ! check_command "$cmd"; then
        echo "Missing: $cmd"
        if [ "$(uname)" = "Darwin" ]; then
            echo "  brew install $cmd"
        else
            echo "  apt-get install -y $cmd"
        fi
        exit 1
    fi
done
echo "All dependencies are installed"

echo ""
echo "Checking environment variables..."

if [ -z "$ADVISOR_VERSION" ]; then
    if [ -f .envrc ]; then
        # shellcheck disable=SC1091
        source .envrc
    fi
fi

if [ -z "$ADVISOR_VERSION" ]; then
    echo "ADVISOR_VERSION is not set"
    echo "Set it in .envrc (e.g., export ADVISOR_VERSION=1.5.7)"
    exit 1
fi
echo "ADVISOR_VERSION=$ADVISOR_VERSION"

echo ""
echo "Syncing vendir dependencies..."
[ ! -d ./vendir/demo-magic ] && vendir sync

echo ""
echo "=== Environment Setup Complete ==="
echo ""
echo "To run the demo:"
echo "  ./demo.sh"
