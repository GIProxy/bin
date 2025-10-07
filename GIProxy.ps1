#Requires -Version 5.1
<#
.SYNOPSIS
    GIProxy Auto-Updater and Launcher
.DESCRIPTION
    Automatically installs Git Portable if needed, clones/updates the GIProxy binary repository,
    and launches the appropriate executable for your system architecture.
.NOTES
    Version: 1.0.0
    Author: GIProxy Team
#>

param(
  [switch]$SkipUpdate,
  [switch]$ForceUpdate,
  [ValidateSet("x64", "x86", "arm64", "auto")]
  [string]$Architecture = "auto"
)

# Configuration
$RepoUrl = "https://github.com/GIProxy/bin.git"
$RepoBranch = "main"
$InstallDir = Join-Path $PSScriptRoot "GIProxy"
$GitPortableDir = Join-Path $PSScriptRoot ".git-portable"
$VersionFile = "version"

# Colors for output
$ColorInfo = "Cyan"
$ColorSuccess = "Green"
$ColorWarning = "Yellow"
$ColorError = "Red"

# Architecture detection
function Get-SystemArchitecture {
  $arch = $env:PROCESSOR_ARCHITECTURE
  $arch6432 = $env:PROCESSOR_ARCHITEW6432
    
  if ($arch6432) {
    return $arch6432.ToLower()
  }
    
  switch ($arch.ToLower()) {
    "amd64" { return "x64" }
    "x86" { return "x86" }
    "arm64" { return "arm64" }
    default { return "x64" }
  }
}

# Detect architecture
if ($Architecture -eq "auto") {
  $Architecture = Get-SystemArchitecture
  Write-Host "[INFO] Detected architecture: $Architecture" -ForegroundColor $ColorInfo
}

# Git Portable URLs
$GitPortableUrls = @{
  "x64"   = "https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.2/PortableGit-2.47.0.2-64-bit.7z.exe"
  "x86"   = "https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.2/PortableGit-2.47.0.2-32-bit.7z.exe"
  "arm64" = "https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.2/PortableGit-2.47.0.2-64-bit.7z.exe"
}

function Write-ColorOutput {
  param(
    [string]$Message,
    [string]$Type = "INFO"
  )
    
  $color = $ColorInfo
  switch ($Type) {
    "SUCCESS" { $color = $ColorSuccess }
    "WARNING" { $color = $ColorWarning }
    "ERROR" { $color = $ColorError }
  }
    
  Write-Host "[$Type] $Message" -ForegroundColor $color
}

function Test-GitInstalled {
  try {
    $null = Get-Command git -ErrorAction Stop
    return $true
  }
  catch {
    return $false
  }
}

function Install-GitPortable {
  param([string]$Arch)
    
  Write-ColorOutput "Git not found. Installing Git Portable for $Arch..." "INFO"
    
  if (-not $GitPortableUrls.ContainsKey($Arch)) {
    Write-ColorOutput "Unsupported architecture: $Arch" "ERROR"
    exit 1
  }
    
  $gitUrl = $GitPortableUrls[$Arch]
  $gitInstaller = Join-Path $env:TEMP "git-portable-$Arch.exe"
    
  try {
    # Create directory
    New-Item -ItemType Directory -Path $GitPortableDir -Force | Out-Null
        
    # Download Git Portable
    Write-ColorOutput "Downloading Git Portable from: $gitUrl" "INFO"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
    $ProgressPreference = 'Continue'
        
    Write-ColorOutput "Extracting Git Portable..." "INFO"
        
    # Extract using self-extracting archive
    Start-Process -FilePath $gitInstaller -ArgumentList "-o`"$GitPortableDir`" -y" -Wait -NoNewWindow
        
    # Clean up
    Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue
        
    # Verify extraction
    $gitExe = Join-Path $GitPortableDir "cmd\git.exe"
    if (Test-Path $gitExe) {
      Write-ColorOutput "Git Portable installed successfully!" "SUCCESS"
      return $gitExe
    }
        
    # Try alternative path
    $gitExe = Join-Path $GitPortableDir "bin\git.exe"
    if (Test-Path $gitExe) {
      Write-ColorOutput "Git Portable installed successfully!" "SUCCESS"
      return $gitExe
    }
        
    throw "Git executable not found after extraction"
  }
  catch {
    Write-ColorOutput "Failed to install Git Portable: $($_.Exception.Message)" "ERROR"
    exit 1
  }
}

function Get-GitCommand {
  param([string]$Arch)
    
  if (Test-GitInstalled) {
    return "git"
  }
    
  # Check if Git Portable already exists
  $gitPortableExe = Join-Path $GitPortableDir "cmd\git.exe"
  if (-not (Test-Path $gitPortableExe)) {
    $gitPortableExe = Join-Path $GitPortableDir "bin\git.exe"
  }
    
  if (Test-Path $gitPortableExe) {
    return $gitPortableExe
  }
    
  # Install Git Portable
  return Install-GitPortable -Arch $Arch
}

function Get-LocalVersion {
  $versionPath = Join-Path $InstallDir $VersionFile
  if (Test-Path $versionPath) {
    return (Get-Content $versionPath -Raw).Trim()
  }
  return $null
}

function Get-RemoteVersion {
  param([string]$GitCmd)
    
  try {
    $remoteVersion = & $GitCmd ls-remote --heads $RepoUrl $RepoBranch 2>&1
    if ($LASTEXITCODE -eq 0 -and $remoteVersion) {
      return $remoteVersion.Split()[0].Substring(0, 7)
    }
  }
  catch {
    Write-ColorOutput "Failed to get remote version: $($_.Exception.Message)" "WARNING"
  }
  return $null
}

function Initialize-Repository {
  param([string]$GitCmd)
    
  Write-ColorOutput "Cloning repository from $RepoUrl..." "INFO"
    
  try {
    $cloneArgs = @("clone", "--branch", $RepoBranch, $RepoUrl, $InstallDir)
    $process = Start-Process -FilePath $GitCmd -ArgumentList $cloneArgs -Wait -NoNewWindow -PassThru
        
    if ($process.ExitCode -ne 0) {
      throw "Git clone failed with exit code $($process.ExitCode)"
    }
        
    Write-ColorOutput "Repository cloned successfully!" "SUCCESS"
    return $true
  }
  catch {
    Write-ColorOutput "Failed to clone repository: $($_.Exception.Message)" "ERROR"
    return $false
  }
}

function Update-Repository {
  param([string]$GitCmd)
    
  Write-ColorOutput "Updating repository..." "INFO"
    
  Push-Location $InstallDir
  try {
    # Fetch latest changes
    & $GitCmd fetch origin $RepoBranch 2>&1 | Out-Null
        
    if ($LASTEXITCODE -ne 0) {
      throw "Git fetch failed"
    }
        
    # Get current branch
    $currentBranch = (& $GitCmd rev-parse --abbrev-ref HEAD).Trim()
        
    # Stash local changes to preserve user data
    Write-ColorOutput "Preserving local changes..." "INFO"
    & $GitCmd stash push -m "Auto-stash before update $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>&1 | Out-Null
    $stashed = $LASTEXITCODE -eq 0
        
    # Pull with rebase to avoid merge commits
    Write-ColorOutput "Pulling latest changes..." "INFO"
    & $GitCmd pull origin $RepoBranch --rebase 2>&1 | Out-Null
        
    if ($LASTEXITCODE -ne 0) {
      Write-ColorOutput "Pull failed, attempting to resolve..." "WARNING"
            
      # Try to continue rebase with ours strategy
      & $GitCmd rebase --continue 2>&1 | Out-Null
            
      if ($LASTEXITCODE -ne 0) {
        # Abort rebase and try merge instead
        & $GitCmd rebase --abort 2>&1 | Out-Null
        & $GitCmd pull origin $RepoBranch --strategy-option=theirs 2>&1 | Out-Null
      }
    }
        
    # Restore stashed changes
    if ($stashed) {
      Write-ColorOutput "Restoring local changes..." "INFO"
      & $GitCmd stash pop 2>&1 | Out-Null
            
      if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "Could not automatically restore all changes. Check 'git stash list' manually." "WARNING"
      }
    }
        
    Write-ColorOutput "Repository updated successfully!" "SUCCESS"
    return $true
  }
  catch {
    Write-ColorOutput "Failed to update repository: $($_.Exception.Message)" "ERROR"
        
    # Try to recover
    & $GitCmd rebase --abort 2>&1 | Out-Null
    & $GitCmd merge --abort 2>&1 | Out-Null
        
    return $false
  }
  finally {
    Pop-Location
  }
}

function Get-ExecutablePath {
  param([string]$Arch)
    
  $buildType = if (Test-Path (Join-Path $InstallDir "win\$Arch\Release\GIProxy.exe")) { "Release" } else { "Debug" }
  $exePath = Join-Path $InstallDir "win\$Arch\$buildType\GIProxy.exe"
    
  if (Test-Path $exePath) {
    return $exePath
  }
    
  Write-ColorOutput "Executable not found for $Arch ($buildType)" "ERROR"
  Write-ColorOutput "Expected path: $exePath" "ERROR"
  return $null
}

function Start-GIProxy {
  param([string]$Arch)
    
  $exePath = Get-ExecutablePath -Arch $Arch
    
  if (-not $exePath) {
    Write-ColorOutput "Cannot start GIProxy: executable not found" "ERROR"
    exit 1
  }
    
  $workingDir = Split-Path $exePath -Parent
    
  Write-ColorOutput "Starting GIProxy..." "INFO"
  Write-ColorOutput "Executable: $exePath" "INFO"
  Write-ColorOutput "Working Directory: $workingDir" "INFO"
  Write-ColorOutput "" "INFO"
  Write-Host "================================" -ForegroundColor $ColorSuccess
  Write-Host "     GIProxy Starting...        " -ForegroundColor $ColorSuccess
  Write-Host "================================" -ForegroundColor $ColorSuccess
  Write-Host ""
    
  Push-Location $workingDir
  try {
    # Start the process and wait for it
    & $exePath
  }
  catch {
    Write-ColorOutput "Error running GIProxy: $($_.Exception.Message)" "ERROR"
    exit 1
  }
  finally {
    Pop-Location
  }
}

function New-DesktopShortcut {
  param([string]$Arch)
  
  $desktopPath = [Environment]::GetFolderPath("Desktop")
  $shortcutPath = Join-Path $desktopPath "GIProxy.lnk"
    
  if (Test-Path $shortcutPath) {
    Write-ColorOutput "Desktop shortcut already exists" "INFO"
    return
  }
  
  # Wait until repository is cloned
  if (-not (Test-Path (Join-Path $InstallDir ".git"))) {
    return
  }
  
  # Get executable path
  $exePath = Get-ExecutablePath -Arch $Arch
  if (-not $exePath) {
    return
  }
  
  $workingDir = Split-Path $exePath -Parent
    
  try {
    Write-ColorOutput "Creating desktop shortcut..." "INFO"
        
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($shortcutPath)
    $Shortcut.TargetPath = $exePath
    $Shortcut.WorkingDirectory = $workingDir
    $Shortcut.IconLocation = "$exePath,0"
    $Shortcut.Description = "GIProxy - Growtopia Proxy"
    $Shortcut.Save()
        
    Write-ColorOutput "Desktop shortcut created successfully!" "SUCCESS"
  }
  catch {
    Write-ColorOutput "Failed to create desktop shortcut: $($_.Exception.Message)" "WARNING"
  }
}

# Main execution
function Main {
  Write-Host ""
  Write-Host "========================================" -ForegroundColor $ColorInfo
  Write-Host "   GIProxy Auto-Updater & Launcher     " -ForegroundColor $ColorInfo
  Write-Host "========================================" -ForegroundColor $ColorInfo
  Write-Host ""
    
  # Get Git command
  $gitCmd = Get-GitCommand -Arch $Architecture
  Write-ColorOutput "Using Git: $gitCmd" "INFO"
    
  # Check if repository exists
  $repoExists = Test-Path (Join-Path $InstallDir ".git")
    
  if (-not $repoExists) {
    Write-ColorOutput "Repository not found. Initializing..." "INFO"
        
    if (-not (Initialize-Repository -GitCmd $gitCmd)) {
      Write-ColorOutput "Failed to initialize repository" "ERROR"
      exit 1
    }
  }
  elseif (-not $SkipUpdate) {
    # Check version
    $localVersion = Get-LocalVersion
    $versionDisplay = if ($localVersion) { $localVersion } else { "unknown" }
    Write-ColorOutput "Local version: $versionDisplay" "INFO"
        
    if ($ForceUpdate) {
      Write-ColorOutput "Force update requested" "WARNING"
      Update-Repository -GitCmd $gitCmd | Out-Null
    }
    else {
      # Always try to update to get latest changes
      Write-ColorOutput "Checking for updates..." "INFO"
      Update-Repository -GitCmd $gitCmd | Out-Null
            
      $newVersion = Get-LocalVersion
      if ($newVersion -and $newVersion -ne $localVersion) {
        Write-ColorOutput "Updated from version $localVersion to $newVersion" "SUCCESS"
      }
      else {
        Write-ColorOutput "Already up to date" "SUCCESS"
      }
    }
  }
  else {
    Write-ColorOutput "Skipping update check" "WARNING"
  }
  
  # Create desktop shortcut after repository is ready
  New-DesktopShortcut -Arch $Architecture
    
  # Start GIProxy
  Write-Host ""
  Start-GIProxy -Arch $Architecture
}

# Run main function
try {
  Main
}
catch {
  Write-ColorOutput "Unexpected error: $($_.Exception.Message)" "ERROR"
  Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" "ERROR"
  exit 1
}
