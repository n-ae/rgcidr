# Shared Package Repositories for Multiple Projects

Both Scoop and Homebrew support **shared repositories** that can contain multiple packages, making it ideal for developers with multiple CLI tools or organizations with a suite of applications.

## Shared Homebrew Tap (Multiple Formulae)

### Repository Structure

```
homebrew-devtools/                    # Repository: username/homebrew-devtools
├── Formula/
│   ├── rgcidr.rb                     # Package 1: IP CIDR filtering
│   ├── logparser.rb                  # Package 2: Log parsing tool  
│   ├── configlint.rb                 # Package 3: Config file linter
│   └── deploy-cli.rb                 # Package 4: Deployment tool
├── Casks/                            # Optional: GUI applications
│   └── myapp.rb
├── .github/
│   └── workflows/
│       └── tests.yml                 # CI/CD for all formulae
└── README.md
```

### Creating a Shared Tap

```bash
# Create the shared tap repository
brew tap-new yourusername/homebrew-devtools

# Add multiple formulae to the Formula/ directory
# Each .rb file represents one package
```

### User Installation

Users can:

1. **Install specific packages directly**:
   ```bash
   brew install yourusername/devtools/rgcidr
   brew install yourusername/devtools/logparser
   ```

2. **Add the tap and install**:
   ```bash
   brew tap yourusername/devtools
   brew install rgcidr logparser configlint
   ```

3. **Install all packages at once**:
   ```bash
   brew tap yourusername/devtools
   brew install $(brew search yourusername/devtools/ | grep -v '==>')
   ```

### Example Shared Formula

Each package gets its own `.rb` file in the `Formula/` directory:

```ruby
# Formula/rgcidr.rb
class Rgcidr < Formula
  desc "High-performance CIDR filtering tool"
  homepage "https://github.com/yourusername/rgcidr"
  url "https://github.com/yourusername/rgcidr/archive/v0.1.0.tar.gz"
  sha256 "..."
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

# Formula/logparser.rb  
class Logparser < Formula
  desc "Fast log file parsing utility"
  homepage "https://github.com/yourusername/logparser"
  # ... rest of formula
end
```

## Shared Scoop Bucket (Multiple Manifests)

### Repository Structure

```
devtools-bucket/                      # Repository: username/devtools-bucket
├── bucket/
│   ├── rgcidr.json                   # Package 1: IP CIDR filtering
│   ├── logparser.json                # Package 2: Log parsing tool
│   ├── configlint.json               # Package 3: Config file linter
│   └── deploy-cli.json               # Package 4: Deployment tool
├── .github/
│   └── workflows/
│       ├── ci.yml                    # Automated testing
│       ├── excavator.yml             # Auto-updates
│       └── issue-handler.yml         # Issue automation
├── bin/                              # Scripts for automation
└── README.md
```

### Creating a Shared Bucket

1. **Use the Scoop Bucket Template**:
   - Go to [ScoopInstaller/BucketTemplate](https://github.com/ScoopInstaller/BucketTemplate)
   - Click "Use this template" 
   - Name it `devtools-bucket` (no "scoop-" prefix needed)

2. **Add JSON manifests** for each package in the `bucket/` directory

### User Installation

Users can:

1. **Add the bucket and install specific packages**:
   ```powershell
   scoop bucket add devtools https://github.com/yourusername/devtools-bucket
   scoop install rgcidr
   scoop install logparser configlint
   ```

2. **Install packages directly by URL**:
   ```powershell
   scoop install yourusername/devtools-bucket/rgcidr
   ```

### Example Shared Manifests

Each package gets its own `.json` file in the `bucket/` directory:

```json
// bucket/rgcidr.json
{
    "version": "0.1.0",
    "description": "High-performance CIDR filtering tool",
    "homepage": "https://github.com/yourusername/rgcidr",
    "license": "MIT",
    "architecture": {
        "64bit": {
            "url": "https://github.com/yourusername/rgcidr/releases/download/v0.1.0/rgcidr-windows-x86_64.exe",
            "hash": "...",
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

// bucket/logparser.json
{
    "version": "1.2.0", 
    "description": "Fast log file parsing utility",
    "homepage": "https://github.com/yourusername/logparser",
    // ... rest of manifest
}
```

## Comparison: Individual vs Shared Repositories

### Individual Repositories
```
homebrew-rgcidr/           scoop-rgcidr/
├── Formula/               ├── bucket/
│   └── rgcidr.rb         │   └── rgcidr.json
└── README.md             └── README.md

homebrew-logparser/        scoop-logparser/ 
├── Formula/               ├── bucket/
│   └── logparser.rb      │   └── logparser.json
└── README.md             └── README.md
```

### Shared Repository
```
homebrew-devtools/         devtools-bucket/
├── Formula/               ├── bucket/
│   ├── rgcidr.rb         │   ├── rgcidr.json
│   ├── logparser.rb      │   ├── logparser.json
│   └── configlint.rb     │   └── configlint.json
└── README.md             └── README.md
```

## Advantages of Shared Repositories

### ✅ **Benefits**

1. **Easier Management**: Single repository to maintain
2. **Unified CI/CD**: One set of workflows for all packages
3. **Consistent Branding**: All tools under one "brand" 
4. **Reduced Overhead**: Fewer repositories to manage
5. **User Convenience**: One tap/bucket for all your tools
6. **Better Discovery**: Users find related tools together

### ⚠️ **Considerations**

1. **Release Coupling**: Updates to one package affect the entire repository
2. **Size Growth**: Repository grows with each package added
3. **Permission Management**: All contributors have access to all packages
4. **Issue Tracking**: Issues for different packages in same tracker

## Recommended Strategy

### For Individual Developers
- **Start with shared repositories** for your personal CLI tools
- **Use individual repositories** for unrelated or large projects

### For Organizations  
- **Use shared repositories** for tool suites (e.g., "devops-tools", "data-tools")
- **Use individual repositories** for major standalone products

### Example Repository Names

**Shared Homebrew Taps**:
- `homebrew-devtools` (development utilities)
- `homebrew-sysadmin` (system administration tools)
- `homebrew-security` (security tools)
- `homebrew-cli` (general CLI utilities)

**Shared Scoop Buckets**:
- `devtools-bucket`
- `sysadmin-bucket` 
- `security-bucket`
- `cli-bucket`

## Migration Path

If you start with individual repositories, you can migrate to shared:

1. **Create the shared repository**
2. **Copy existing formulae/manifests** 
3. **Update installation instructions**
4. **Deprecate individual repositories** (with migration notice)
5. **Redirect users** to the shared repository

## Automation for Shared Repositories

Both platforms support automation for shared repositories:

### Homebrew
- **BrewTestBot**: Automated testing and updates
- **Custom workflows**: Test all formulae on changes
- **Version bumping**: Update multiple packages

### Scoop  
- **Excavator workflows**: Auto-update all manifests
- **CI testing**: Validate all manifests on changes
- **Issue handlers**: Automated issue resolution

This approach gives you the flexibility to organize packages logically while minimizing maintenance overhead!