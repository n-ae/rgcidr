# Unified Repository Example: homebrew-packages

## Repository: `yourusername/homebrew-packages`

### Complete Directory Structure

```
homebrew-packages/                    # Main repository
├── homebrew/
│   ├── Formula/
│   │   ├── rgcidr.rb                 # IPv4/IPv6 CIDR filtering
│   │   ├── loganalyzer.rb            # Log analysis tool
│   │   ├── configlint.rb             # Config validation
│   │   ├── apitest.rb                # API testing utility
│   │   └── deployctl.rb              # Deployment controller
│   └── Casks/                        # Optional: GUI applications
│       ├── logviewer.rb              # GUI log viewer
│       └── config-editor.rb          # Visual config editor
├── scoop/
│   └── bucket/
│       ├── rgcidr.json               # Same tools, Windows versions
│       ├── loganalyzer.json
│       ├── configlint.json
│       ├── apitest.json
│       └── deployctl.json
├── .github/
│   └── workflows/
│       ├── test-homebrew.yml         # Test macOS/Linux packages
│       ├── test-scoop.yml            # Test Windows packages
│       ├── update-all.yml            # Update both platforms
│       ├── release-packages.yml      # Release workflow
│       └── audit.yml                 # Security and quality checks
├── scripts/
│   ├── update-all.sh                 # Cross-platform updates
│   ├── test-all.sh                   # Cross-platform testing
│   ├── homebrew/
│   │   ├── update-formulae.sh        # Update Homebrew formulae
│   │   ├── test-formulae.sh          # Test Homebrew packages
│   │   └── audit-formulae.sh         # Audit Homebrew packages
│   └── scoop/
│       ├── update-manifests.ps1      # Update Scoop manifests
│       ├── test-manifests.ps1        # Test Scoop packages
│       └── validate-manifests.ps1    # Validate JSON manifests
├── docs/
│   ├── HOMEBREW_GUIDE.md             # Homebrew-specific documentation
│   ├── SCOOP_GUIDE.md                # Scoop-specific documentation
│   ├── ADDING_PACKAGES.md            # How to add new packages
│   ├── UPDATING_PACKAGES.md          # Update procedures
│   ├── CONTRIBUTING.md               # Contribution guidelines
│   └── TROUBLESHOOTING.md            # Common issues and solutions
├── templates/
│   ├── homebrew-formula.rb.template  # Template for new Homebrew formulae
│   ├── scoop-manifest.json.template  # Template for new Scoop manifests
│   └── package-checklist.md          # Checklist for new packages
├── tools/                            # Development tools
│   ├── version-sync.py               # Ensure version consistency
│   ├── hash-generator.sh             # Generate SHA256 hashes
│   └── manifest-validator.py         # Validate manifest files
├── README.md                         # Main repository documentation
├── LICENSE                           # MIT License
└── .gitignore                        # Git ignore patterns
```

## Example Package Definitions

### Homebrew Formula (homebrew/Formula/rgcidr.rb)
```ruby
class Rgcidr < Formula
  desc "High-performance IPv4/IPv6 CIDR filtering tool"
  homepage "https://github.com/yourusername/rgcidr"
  url "https://github.com/yourusername/rgcidr/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "1234567890abcdef..."
  license "MIT"
  
  depends_on "zig" => :build
  
  def install
    system "zig", "build", "-Doptimize=ReleaseFast"
    bin.install "zig-out/bin/rgcidr"
    
    # Install shell completions
    bash_completion.install "completions/rgcidr.bash" => "rgcidr"
    fish_completion.install "completions/rgcidr.fish"
    zsh_completion.install "completions/_rgcidr"
    
    # Install man page
    man1.install "docs/rgcidr.1"
  end
  
  test do
    # Version test
    assert_match version.to_s, shell_output("#{bin}/rgcidr --version 2>&1", 1)
    
    # Functionality test
    (testpath/"test.txt").write("192.168.1.1\n10.0.0.1\n172.16.0.1\n")
    output = shell_output("#{bin}/rgcidr '192.168.0.0/16' #{testpath}/test.txt")
    assert_match "192.168.1.1", output
    refute_match "10.0.0.1", output
    
    # IPv6 test
    (testpath/"ipv6.txt").write("2001:db8::1\nfe80::1\n192.168.1.1\n")
    ipv6_output = shell_output("#{bin}/rgcidr '2001:db8::/32' #{testpath}/ipv6.txt")
    assert_match "2001:db8::1", ipv6_output
  end
end
```

### Scoop Manifest (scoop/bucket/rgcidr.json)
```json
{
    "version": "0.1.0",
    "description": "High-performance IPv4/IPv6 CIDR filtering tool",
    "homepage": "https://github.com/yourusername/rgcidr",
    "license": "MIT",
    "notes": [
        "rgcidr filters IP addresses against CIDR patterns",
        "Supports both IPv4 and IPv6 addresses",
        "Example: rgcidr '192.168.0.0/16' logfile.txt",
        "Use 'rgcidr --help' for more information"
    ],
    "architecture": {
        "64bit": {
            "url": "https://github.com/yourusername/rgcidr/releases/download/v0.1.0/rgcidr-windows-x86_64.exe",
            "hash": "sha256:1234567890abcdef...",
            "bin": [
                ["rgcidr-windows-x86_64.exe", "rgcidr"]
            ]
        },
        "32bit": {
            "url": "https://github.com/yourusername/rgcidr/releases/download/v0.1.0/rgcidr-windows-i386.exe",
            "hash": "sha256:fedcba0987654321...",
            "bin": [
                ["rgcidr-windows-i386.exe", "rgcidr"]
            ]
        }
    },
    "checkver": {
        "github": "https://github.com/yourusername/rgcidr"
    },
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/yourusername/rgcidr/releases/download/v$version/rgcidr-windows-x86_64.exe",
                "hash": {
                    "url": "https://github.com/yourusername/rgcidr/releases/download/v$version/checksums.txt",
                    "regex": "([a-fA-F0-9]{64})\\s+rgcidr-windows-x86_64.exe"
                }
            },
            "32bit": {
                "url": "https://github.com/yourusername/rgcidr/releases/download/v$version/rgcidr-windows-i386.exe",
                "hash": {
                    "url": "https://github.com/yourusername/rgcidr/releases/download/v$version/checksums.txt",
                    "regex": "([a-fA-F0-9]{64})\\s+rgcidr-windows-i386.exe"
                }
            }
        }
    }
}
```

## User Installation Commands

### Homebrew (macOS/Linux)
```bash
# Add the tap
brew tap yourusername/packages

# Install individual packages
brew install rgcidr
brew install loganalyzer configlint

# Install multiple packages at once
brew install rgcidr loganalyzer configlint apitest deployctl

# Install all packages from the tap
brew install $(brew search yourusername/packages/ | grep -v '===')

# Direct installation (auto-adds tap)
brew install yourusername/packages/rgcidr
```

### Scoop (Windows)
```powershell
# Add the bucket
scoop bucket add packages https://github.com/yourusername/homebrew-packages

# Install individual packages
scoop install rgcidr
scoop install loganalyzer configlint

# Install multiple packages at once
scoop install rgcidr loganalyzer configlint apitest deployctl

# Direct installation
scoop install yourusername/homebrew-packages/rgcidr
```

## Main README.md Content

```markdown
# Development Tools Package Repository

Cross-platform CLI tools for developers, available on both Homebrew (macOS/Linux) and Scoop (Windows).

## 🚀 Quick Installation

### macOS/Linux (Homebrew)
\`\`\`bash
brew tap yourusername/packages
brew install rgcidr loganalyzer configlint
\`\`\`

### Windows (Scoop) 
\`\`\`powershell
scoop bucket add packages https://github.com/yourusername/homebrew-packages
scoop install rgcidr loganalyzer configlint
\`\`\`

## 📦 Available Packages

| Package | Description | Platforms |
|---------|-------------|-----------|
| **rgcidr** | High-performance IPv4/IPv6 CIDR filtering | macOS, Linux, Windows |
| **loganalyzer** | Fast log file analysis and pattern detection | macOS, Linux, Windows |
| **configlint** | Configuration file validator (JSON, YAML, TOML) | macOS, Linux, Windows |
| **apitest** | RESTful API testing and validation tool | macOS, Linux, Windows |
| **deployctl** | Deployment automation controller | macOS, Linux, Windows |

## 🔄 Updates

Both package managers support automatic updates:

### Homebrew
\`\`\`bash
brew update && brew upgrade
\`\`\`

### Scoop
\`\`\`powershell
scoop update && scoop update *
\`\`\`

## 📚 Documentation

- [Homebrew Guide](docs/HOMEBREW_GUIDE.md) - macOS/Linux specific instructions
- [Scoop Guide](docs/SCOOP_GUIDE.md) - Windows specific instructions
- [Contributing](docs/CONTRIBUTING.md) - How to contribute new packages
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

## 🛠️ Development

### Adding New Packages
See [ADDING_PACKAGES.md](docs/ADDING_PACKAGES.md) for detailed instructions.

### Testing
\`\`\`bash
# Test Homebrew formulae
./scripts/homebrew/test-formulae.sh

# Test Scoop manifests (Windows)
.\scripts\scoop\test-manifests.ps1
\`\`\`

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions welcome! Please read our [Contributing Guide](docs/CONTRIBUTING.md).
```

## Automation Example

### Cross-Platform Update Script (scripts/update-all.sh)
```bash
#!/bin/bash
# Update packages across both Homebrew and Scoop

set -e

PACKAGE_NAME="$1"
NEW_VERSION="$2"

if [ -z "$PACKAGE_NAME" ] || [ -z "$NEW_VERSION" ]; then
    echo "Usage: $0 <package-name> <new-version>"
    echo "Example: $0 rgcidr 0.2.0"
    exit 1
fi

echo "Updating $PACKAGE_NAME to version $NEW_VERSION"

# Update Homebrew formula
echo "Updating Homebrew formula..."
./scripts/homebrew/update-formulae.sh "$PACKAGE_NAME" "$NEW_VERSION"

# Update Scoop manifest (requires Windows or WSL with PowerShell)
echo "Updating Scoop manifest..."
if command -v pwsh &> /dev/null; then
    pwsh -File ./scripts/scoop/update-manifests.ps1 -Package "$PACKAGE_NAME" -Version "$NEW_VERSION"
else
    echo "PowerShell not available. Please run the Scoop update manually on Windows:"
    echo "  .\scripts\scoop\update-manifests.ps1 -Package '$PACKAGE_NAME' -Version '$NEW_VERSION'"
fi

echo "✅ Update completed for $PACKAGE_NAME v$NEW_VERSION"
echo "Next steps:"
echo "1. Test both platforms"
echo "2. Commit and push changes"
echo "3. Tag release if needed"
```

This unified approach provides excellent maintainability while giving users a consistent experience across platforms.