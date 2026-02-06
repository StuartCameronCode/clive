#!/bin/bash

# Script to update clive.rb Homebrew formula with new version and SHA256 hash
# Usage: ./update_clive_sha256.sh <version>

set -e

if [ $# -eq 0 ]; then
    echo "Error: Version argument required"
    echo "Usage: $0 <version>"
    echo "Example: $0 1.0.6"
    exit 1
fi

VERSION="$1"
FORMULA_FILE="HomebrewFormula/clive.rb"
GITHUB_URL="https://github.com/StuartCameronCode/clive/releases/download/v${VERSION}/Clive-${VERSION}.zip"

echo "Calculating SHA256 for version ${VERSION}..."
SHA256=$(curl -sL "${GITHUB_URL}" | shasum -a 256 | awk '{print $1}')

if [ -z "$SHA256" ]; then
    echo "Error: Failed to calculate SHA256. Please verify the version exists."
    exit 1
fi

echo "SHA256: ${SHA256}"
echo "Updating ${FORMULA_FILE}..."

# Update version
sed -i '' "s/version \".*\"/version \"${VERSION}\"/" "${FORMULA_FILE}"

# Update URL
sed -i '' "s|url \".*\"|url \"${GITHUB_URL}\"|" "${FORMULA_FILE}"

# Update SHA256
sed -i '' "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "${FORMULA_FILE}"

echo "Successfully updated ${FORMULA_FILE} with version ${VERSION} and SHA256 ${SHA256}"

