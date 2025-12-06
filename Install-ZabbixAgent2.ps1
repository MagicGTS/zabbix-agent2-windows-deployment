#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs or updates Zabbix Agent 2 with configuration from network share.

.DESCRIPTION
    This script automates installation and configuration of Zabbix Agent 2:
    - Checks current installed version
    - Installs/updates agent from network share
    - Deploys configuration file
    - Creates PSK key file
    - Starts the service

.PARAMETER NetworkShare
    UNC path to network share containing installation files and config.
    Example: \\server\share\zabbix

.PARAMETER Server
    Zabbix Server or Proxy address for passive checks.

.PARAMETER ServerActive
    Zabbix Server or Proxy address for active checks.

.PARAMETER PSKKey
    Pre-shared key content (256-bit hex string, 64 characters).

.PARAMETER TargetVersion
    Expected Zabbix Agent 2 version (e.g., "7.4.5").

.PARAMETER ConfigVersion
    Configuration file version for tracking updates.

.PARAMETER Force
    Force reinstallation even if versions match.

.EXAMPLE
    .\Install-ZabbixAgent2.ps1 -NetworkShare "\\fileserver\zabbix" -Server "zbx-poll.contoso.com" -ServerActive "zbx-push.contoso.com" -PSKKey "0123456789abcdef..." -MSIFileName "zabbix_agent2-7.4.5-windows-amd64-openssl.msi" -ConfigVersion "1.0"

.EXAMPLE
    .\Install-ZabbixAgent2.ps1 -NetworkShare "\\fileserver\zabbix" -Server "zbx-poll.contoso.com" -ServerActive "zbx-push.contoso.com" -PSKKey "0123456789abcdef..." -MSIFileName "zabbix_agent2-7.4.5-windows-amd64-openssl.msi" -ConfigVersion "1.0" -Force

.NOTES
    Author: GitHub Copilot
    Version: 1.0
    Requires: PowerShell 5.1+, Administrator privileges
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true, HelpMessage="UNC path to network share with installation files")]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Container)) {
            throw "Network share path does not exist: $_"
        }
        $true
    })]
    [string]$NetworkShare,

    [Parameter(Mandatory=$true, HelpMessage="Zabbix Server/Proxy address for passive checks")]
    [ValidateNotNullOrEmpty()]
    [string]$Server,

    [Parameter(Mandatory=$true, HelpMessage="Zabbix Server/Proxy address for active checks")]
    [ValidateNotNullOrEmpty()]
    [string]$ServerActive,

    [Parameter(Mandatory=$true, HelpMessage="PSK key content (64 hex characters)")]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$PSKKey,

    [Parameter(Mandatory=$true, HelpMessage="MSI filename (e.g., zabbix_agent2-7.4.5-windows-amd64-openssl.msi)")]
    [ValidatePattern('^zabbix_agent2-\d+\.\d+\.\d+-windows-amd64-openssl\.msi$')]
    [string]$MSIFileName,

    [Parameter(Mandatory=$true, HelpMessage="Configuration version for tracking")]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigVersion,

    [Parameter(Mandatory=$false, HelpMessage="Force reinstallation")]
    [switch]$Force
)

# Configuration
$script:InstallPath = "C:\Program Files\Zabbix Agent 2"
$script:ConfigFile = Join-Path $InstallPath "zabbix_agent2.conf"
$script:PSKFile = Join-Path $InstallPath "psk.key"
$script:ServiceName = "Zabbix Agent 2"
$script:ExecutablePath = Join-Path $InstallPath "zabbix_agent2.exe"

#region Helper Functions

function Get-VersionFromMSIFileName {
    <#
    .SYNOPSIS
        Extracts version number from MSI filename.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FileName
    )
    
    if ($FileName -match 'zabbix_agent2-(\d+\.\d+\.\d+)-windows-amd64-openssl\.msi') {
        return $matches[1]
    }
    
    throw "Cannot extract version from filename: $FileName"
}

function Get-InstalledAgentVersion {
    <#
    .SYNOPSIS
        Gets installed agent version by executing zabbix_agent2.exe -V.
    #>
    try {
        if (-not (Test-Path $script:ExecutablePath)) {
            Write-Log "Executable not found - agent not installed" -Level Warning
            return $null
        }

        $output = & $script:ExecutablePath -V 2>&1 | Select-Object -First 1
        
        # Parse output: "zabbix_agent2 Win64 (Zabbix) 7.4.5"
        if ($output -match 'zabbix_agent2.*?\s+(\d+\.\d+\.\d+)') {
            return $matches[1]
        }
        
        Write-Log "Cannot parse version from executable output: $output" -Level Warning
        return $null
    }
    catch {
        Write-Log "Error getting installed agent version: $_" -Level Error
        return $null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'White' }
    }
    
    if ([string]::IsNullOrEmpty($Message)) {
        Write-Host ""
    } else {
        Write-Host "[$timestamp] $Message" -ForegroundColor $color
    }
}

function Get-InstalledConfigVersion {
    <#
    .SYNOPSIS
        Gets config version from config file.
    #>
    try {
        if (-not (Test-Path $script:ConfigFile)) {
            Write-Log "Configuration file not found - agent not installed" -Level Warning
            return $null
        }

        $content = Get-Content $script:ConfigFile -Raw -ErrorAction Stop
        
        # Extract config version from header
        # Expected format:
        # # Zabbix Agent 2 Configuration
        # # Config Version: 1.0
        
        if ($content -match '#\s*Config Version:\s*(.+)') {
            return $matches[1].Trim()
        }
        
        Write-Log "Config version not found in configuration file" -Level Warning
        return $null
    }
    catch {
        Write-Log "Error reading configuration file: $_" -Level Error
        return $null
    }
}

function Test-UpdateRequired {
    <#
    .SYNOPSIS
        Checks if installation or update is required.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetAgentVersion,
        
        [Parameter(Mandatory=$true)]
        [string]$TargetConfigVersion
    )

    if ($Force) {
        Write-Log "Force flag set - reinstallation required" -Level Warning
        return $true
    }

    # Get installed agent version from executable
    $installedAgentVersion = Get-InstalledAgentVersion
    
    if ($null -eq $installedAgentVersion) {
        Write-Log "Agent not installed - installation required" -Level Info
        return $true
    }

    # Get config version from config file
    $installedConfigVersion = Get-InstalledConfigVersion
    
    if ($null -eq $installedConfigVersion) {
        Write-Log "Config version not found - update required" -Level Warning
        return $true
    }

    # Compare versions
    if ($installedAgentVersion -ne $TargetAgentVersion) {
        Write-Log "Agent version mismatch (current: $installedAgentVersion, target: $TargetAgentVersion) - update required" -Level Warning
        return $true
    }

    if ($installedConfigVersion -ne $TargetConfigVersion) {
        Write-Log "Config version mismatch (current: $installedConfigVersion, target: $TargetConfigVersion) - update required" -Level Warning
        return $true
    }

    Write-Log "Agent version $installedAgentVersion and config version $installedConfigVersion are up to date" -Level Success
    return $false
}

function Stop-ZabbixService {
    <#
    .SYNOPSIS
        Stops Zabbix Agent 2 service if running.
    #>
    try {
        $service = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
        
        if ($null -eq $service) {
            Write-Log "Service not found - skipping stop" -Level Info
            return
        }

        if ($service.Status -eq 'Running') {
            Write-Log "Stopping service '$script:ServiceName'..." -Level Info
            Stop-Service -Name $script:ServiceName -Force -ErrorAction Stop
            Write-Log "Service stopped successfully" -Level Success
        } else {
            Write-Log "Service is not running" -Level Info
        }
    }
    catch {
        Write-Log "Error stopping service: $_" -Level Error
        throw
    }
}

function Install-ZabbixAgent {
    <#
    .SYNOPSIS
        Installs or updates Zabbix Agent 2 from MSI.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$MSIPath,
        
        [Parameter(Mandatory=$true)]
        [string]$ServerAddress,
        
        [Parameter(Mandatory=$true)]
        [string]$ServerActiveAddress
    )

    try {
        Write-Log "Installing Zabbix Agent 2 from: $MSIPath" -Level Info

        if (-not (Test-Path $MSIPath)) {
            throw "MSI file not found: $MSIPath"
        }

        $arguments = @(
            "/i"
            "`"$MSIPath`""
            "/qn"
            "DONOTSTART=1"
            "ENABLEPATH=1"
            "TARGETDIR=`"$script:InstallPath`""
            "SERVER=$ServerAddress"
            "SERVERACTIVE=$ServerActiveAddress"
        )

        Write-Log "Executing: msiexec.exe $($arguments -join ' ')" -Level Info
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -ne 0) {
            throw "MSI installation failed with exit code: $($process.ExitCode)"
        }

        Write-Log "Zabbix Agent 2 installed successfully" -Level Success
    }
    catch {
        Write-Log "Error during installation: $_" -Level Error
        throw
    }
}

function Update-ConfigurationFile {
    <#
    .SYNOPSIS
        Copies configuration file from network share.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath
    )

    try {
        Write-Log "Copying configuration file from: $SourcePath" -Level Info

        if (-not (Test-Path $SourcePath)) {
            throw "Source configuration file not found: $SourcePath"
        }

        # Copy config file as-is without modifications
        Copy-Item -Path $SourcePath -Destination $script:ConfigFile -Force

        Write-Log "Configuration file copied successfully" -Level Success
    }
    catch {
        Write-Log "Error copying configuration file: $_" -Level Error
        throw
    }
}

function New-PSKKeyFile {
    <#
    .SYNOPSIS
        Creates PSK key file with specified content.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$KeyContent
    )

    try {
        Write-Log "Creating PSK key file: $script:PSKFile" -Level Info

        # Write key content to file
        $KeyContent | Set-Content -Path $script:PSKFile -Encoding ASCII -NoNewline -Force

        # Secure the file (remove inheritance, grant only SYSTEM and Administrators)
        $acl = Get-Acl $script:PSKFile
        $acl.SetAccessRuleProtection($true, $false)
        
        # Remove all existing rules
        $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
        
        # Add SYSTEM - Full Control
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM", "FullControl", "Allow"
        )
        $acl.AddAccessRule($systemRule)
        
        # Add Administrators - Full Control
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators", "FullControl", "Allow"
        )
        $acl.AddAccessRule($adminRule)
        
        # Add NetworkService - Read (for Zabbix Agent service)
        $serviceRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\NetworkService", "Read", "Allow"
        )
        $acl.AddAccessRule($serviceRule)
        
        Set-Acl -Path $script:PSKFile -AclObject $acl

        Write-Log "PSK key file created and secured" -Level Success
    }
    catch {
        Write-Log "Error creating PSK key file: $_" -Level Error
        throw
    }
}

function Start-ZabbixService {
    <#
    .SYNOPSIS
        Starts Zabbix Agent 2 service.
    #>
    try {
        Write-Log "Starting service '$script:ServiceName'..." -Level Info

        $service = Get-Service -Name $script:ServiceName -ErrorAction Stop
        
        if ($service.Status -ne 'Running') {
            Start-Service -Name $script:ServiceName -ErrorAction Stop
            
            # Wait for service to start
            Start-Sleep -Seconds 2
            
            $service.Refresh()
            if ($service.Status -eq 'Running') {
                Write-Log "Service started successfully" -Level Success
            } else {
                throw "Service failed to start (status: $($service.Status))"
            }
        } else {
            Write-Log "Service is already running" -Level Info
        }
    }
    catch {
        Write-Log "Error starting service: $_" -Level Error
        throw
    }
}

function Test-ServiceHealth {
    <#
    .SYNOPSIS
        Verifies service is running and healthy.
    #>
    try {
        Write-Log "Checking service health..." -Level Info

        $service = Get-Service -Name $script:ServiceName -ErrorAction Stop
        
        if ($service.Status -ne 'Running') {
            throw "Service is not running (status: $($service.Status))"
        }

        # Check log file for errors
        $logFile = Join-Path $script:InstallPath "zabbix_agent2.log"
        if (Test-Path $logFile) {
            $recentLog = Get-Content $logFile -Tail 20 -ErrorAction SilentlyContinue
            $errors = $recentLog | Select-String -Pattern "error|failed|cannot" -SimpleMatch
            
            if ($errors) {
                Write-Log "Recent errors found in log file:" -Level Warning
                $errors | ForEach-Object { Write-Log "  $_" -Level Warning }
            }
        }

        Write-Log "Service health check passed" -Level Success
        return $true
    }
    catch {
        Write-Log "Service health check failed: $_" -Level Error
        return $false
    }
}

#endregion

#region Main Script

try {
    Write-Log "=== Zabbix Agent 2 Installation Script ===" -Level Info
    Write-Log "MSI Filename: $MSIFileName" -Level Info
    Write-Log "Config Version: $ConfigVersion" -Level Info
    Write-Log "Network Share: $NetworkShare" -Level Info
    Write-Log "" -Level Info

    # Step 1: Mount network share as PSDrive for session access
    Write-Log "Step 1: Mounting network share..." -Level Info
    $driveName = "ZabbixTemp"
    
    try {
        # Remove drive if already exists
        if (Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue) {
            Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue
        }
        
        # Mount network share
        $null = New-PSDrive -Name $driveName -PSProvider FileSystem -Root $NetworkShare -ErrorAction Stop
        Write-Log "Network share mounted as ${driveName}:" -Level Success
        
        # Update NetworkShare path to use mounted drive
        $NetworkShare = "${driveName}:"
    }
    catch {
        Write-Log "Warning: Could not mount network drive, will use UNC path directly: $_" -Level Warning
        # Continue with original UNC path
    }

    # Step 2: Extract version from MSI filename
    Write-Log "Step 2: Extracting version from MSI filename..." -Level Info
    $targetAgentVersion = Get-VersionFromMSIFileName -FileName $MSIFileName
    Write-Log "Target Agent Version: $targetAgentVersion" -Level Success

    # Step 3: Check if update is required
    Write-Log "Step 3: Checking if installation/update is required..." -Level Info
    $updateRequired = Test-UpdateRequired -TargetAgentVersion $targetAgentVersion -TargetConfigVersion $ConfigVersion

    if (-not $updateRequired) {
        Write-Log "No update required - exiting" -Level Success
        exit 0
    }

    # Step 4: Find MSI file in network share
    Write-Log "Step 4: Locating MSI installer..." -Level Info
    $msiFile = Get-ChildItem -Path $NetworkShare -Filter $MSIFileName -File -ErrorAction Stop | Select-Object -First 1

    if ($null -eq $msiFile) {
        throw "MSI file not found in network share: $MSIFileName"
    }

    Write-Log "Found MSI: $($msiFile.FullName)" -Level Success

    # Step 5: Find configuration file
    Write-Log "Step 5: Locating configuration file..." -Level Info
    $configSource = Join-Path $NetworkShare "zabbix_agent2.conf"

    if (-not (Test-Path $configSource)) {
        throw "Configuration file not found: $configSource"
    }

    Write-Log "Found config: $configSource" -Level Success

    # Step 6: Stop service if running
    Write-Log "Step 6: Stopping Zabbix service..." -Level Info
    Stop-ZabbixService

    # Step 7: Install/Update agent
    Write-Log "Step 7: Installing Zabbix Agent 2..." -Level Info
    Install-ZabbixAgent -MSIPath $msiFile.FullName -ServerAddress $Server -ServerActiveAddress $ServerActive

    # Step 8: Update configuration
    Write-Log "Step 8: Updating configuration file..." -Level Info
    Update-ConfigurationFile -SourcePath $configSource

    # Step 9: Create PSK key file
    Write-Log "Step 9: Creating PSK key file..." -Level Info
    New-PSKKeyFile -KeyContent $PSKKey

    # Step 10: Start service
    Write-Log "Step 10: Starting Zabbix service..." -Level Info
    Start-ZabbixService

    # Step 11: Verify installation
    Write-Log "Step 11: Verifying installation..." -Level Info
    $healthy = Test-ServiceHealth

    if (-not $healthy) {
        Write-Log "Service health check failed - please review logs" -Level Warning
    }

    Write-Log "" -Level Info
    Write-Log "=== Installation completed successfully ===" -Level Success
    
    # Get actual installed version
    $finalAgentVersion = Get-InstalledAgentVersion
    Write-Log "Agent Version: $finalAgentVersion" -Level Success
    Write-Log "Config Version: $ConfigVersion" -Level Success
    Write-Log "Installation Path: $script:InstallPath" -Level Success
    
    exit 0
}
catch {
    Write-Log "" -Level Error
    Write-Log "=== Installation failed ===" -Level Error
    Write-Log "Error: $_" -Level Error
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
finally {
    # Cleanup: Remove mounted PSDrive if exists
    if (Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue) {
        Write-Log "Cleaning up: Removing mounted drive ${driveName}:" -Level Info
        Remove-PSDrive -Name $driveName -Force -ErrorAction SilentlyContinue
    }
}

#endregion
