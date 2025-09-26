# Publishing rgcidr to Package Managers

This guide explains how to publish rgcidr to Scoop (Windows) and Homebrew (macOS/Linux) package managers.

## Prerequisites

Before publishing to package managers, ensure you have:

1. **GitHub Release**: Created with proper versioning (e.g., v0.1.0)
2. **Binary Artifacts**: Built for all target platforms
3. **Checksums**: SHA256 hashes for all release artifacts
4. **License**: Proper license file (MIT)

## Scoop (Windows Package Manager)

### Option 1: Create Your Own Bucket

You can create either individual buckets for each package or shared buckets for multiple packages.

#### Individual Bucket (Recommended for single packages)

#### Step 1: Create a Scoop Bucket Repository

1. Create a new GitHub repository named `homebrew-rgcidr` or `scoop-bucket`
2. Use the [Scoop Bucket Template](https://github.com/ScoopInstaller/BucketTemplate) for automatic CI/CD

#### Step 2: Add the Manifest

Copy `packaging/scoop/rgcidr.json` to your bucket repository:

```json
{
    "version": "0.1.0",
    "description": "A high-performance Zig library and CLI tool for filtering IPv4 and IPv6 addresses against CIDR patterns",
    "homepage": "https://github.com/yourusername/rgcidr",
    "license": "MIT",
    "architecture": {
        "64bit": {
            "url": "https://github.com/yourusername/rgcidr/releases/download/v0.1.0/rgcidr-windows-x86_64.exe",
            "hash": "SHA256_HASH_FROM_RELEASE",
            "bin": [
                ["rgcidr-windows-x86_64.exe", "rgcidr"]
            ]
        }
    }
}
```

#### Step 3: Update Manifest

1. **Replace placeholders**:
   - `yourusername` → your GitHub username
   - `SHA256_HASH_FROM_RELEASE` → actual SHA256 hash of the Windows binary

2. **Get SHA256 hash**:
   ```bash
   # Download the release binary and get hash
   curl -L -o rgcidr.exe https://github.com/yourusername/rgcidr/releases/download/v0.1.0/rgcidr-windows-x86_64.exe
   sha256sum rgcidr.exe
   ```

#### Step 4: Publish and Share

1. Commit and push the manifest to your bucket repository
2. Users can install with:
   ```powershell
   scoop bucket add rgcidr https://github.com/yourusername/scoop-bucket
   scoop install rgcidr
   ```

#### Shared Bucket (Recommended for multiple packages)

If you have multiple CLI tools or want to create a suite of related packages:

1. **Create repository**: `yourusername/devtools-bucket`
2. **Use Bucket Template**: Use [ScoopInstaller/BucketTemplate](https://github.com/ScoopInstaller/BucketTemplate)
3. **Add multiple manifests**: Place each `.json` file in `bucket/` directory
4. **Users install with**:
   ```powershell
   scoop bucket add devtools https://github.com/yourusername/devtools-bucket
   scoop install rgcidr logparser configlint  # Install multiple tools
   ```

See [SHARED_PACKAGE_REPOSITORIES.md](SHARED_PACKAGE_REPOSITORIES.md) for detailed examples.

### Option 2: Submit to Official Scoop Buckets

For broader distribution, submit a PR to:
- [ScoopInstaller/Main](https://github.com/ScoopInstaller/Main) - for core utilities
- [ScoopInstaller/Extras](https://github.com/ScoopInstaller/Extras) - for additional tools

## Homebrew (macOS/Linux Package Manager)

### Option 1: Create Your Own Tap

You can create either individual taps for each package or shared taps for multiple packages.

#### Individual Tap (Recommended for single packages)

#### Step 1: Create a Homebrew Tap Repository

1. Create a new GitHub repository named `homebrew-rgcidr`
2. The `homebrew-` prefix is mandatory for taps

#### Step 2: Generate Formula

```bash
# Create the tap structure
brew tap-new yourusername/homebrew-rgcidr

# Generate initial formula
brew create --set-name rgcidr \
  'https://github.com/yourusername/rgcidr/archive/v0.1.0.tar.gz' \
  --tap yourusername/homebrew-rgcidr
```

#### Step 3: Customize Formula

Copy and customize `packaging/homebrew/rgcidr.rb`:

```ruby
class Rgcidr < Formula
  desc "High-performance Zig library and CLI tool for filtering IPv4 and IPv6 addresses against CIDR patterns"
  homepage "https://github.com/yourusername/rgcidr"
  url "https://github.com/yourusername/rgcidr/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "SHA256_HASH_FROM_RELEASE"
  license "MIT"
  
  depends_on "zig" => :build

  def install
    system "zig", "build", "-Doptimize=ReleaseFast"
    bin.install "zig-out/bin/rgcidr"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/rgcidr --version 2>&1", 1)
    
    (testpath/"test.txt").write("192.168.1.1\n10.0.0.1\n")
    output = shell_output("#{bin}/rgcidr '192.168.0.0/16' #{testpath}/test.txt")
    assert_match "192.168.1.1", output
  end
end
```

#### Step 4: Update Formula

1. **Replace placeholders**:
   - `yourusername` → your GitHub username
   - `SHA256_HASH_FROM_RELEASE` → actual SHA256 hash of source tarball

2. **Get SHA256 hash**:
   ```bash
   # Download source tarball and get hash
   curl -L -o rgcidr.tar.gz https://github.com/yourusername/rgcidr/archive/refs/tags/v0.1.0.tar.gz
   sha256sum rgcidr.tar.gz
   ```

#### Step 5: Test Formula

```bash
# Test installation
brew install --build-from-source yourusername/rgcidr/rgcidr

# Run audit
brew audit --strict --new --online yourusername/rgcidr/rgcidr

# Test functionality
rgcidr --version
```

#### Step 6: Publish Tap

1. Commit the formula to your `homebrew-rgcidr` repository
2. Users can install with:
   ```bash
   brew tap yourusername/rgcidr
   brew install rgcidr
   ```

#### Shared Tap (Recommended for multiple packages)

If you have multiple CLI tools or want to create a suite of related packages:

1. **Create repository**: `yourusername/homebrew-devtools` 
2. **Generate tap**: `brew tap-new yourusername/homebrew-devtools`
3. **Add multiple formulae**: Place each `.rb` file in `Formula/` directory
4. **Users install with**:
   ```bash
   brew tap yourusername/devtools
   brew install rgcidr logparser configlint  # Install multiple tools
   ```

See [SHARED_PACKAGE_REPOSITORIES.md](SHARED_PACKAGE_REPOSITORIES.md) for detailed examples.

### Option 2: Submit to Homebrew Core

For inclusion in the main Homebrew repository:

1. Check [Acceptable Formulae](https://docs.brew.sh/Acceptable-Formulae) criteria
2. Submit PR to [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core)
3. Follow [contribution guidelines](https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request)

## Automation and Maintenance

### GitHub Actions Integration

Add workflow steps to automatically update package managers on release:

```yaml
# .github/workflows/release.yml
- name: Update Scoop Manifest
  run: |
    # Update Scoop manifest with new version and hash
    # Commit to bucket repository

- name: Update Homebrew Formula  
  run: |
    # Update Homebrew formula with new version and hash
    # Commit to tap repository
```

### Version Management

Both package managers support automatic updates:

- **Scoop**: Uses `autoupdate` and `checkver` in manifest
- **Homebrew**: Can use automated PR tools like [BrewTestBot](https://github.com/BrewTestBot)

## Distribution Strategy

### Recommended Approach

1. **Start with your own repositories** (tap/bucket) for immediate availability
2. **Build user base** and gather feedback  
3. **Submit to official repositories** once established
4. **Automate updates** using CI/CD pipelines

### Repository Structure

```
rgcidr/
├── packaging/
│   ├── scoop/
│   │   └── rgcidr.json
│   └── homebrew/
│       └── rgcidr.rb
└── docs/
    └── PACKAGE_PUBLISHING.md
```

## Maintenance Checklist

For each new release:

- [ ] Update version numbers in manifests/formulae
- [ ] Update SHA256 hashes for new binaries
- [ ] Test installation on target platforms
- [ ] Update package manager repositories
- [ ] Verify users can install the new version

## Support and Troubleshooting

### Common Issues

1. **Hash Mismatch**: Always verify SHA256 hashes match release artifacts
2. **Build Failures**: Test formula/manifest on clean systems
3. **Version Conflicts**: Use semantic versioning consistently
4. **Platform Issues**: Test on multiple OS versions

### Getting Help

- **Scoop**: [ScoopInstaller/Scoop Discussions](https://github.com/ScoopInstaller/Scoop/discussions)
- **Homebrew**: [Homebrew Discussions](https://github.com/Homebrew/discussions/discussions)

## References

- [Scoop Wiki - App Manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Adding Software to Homebrew](https://docs.brew.sh/Adding-Software-to-Homebrew)