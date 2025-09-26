# Unified Repository Strategy: Homebrew + Scoop

This guide explains how to use a single repository to manage packages for both Homebrew (macOS/Linux) and Scoop (Windows).

## Why Use a Unified Repository?

### ✅ **Advantages**
- **Single source of truth** for all package definitions
- **Simplified maintenance** - update both platforms at once
- **Consistent versioning** across all platforms
- **Unified CI/CD** workflows
- **Better discoverability** - users find all your tools in one place
- **Reduced repository sprawl** - easier to manage permissions and access

### ⚠️ **Considerations**
- **Platform-specific requirements** need separate manifest formats
- **Different testing approaches** for each platform
- **Repository naming** must satisfy both naming conventions
- **Larger repository size** (but minimal impact)

## Repository Structure

### Recommended Layout

```
yourusername/packages/                 # Main repository
├── homebrew/
│   ├── Formula/
│   │   ├── rgcidr.rb                  # Homebrew formula
│   │   ├── logparser.rb
│   │   └── configlint.rb
│   └── Casks/                         # Optional: GUI apps
│       └── myapp.rb
├── scoop/
│   └── bucket/
│       ├── rgcidr.json                # Scoop manifest
│       ├── logparser.json
│       └── configlint.json
├── .github/
│   └── workflows/
│       ├── test-homebrew.yml          # Test formulae
│       ├── test-scoop.yml             # Test manifests
│       ├── update-packages.yml        # Auto-update both
│       └── release-packages.yml       # Deploy on release
├── scripts/
│   ├── update-all.sh                  # Update both platforms
│   ├── test-all.sh                    # Test both platforms
│   ├── homebrew/
│   │   ├── update-formulae.sh         # Homebrew-specific updates
│   │   └── test-formulae.sh           # Homebrew testing
│   └── scoop/
│       ├── update-manifests.ps1       # Scoop-specific updates
│       └── test-manifests.ps1         # Scoop testing
├── docs/
│   ├── HOMEBREW_SETUP.md              # Homebrew tap setup
│   ├── SCOOP_SETUP.md                 # Scoop bucket setup
│   ├── CONTRIBUTING.md                # Contribution guidelines
│   └── PACKAGE_GUIDELINES.md          # Adding new packages
├── templates/                         # Templates for new packages
│   ├── homebrew-formula.rb.template
│   └── scoop-manifest.json.template
├── README.md                          # Main documentation
└── LICENSE
```

## Repository Naming Convention

Use a name that works for both platforms:

### ✅ **Good Names** (Homebrew compatible):
- `homebrew-packages` (Homebrew prefers `homebrew-` prefix)
- `homebrew-devtools`
- `homebrew-cli-suite`

### ✅ **Alternative Approach**:
Use descriptive names without prefixes:
- `packages` 
- `devtools-packages`
- `cli-tools`

**Note**: For Homebrew, the `homebrew-` prefix enables the short form `brew tap username/packages` instead of requiring the full URL.

## Setup Instructions

### 1. Create the Repository

```bash
# Create repository (use homebrew- prefix for convenience)
gh repo create yourusername/homebrew-packages --public

# Clone and set up structure
git clone https://github.com/yourusername/homebrew-packages
cd homebrew-packages

# Create directory structure
mkdir -p homebrew/Formula homebrew/Casks
mkdir -p scoop/bucket
mkdir -p .github/workflows scripts/homebrew scripts/scoop
mkdir -p docs templates
```

### 2. Add Package Manifests

#### Homebrew Formula (`homebrew/Formula/rgcidr.rb`):
```ruby
class Rgcidr < Formula
  desc "High-performance IPv4/IPv6 CIDR filtering tool"
  homepage "https://github.com/yourusername/rgcidr"
  url "https://github.com/yourusername/rgcidr/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "abcd1234..."
  license "MIT"
  
  depends_on "zig" => :build
  
  def install
    system "zig", "build", "-Doptimize=ReleaseFast"
    bin.install "zig-out/bin/rgcidr"
  end
  
  test do
    assert_match version.to_s, shell_output("#{bin}/rgcidr --version")
  end
end
```

#### Scoop Manifest (`scoop/bucket/rgcidr.json`):
```json
{
    "version": "0.1.0",
    "description": "High-performance IPv4/IPv6 CIDR filtering tool",
    "homepage": "https://github.com/yourusername/rgcidr",
    "license": "MIT",
    "architecture": {
        "64bit": {
            "url": "https://github.com/yourusername/rgcidr/releases/download/v0.1.0/rgcidr-windows-x86_64.exe",
            "hash": "abcd1234...",
            "bin": [["rgcidr-windows-x86_64.exe", "rgcidr"]]
        }
    },
    "checkver": {"github": "https://github.com/yourusername/rgcidr"},
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/yourusername/rgcidr/releases/download/v$version/rgcidr-windows-x86_64.exe"
            }
        }
    }
}
```

### 3. Create User Documentation

#### Main README.md:
```markdown
# Package Repository

Cross-platform packages for Homebrew (macOS/Linux) and Scoop (Windows).

## Installation

### macOS/Linux (Homebrew)
\`\`\`bash
brew tap yourusername/packages
brew install rgcidr logparser
\`\`\`

### Windows (Scoop)
\`\`\`powershell
scoop bucket add packages https://github.com/yourusername/homebrew-packages
scoop install rgcidr logparser
\`\`\`

## Available Packages
- **rgcidr** - High-performance CIDR filtering
- **logparser** - Fast log analysis
- **configlint** - Configuration validation

## Contributing
See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.
```

### 4. Set Up Automation

#### GitHub Workflow (`.github/workflows/update-packages.yml`):
```yaml
name: Update Packages
on:
  repository_dispatch:
    types: [update-packages]
  workflow_dispatch:
    inputs:
      package:
        description: 'Package to update (or "all")'
        required: true
        default: 'all'
      version:
        description: 'New version'
        required: true

jobs:
  update-homebrew:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v4
    - name: Update Homebrew formulae
      run: |
        ./scripts/homebrew/update-formulae.sh ${{ github.event.inputs.package }} ${{ github.event.inputs.version }}
    - name: Test formulae
      run: |
        ./scripts/homebrew/test-formulae.sh
    - name: Commit changes
      run: |
        git config --local user.email "action@github.com"
        git config --local user.name "GitHub Action"
        git add homebrew/
        git commit -m "Update Homebrew formulae: ${{ github.event.inputs.package }} v${{ github.event.inputs.version }}" || exit 0

  update-scoop:
    runs-on: windows-latest
    steps:
    - uses: actions/checkout@v4
    - name: Update Scoop manifests
      run: |
        .\scripts\scoop\update-manifests.ps1 -Package "${{ github.event.inputs.package }}" -Version "${{ github.event.inputs.version }}"
    - name: Test manifests
      run: |
        .\scripts\scoop\test-manifests.ps1
    - name: Commit changes
      run: |
        git config --local user.email "action@github.com"
        git config --local user.name "GitHub Action"
        git add scoop/
        git commit -m "Update Scoop manifests: ${{ github.event.inputs.package }} v${{ github.event.inputs.version }}" || exit 0

  finalize:
    needs: [update-homebrew, update-scoop]
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Pull all changes
      run: git pull origin main
    - name: Push final changes
      run: git push origin main
```

## User Installation Experience

### Cross-Platform Instructions

Users get a consistent experience across platforms:

#### For Homebrew Users:
```bash
# Add the tap
brew tap yourusername/packages

# Install tools
brew install rgcidr                    # Install single tool
brew install rgcidr logparser          # Install multiple tools
brew install $(brew search yourusername/packages/ | grep -v '===')  # Install all tools
```

#### For Scoop Users:
```powershell
# Add the bucket  
scoop bucket add packages https://github.com/yourusername/homebrew-packages

# Install tools
scoop install rgcidr                   # Install single tool
scoop install rgcidr logparser         # Install multiple tools
```

### Direct Installation (No Tap/Bucket Required):
```bash
# Homebrew - auto-adds tap
brew install yourusername/packages/rgcidr

# Scoop - direct from URL
scoop install yourusername/homebrew-packages/rgcidr
```

## Maintenance Workflow

### Adding a New Package

1. **Create manifests for both platforms**:
   ```bash
   # Use templates
   cp templates/homebrew-formula.rb.template homebrew/Formula/newpackage.rb
   cp templates/scoop-manifest.json.template scoop/bucket/newpackage.json
   
   # Edit manifests with package details
   ```

2. **Test both platforms**:
   ```bash
   # Test Homebrew formula
   brew install --build-from-source ./homebrew/Formula/newpackage.rb
   
   # Test Scoop manifest (on Windows)
   scoop install .\scoop\bucket\newpackage.json
   ```

3. **Commit and deploy**:
   ```bash
   git add homebrew/Formula/newpackage.rb scoop/bucket/newpackage.json
   git commit -m "Add newpackage v1.0.0"
   git push origin main
   ```

### Updating Packages

Use the automated workflow:
```bash
# Trigger update via GitHub CLI
gh workflow run update-packages.yml -f package=rgcidr -f version=0.2.0

# Or manually via scripts
./scripts/update-all.sh rgcidr 0.2.0
```

## Best Practices

### ✅ **Do:**
- Keep manifest formats synchronized
- Use consistent versioning across platforms
- Test on both platforms before releasing
- Automate updates when possible
- Document platform-specific requirements
- Use semantic versioning

### ❌ **Don't:**
- Mix different versions between platforms
- Forget to update SHA256 hashes
- Skip testing on target platforms
- Use platform-specific features without documenting
- Hardcode paths or assumptions

## Migration from Separate Repositories

If you already have separate repositories:

1. **Create unified repository** with proper structure
2. **Copy existing manifests** to appropriate directories
3. **Set up automation** and testing
4. **Update documentation** with new installation instructions
5. **Add deprecation notices** to old repositories
6. **Redirect users** to unified repository

## Troubleshooting

### Common Issues:
- **Homebrew naming conflicts**: Use `brew search` to check names
- **Scoop hash mismatches**: Always verify SHA256 hashes
- **Platform testing**: Use GitHub Actions for cross-platform testing
- **Version synchronization**: Use automation to maintain consistency

This unified approach provides the best balance of maintainability and user experience across platforms!