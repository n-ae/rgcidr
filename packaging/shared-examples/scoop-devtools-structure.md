# Shared Scoop Bucket Example Structure

## Repository: `yourusername/devtools-bucket`

```
devtools-bucket/
├── bucket/
│   ├── rgcidr.json                   # IP CIDR filtering tool
│   ├── loganalyzer.json              # Log analysis utility
│   ├── configvalidator.json          # Configuration validator
│   ├── apitest.json                  # API testing tool
│   └── deployctl.json                # Deployment controller
├── .github/
│   └── workflows/
│       ├── ci.yml                    # Test all manifests
│       ├── excavator.yml             # Auto-update packages
│       ├── issue-handler.yml         # Handle common issues
│       └── pull-request.yml          # Validate PRs
├── bin/
│   ├── auto-pr.ps1                   # Auto-PR script
│   ├── checkhashes.ps1               # Hash verification
│   ├── checkurls.ps1                 # URL validation
│   └── formatjson.ps1                # JSON formatting
├── scripts/
│   ├── update-all.ps1                # Update all manifests
│   ├── test-bucket.ps1               # Test all packages
│   └── generate-manifest.ps1         # Manifest generator
├── docs/
│   ├── ADDING_PACKAGES.md            # How to add packages
│   ├── MAINTAINING.md                # Maintenance guide
│   └── CONTRIBUTING.md               # Contribution guidelines
├── .vscode/
│   ├── settings.json                 # VS Code settings
│   └── extensions.json               # Recommended extensions
├── README.md                         # Main documentation
└── LICENSE                           # Repository license
```

## Example Manifest Structure

### bucket/rgcidr.json
```json
{
    "version": "0.1.0",
    "description": "High-performance IPv4/IPv6 CIDR filtering tool",
    "homepage": "https://github.com/yourusername/rgcidr",
    "license": "MIT",
    "notes": [
        "rgcidr filters IP addresses against CIDR patterns",
        "Supports both IPv4 and IPv6 addresses",
        "Use 'rgcidr --help' for usage information"
    ],
    "architecture": {
        "64bit": {
            "url": "https://github.com/yourusername/rgcidr/releases/download/v0.1.0/rgcidr-windows-x86_64.exe",
            "hash": "sha256:abcd1234...",
            "bin": [
                ["rgcidr-windows-x86_64.exe", "rgcidr"]
            ]
        },
        "32bit": {
            "url": "https://github.com/yourusername/rgcidr/releases/download/v0.1.0/rgcidr-windows-i386.exe", 
            "hash": "sha256:efgh5678...",
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

### bucket/loganalyzer.json
```json
{
    "version": "1.2.0",
    "description": "Fast log file analysis and pattern detection",
    "homepage": "https://github.com/yourusername/loganalyzer",
    "license": "MIT",
    "depends": [
        "vcredist2022"
    ],
    "architecture": {
        "64bit": {
            "url": "https://github.com/yourusername/loganalyzer/releases/download/v1.2.0/loganalyzer-windows-x64.zip",
            "hash": "sha256:ijkl9012...",
            "extract_dir": "loganalyzer-v1.2.0",
            "bin": "loganalyzer.exe"
        }
    },
    "shortcuts": [
        ["loganalyzer.exe", "Log Analyzer"]
    ],
    "persist": [
        "config",
        "templates"
    ],
    "checkver": {
        "github": "https://github.com/yourusername/loganalyzer"
    },
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/yourusername/loganalyzer/releases/download/v$version/loganalyzer-windows-x64.zip",
                "extract_dir": "loganalyzer-v$version"
            }
        }
    }
}
```

### bucket/configvalidator.json  
```json
{
    "version": "2.0.1",
    "description": "Configuration file validator for multiple formats",
    "homepage": "https://github.com/yourusername/configvalidator", 
    "license": "Apache-2.0",
    "architecture": {
        "64bit": {
            "url": "https://github.com/yourusername/configvalidator/releases/download/v2.0.1/configvalidator_windows_amd64.tar.gz",
            "hash": "sha256:mnop3456...",
            "bin": "configvalidator.exe"
        }
    },
    "post_install": [
        "Write-Host 'ConfigValidator installed successfully!'",
        "Write-Host 'Run \"configvalidator --help\" for usage information'",
        "Write-Host 'Sample configs available at: https://github.com/yourusername/configvalidator/tree/main/examples'"
    ],
    "checkver": {
        "github": "https://github.com/yourusername/configvalidator"
    },
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/yourusername/configvalidator/releases/download/v$version/configvalidator_windows_amd64.tar.gz"
            }
        }
    }
}
```

## Installation Commands for Users

### Add the bucket and install specific tools:
```powershell
scoop bucket add devtools https://github.com/yourusername/devtools-bucket
scoop install rgcidr
scoop install loganalyzer configvalidator
```

### Install tools directly (auto-adds bucket):
```powershell
scoop install yourusername/devtools-bucket/rgcidr
scoop install yourusername/devtools-bucket/apitest
```

### Install all tools from the bucket:
```powershell
scoop bucket add devtools https://github.com/yourusername/devtools-bucket
scoop install $(scoop search devtools/ | Select-String -Pattern "devtools/" | ForEach-Object { ($_ -split '/')[1] })
```

## Automation Features

### Auto-Updates (excavator.yml)
```yaml
name: Excavator
on:
  schedule:
    - cron: '0 */4 * * *'  # Every 4 hours
  workflow_dispatch:

jobs:
  excavate:
    runs-on: windows-latest
    steps:
    - uses: actions/checkout@v4
    - name: Excavate
      uses: ScoopInstaller/Excavator@main
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        auto_pr: true
```

### Issue Handler (issue-handler.yml)
```yaml
name: Issue Handler
on:
  issues:
    types: [opened]
  issue_comment:
    types: [created]

jobs:
  issue_handler:
    runs-on: windows-latest
    steps:
    - uses: actions/checkout@v4
    - name: Handle Issues
      uses: ScoopInstaller/GithubActions@main
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
```

## Maintenance Workflow

1. **Adding a new package**:
   - Create `bucket/newpackage.json`
   - Test: `scoop install .\bucket\newpackage.json`
   - Commit and push

2. **Updating a package**:
   - Update version and hash in JSON
   - Test: `scoop uninstall newpackage && scoop install .\bucket\newpackage.json`
   - Commit changes

3. **Testing all packages**:
   ```powershell
   .\bin\checkhashes.ps1
   .\bin\checkurls.ps1
   ```

## Bucket Features

- **Automated updates** via Excavator workflows
- **Hash verification** for security
- **URL checking** for availability
- **Issue handling** for common problems
- **Pull request validation**
- **JSON formatting** and validation

This structure provides a robust, automated system for maintaining multiple Windows packages in a single Scoop bucket.