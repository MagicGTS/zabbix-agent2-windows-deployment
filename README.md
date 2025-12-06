# Zabbix Agent 2 - Automated Deployment Script

**Automated installation and configuration management for Zabbix Agent 2 on Windows**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Version](https://img.shields.io/badge/Version-1.1.0-brightgreen.svg)](https://github.com/MagicGTS/zabbix-agent2-windows-deployment)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)

## 📋 Overview

This PowerShell script automates the deployment and update management of Zabbix Agent 2 across Windows environments. It provides intelligent version checking, centralized configuration management, and secure PSK deployment from a network share.

### Key Features

- ✅ **Intelligent Version Detection** - Automatically extracts version from MSI filename and detects installed version via executable
- ✅ **Smart Update Logic** - Differentiates between full reinstall (version change) and configuration update (config/PSK change)
- ✅ **PSK Key Change Detection** - Automatically detects and updates PSK keys without reinstalling the agent
- ✅ **Centralized Management** - Deploy from network share with single configuration source
- ✅ **Secure PSK Deployment** - Automated PSK key file creation with proper ACL permissions
- ✅ **Auto-Registration Support** - Pre-configured for Zabbix auto-registration with hostname detection
- ✅ **Service Management** - Handles service stop/start with health verification
- ✅ **Detailed Logging** - Comprehensive step-by-step execution logging
- ✅ **Error Handling** - Robust error handling with cleanup in finally block
- ✅ **Version Information** - Built-in version command for script management

---

## 🚀 Quick Start

### Prerequisites

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or higher
- Administrator privileges
- Network share with installation files

### Check Script Version

```powershell
.\Install-ZabbixAgent2.ps1 -Version
```

### Basic Usage

```powershell
.\Install-ZabbixAgent2.ps1 `
    -NetworkShare "\\fileserver\zabbix" `
    -Server "zbx-proxy.contoso.com" `
    -ServerActive "zbx-proxy.contoso.com" `
    -PSKKey "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" `
    -MSIFileName "zabbix_agent2-7.4.5-windows-amd64-openssl.msi" `
    -ConfigVersion "1.0"
```

---

## 📂 Repository Structure

```
.
├── Install-ZabbixAgent2.ps1    # Main installation script (v1.1.0)
├── zabbix_agent2.conf          # Example agent configuration
└── README.md                   # This file
```

---

## 📖 How It Works

### Version Detection System

The script uses a **three-tier version checking system**:

1. **Agent Version** - Extracted from:
   - MSI filename pattern: `zabbix_agent2-X.Y.Z-windows-amd64-openssl.msi`
   - Installed executable: `zabbix_agent2.exe -V` output

2. **Config Version** - Read from configuration file header:
   ```properties
   # Zabbix Agent 2 Configuration
   # Config Version: 1.0
   ```

3. **PSK Key** - Read from `psk.key` file (first line)
   - Compared case-insensitively (hex strings)
   - Triggers service restart if changed

### Update Logic

The script uses **intelligent update logic**:

- **Full Reinstall** - Triggered when:
  - Agent version changes
  - Agent not installed
  - Force flag used

- **Configuration Update** - Triggered when:
  - Config version changes
  - PSK key changes
  - Only stops service → updates files → starts service

### Installation Flow

```
Start
  ↓
Mount Network Share as PSDrive
  ↓
Extract Version from MSI Filename
  ↓
Check Installed Agent Version
  ↓
Check Config Version
  ↓
Check PSK Key
  ↓
Version Changed? → Yes → Full Reinstall → End
  ↓ No
Config/PSK Changed? → Yes → Update Config/PSK → Restart Service → End
  ↓ No
All Up to Date → End
```

### Execution Steps

**Full Reinstall Mode (Agent Version Changed):**
1. **Mount Network Share** - Creates temporary PSDrive for reliable network access
2. **Version Extraction** - Parses MSI filename to get target version
3. **Update Check** - Detects agent version mismatch
4. **Stop Service** - Stops Zabbix Agent 2 service
5. **Installation** - Executes MSI with silent parameters
6. **Configuration** - Copies config file from network share
7. **PSK Deployment** - Creates PSK key file with secure ACL permissions
8. **Service Start** - Starts agent service and verifies status
9. **Health Check** - Scans log file for errors
10. **Cleanup** - Removes temporary PSDrive

**Configuration Update Mode (Config/PSK Changed):**
1. **Mount Network Share** - Creates temporary PSDrive
2. **Version Check** - Agent version matches, config/PSK differs
3. **Stop Service** - Stops Zabbix Agent 2 service
4. **Update Config** - Copies updated configuration file
5. **Update PSK** - Updates PSK key file
6. **Service Start** - Restarts agent service
7. **Health Check** - Verifies service is running
8. **Cleanup** - Removes temporary PSDrive

---

## 🔧 Parameters

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `NetworkShare` | ✅ Yes | UNC path to network share | `\\fileserver\zabbix` |
| `Server` | ✅ Yes | Zabbix Server/Proxy for passive checks | `zbx-proxy.contoso.com` |
| `ServerActive` | ✅ Yes | Zabbix Server/Proxy for active checks | `zbx-proxy.contoso.com` |
| `PSKKey` | ✅ Yes | 256-bit PSK in hex (64 chars) | `0123...cdef` |
| `MSIFileName` | ✅ Yes | MSI filename with version | `zabbix_agent2-7.4.5-windows-amd64-openssl.msi` |
| `ConfigVersion` | ✅ Yes | Config version identifier | `1.0` |
| `Force` | ❌ No | Force reinstallation | `-Force` |
| `Version` | ❌ No | Display script version | `-Version` |

---

## 📦 Network Share Setup

### Required Files Structure

```
\\fileserver\zabbix\
├── zabbix_agent2-7.4.5-windows-amd64-openssl.msi
└── zabbix_agent2.conf
```

### Configuration File Format

Add version header to your `zabbix_agent2.conf`:

```properties
# Zabbix Agent 2 Configuration
# Config Version: 1.0
# Last Updated: 2025-12-06 10:30:00

# ... rest of configuration ...
Server=zbx-proxy.contoso.com
ServerActive=zbx-proxy.contoso.com
HostnameItem=system.hostname
# ... etc ...
```

**Important:** The script copies the config file **as-is** without modifications. Manage versions manually in the file header.

---

## 🔐 Security Features

### PSK Key File Protection

The script creates `psk.key` with restrictive ACL:

- **SYSTEM**: Full Control
- **Administrators**: Full Control  
- **NT AUTHORITY\NetworkService**: Read (for Zabbix service)
- **Inheritance**: Disabled
- **Other Users**: No Access

### MSI Installation Parameters

```powershell
msiexec.exe /i "zabbix_agent2.msi" /qn `
    DONOTSTART=1 `
    ENABLEPATH=1 `
    TARGETDIR="C:\Program Files\Zabbix Agent 2" `
    SERVER=zbx-proxy.contoso.com `
    SERVERACTIVE=zbx-proxy.contoso.com
```

---

## 🌐 Auto-Registration Configuration

### Example `zabbix_agent2.conf` Snippet

```properties
# Auto-detect hostname from Windows
HostnameItem=system.hostname

# Metadata for auto-registration and discovery rules
# Customize: "Windows Server" or "Windows Workstation"
HostMetadata=Windows Workstation

# TLS PSK Encryption
TLSConnect=psk
TLSAccept=psk
TLSPSKIdentity=autoregistration
TLSPSKFile=C:\Program Files\Zabbix Agent 2\psk.key

# Persistent buffer for offline data retention
EnablePersistentBuffer=1
PersistentBufferPeriod=1h
PersistentBufferFile=C:\Program Files\Zabbix Agent 2\PersistentBuffer.sqlite3
```

---

## 🔄 Update Management

### Updating Agent Version

1. Upload new MSI to network share: `zabbix_agent2-7.4.6-windows-amd64-openssl.msi`
2. Run script with new filename:
   ```powershell
   .\Install-ZabbixAgent2.ps1 ... -MSIFileName "zabbix_agent2-7.4.6-windows-amd64-openssl.msi"
   ```
3. Script detects version mismatch and updates automatically

### Updating Configuration

1. Modify `zabbix_agent2.conf` on network share
2. Increment version header:
   ```properties
   # Config Version: 1.1
   ```
3. Run script with updated `ConfigVersion`:
   ```powershell
   .\Install-ZabbixAgent2.ps1 ... -ConfigVersion "1.1"
   ```

### Force Reinstallation

```powershell
.\Install-ZabbixAgent2.ps1 ... -Force
```

---

## 📊 Execution Output Example

```
[2025-12-06 10:15:30] === Zabbix Agent 2 Installation Script ===
[2025-12-06 10:15:30] MSI Filename: zabbix_agent2-7.4.5-windows-amd64-openssl.msi
[2025-12-06 10:15:30] Config Version: 1.0
[2025-12-06 10:15:30] Network Share: \\fileserver\zabbix\

[2025-12-06 10:15:30] Step 1: Mounting network share...
[2025-12-06 10:15:31] Network share mounted as ZabbixTemp:
[2025-12-06 10:15:31] Step 2: Extracting version from MSI filename...
[2025-12-06 10:15:31] Target Agent Version: 7.4.5
[2025-12-06 10:15:31] Step 3: Checking if installation/update is required...
[2025-12-06 10:15:32] Agent version mismatch (current: 7.4.4, target: 7.4.5) - update required
[2025-12-06 10:15:32] Step 4: Locating MSI installer...
[2025-12-06 10:15:32] Found MSI: ZabbixTemp:\zabbix_agent2-7.4.5-windows-amd64-openssl.msi
...
[2025-12-06 10:15:47] === Installation completed successfully ===
[2025-12-06 10:15:47] Agent Version: 7.4.5
[2025-12-06 10:15:47] Config Version: 1.0
```

---

## 🎯 Use Cases

### 1. Mass Deployment via Group Policy

Deploy to multiple workstations using GPO startup script:

**Group Policy Settings:**
- **Computer Configuration** → **Windows Settings** → **Scripts** → **Startup**
- **Script:** `\\fileserver\zabbix\Install-ZabbixAgent2.ps1`

### 2. SCCM/MECM Package

Create SCCM application package with detection method based on version checking.

### 3. Scheduled Task for Updates

Create scheduled task to check for updates daily at 3 AM.

### 4. Manual Remote Deployment

Deploy to single remote computer via `Invoke-Command`.

---

## 🛠️ Troubleshooting

### Common Issues

**Issue:** "Network share path does not exist"
```
Solution: Verify UNC path is accessible from administrative context
Test: Test-Path "\\fileserver\zabbix"
```

**Issue:** "Cannot extract version from filename"
```
Solution: Ensure MSI filename matches pattern: zabbix_agent2-X.Y.Z-windows-amd64-openssl.msi
```

**Issue:** "Service failed to start"
```
Solution: Check log file at: C:\Program Files\Zabbix Agent 2\zabbix_agent2.log
Common causes: Invalid server address, firewall blocking, incorrect PSK
```

---

## 📚 Additional Documentation

- **[Zabbix Official Documentation](https://www.zabbix.com/documentation/current/manual/appendix/config/zabbix_agent2)** - Agent 2 configuration reference

---

## 📝 Changelog

### Version 1.0.0 (2025-12-06)
- Initial release
- Automated installation from network share
- Version detection from MSI filename and executable
- Config version tracking
- PSK key deployment with ACL security
- Service management with health checks
- PSDrive mounting for network access
- Comprehensive error handling and logging

---

**⭐ If you find this useful, please star this repository!**


