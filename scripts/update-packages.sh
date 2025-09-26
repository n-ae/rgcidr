#!/bin/bash
# Update package manager manifests/formulae with new release information

set -e

# Configuration
VERSION=${1:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}
GITHUB_REPO="yourusername/rgcidr"  # Update this with your actual repo
SCOOP_BUCKET_REPO="yourusername/scoop-bucket"  # Update this
HOMEBREW_TAP_REPO="yourusername/homebrew-rgcidr"  # Update this

if [ -z "$VERSION" ]; then
    echo "Error: No version specified and no git tags found"
    echo "Usage: $0 [version]"
    echo "Example: $0 0.1.0"
    exit 1
fi

echo "Updating package manifests for version $VERSION"

# Function to get SHA256 hash from a URL
get_sha256() {
    local url="$1"
    local temp_file=$(mktemp)
    echo "Downloading $url to get SHA256..."
    curl -L -s "$url" -o "$temp_file"
    local hash=$(sha256sum "$temp_file" | cut -d' ' -f1)
    rm "$temp_file"
    echo "$hash"
}

# Update Scoop manifest
update_scoop_manifest() {
    echo "Updating Scoop manifest..."
    
    local windows_url="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/rgcidr-windows-x86_64.exe"
    local windows_hash=$(get_sha256 "$windows_url")
    
    # Create updated manifest
    cat > packaging/scoop/rgcidr.json << EOF
{
    "version": "$VERSION",
    "description": "A high-performance Zig library and CLI tool for filtering IPv4 and IPv6 addresses against CIDR patterns",
    "homepage": "https://github.com/$GITHUB_REPO",
    "license": "MIT",
    "architecture": {
        "64bit": {
            "url": "$windows_url",
            "hash": "$windows_hash",
            "bin": [
                ["rgcidr-windows-x86_64.exe", "rgcidr"]
            ]
        }
    },
    "checkver": {
        "github": "https://github.com/$GITHUB_REPO"
    },
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/$GITHUB_REPO/releases/download/v\$version/rgcidr-windows-x86_64.exe",
                "hash": {
                    "url": "https://github.com/$GITHUB_REPO/releases/download/v\$version/checksums.txt",
                    "regex": "([a-fA-F0-9]{64})\\\\s+rgcidr-windows-x86_64.exe"
                }
            }
        }
    }
}
EOF
    
    echo "✓ Scoop manifest updated with hash: $windows_hash"
}

# Update Homebrew formula
update_homebrew_formula() {
    echo "Updating Homebrew formula..."
    
    local source_url="https://github.com/$GITHUB_REPO/archive/refs/tags/v$VERSION.tar.gz"
    local source_hash=$(get_sha256 "$source_url")
    
    # Create updated formula
    cat > packaging/homebrew/rgcidr.rb << EOF
class Rgcidr < Formula
  desc "High-performance Zig library and CLI tool for filtering IPv4 and IPv6 addresses against CIDR patterns"
  homepage "https://github.com/$GITHUB_REPO"
  url "$source_url"
  sha256 "$source_hash"
  license "MIT"
  
  depends_on "zig" => :build

  def install
    system "zig", "build", "-Doptimize=ReleaseFast"
    bin.install "zig-out/bin/rgcidr"
  end

  test do
    # Test basic functionality
    assert_match version.to_s, shell_output("#{bin}/rgcidr --version 2>&1", 1)
    
    # Test IP filtering functionality
    (testpath/"test.txt").write("192.168.1.1\\n10.0.0.1\\n172.16.0.1\\n")
    output = shell_output("#{bin}/rgcidr '192.168.0.0/16' #{testpath}/test.txt")
    assert_match "192.168.1.1", output
    refute_match "10.0.0.1", output
  end
end
EOF
    
    echo "✓ Homebrew formula updated with hash: $source_hash"
}

# Main execution
echo "Starting package manifest update for rgcidr v$VERSION"
echo "GitHub Repository: $GITHUB_REPO"
echo

# Create packaging directory if it doesn't exist
mkdir -p packaging/scoop packaging/homebrew

# Update manifests
update_scoop_manifest
update_homebrew_formula

echo
echo "Package manifests updated successfully!"
echo
echo "Next steps:"
echo "1. Review the updated files:"
echo "   - packaging/scoop/rgcidr.json"
echo "   - packaging/homebrew/rgcidr.rb"
echo
echo "2. Commit and push to your bucket/tap repositories:"
echo "   - Scoop bucket: $SCOOP_BUCKET_REPO"
echo "   - Homebrew tap: $HOMEBREW_TAP_REPO"
echo
echo "3. Test installation:"
echo "   - Scoop: scoop install rgcidr"
echo "   - Homebrew: brew install rgcidr"
echo
echo "For detailed instructions, see docs/PACKAGE_PUBLISHING.md"