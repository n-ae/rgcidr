#!/bin/bash
# Create a GitHub release for rgcidr

set -e

# Get current version from build.zig.zon
VERSION=$(grep -E '^\s*\.version\s*=' build.zig.zon | sed 's/.*"\([^"]*\)".*/\1/')

if [ -z "$VERSION" ]; then
    echo "❌ Could not extract version from build.zig.zon"
    exit 1
fi

echo "🚀 Creating release for rgcidr v$VERSION"

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ Not in a git repository"
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo "❌ You have uncommitted changes. Please commit them first."
    exit 1
fi

# Check if tag already exists
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo "❌ Tag v$VERSION already exists"
    exit 1
fi

# Push current changes to ensure CI has latest code
echo "📤 Pushing changes to GitHub..."
git push origin main

# Wait a moment for GitHub to process
sleep 2

echo "✅ Creating release v$VERSION"
echo ""
echo "📋 Release steps:"
echo "1. The release workflow will automatically trigger"
echo "2. Binaries will be built for all platforms"
echo "3. Checksums will be generated"
echo "4. Release will be published"
echo ""
echo "🔗 Release URL: https://github.com/n-ae/rgcidr/releases/tag/v$VERSION"
echo ""
echo "⏳ You can monitor the release progress at:"
echo "   https://github.com/n-ae/rgcidr/actions"
echo ""
echo "📦 Once complete, you can update the package repository with:"
echo "   cd ~/dev/packages"
echo "   ./scripts/update-all.sh rgcidr $VERSION"