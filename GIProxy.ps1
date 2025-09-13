<#
.SYNOPSIS
Update GIProxy-bin and run GIProxy.exe elevated using ShellExecute (COM).

.DESCRIPTION
- Clones repo if missing, or updates it only when remote version differs.
- Detects OS architecture (amd64/amd32/arm64) to pick the correct executable.
- **Fixed:** Properly detects existing portable Git to avoid re-downloading.
- Launches GIProxy.exe elevated with '--https' via Shell.Application's ShellExecute.
- Uses English messages inside the script.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration ---
$repoUrl = 'https://github.com/GTPSHAX/GIProxy-bin.git'
$remoteVersionUrl = 'https://raw.githubusercontent.com/GTPSHAX/GIProxy-bin/main/version'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$clonePath = Join-Path $scriptDir 'GIProxy-bin'
$localVersionFile = Join-Path $clonePath 'version'
$exeArg = '--https'      # argument to pass to GIProxy.exe
$portableGitDir = Join-Path $scriptDir 'PortableGit'
$portableGitExePath = Join-Path $portableGitDir 'cmd\git.exe' # Path to portable git executable

function Write-Log {
  param([string]$msg)
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Write-Host "[$ts] $msg"
}

function Get-RemoteVersion {
  try {
    # Use Invoke-RestMethod to read the text file; fall back gracefully on failure.
    return (Invoke-RestMethod -Uri $remoteVersionUrl -UseBasicParsing).Trim()
  } catch {
    Write-Log "Warning: Failed to fetch remote version: $($_.Exception.Message)"
    return $null
  }
}

function Install-PortableGit {
  Write-Log "Git not found. Downloading and installing portable Git..."
  $gitPortableUrl = "https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/PortableGit-2.44.0-64-bit.7z.exe"
  
  # Check for 32-bit or other architectures; for now, we only provide a link for 64-bit due to repo limitations.
  # Note: If you need 32-bit portable Git, you'll need to update this URL.
  $arch = "64-bit"
  if (-not [Environment]::Is64BitOperatingSystem) {
    $arch = "32-bit"
    $gitPortableUrl = "https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/PortableGit-2.44.0-32-bit.7z.exe"
  }

  # Download the self-extracting archive
  try {
    $downloadPath = Join-Path $scriptDir "PortableGit.7z.exe"
    
    # Create portable git directory if it doesn't exist
    if (-not (Test-Path $portableGitDir)) {
      New-Item -Path $portableGitDir -ItemType Directory | Out-Null
    }
    
    Write-Log "Downloading portable Git ($arch) from $gitPortableUrl..."
    Invoke-WebRequest -Uri $gitPortableUrl -OutFile $downloadPath -UseBasicParsing
    
    # Extract the archive
    Write-Log "Extracting portable Git to $portableGitDir..."
    & $downloadPath /S /D=$portableGitDir
    
    # Clean up downloaded file
    if (Test-Path $downloadPath) {
      Remove-Item $downloadPath -Force
    }
    
    # Verify extraction was successful
    if (-not (Test-Path $portableGitExePath)) {
      throw "Failed to extract portable Git - executable not found at $portableGitExePath"
    }
    
    Write-Log "Portable Git installed successfully at: $portableGitDir"
    return $portableGitExePath
    
  } catch {
    throw "Failed to download or install portable Git: $($_.Exception.Message)"
  }
}

try {
  Write-Log "Starting GIProxy update & elevated-run workflow."

  # --- Git Detection Logic (Fixed Order) ---
  $gitPath = $null
  
  # 1. FIRST: Check if portable Git is already installed by this script
  if (Test-Path $portableGitExePath) {
    $gitPath = $portableGitExePath
    Write-Log "Using existing portable Git from: $gitPath"
  }
  # 2. SECOND: Check if Git is installed system-wide (only if portable not found)
  elseif (Get-Command git -ErrorAction SilentlyContinue) {
    $gitPath = (Get-Command git).Source
    Write-Log "Using system-wide Git from: $gitPath"
  }
  # 3. LAST RESORT: Download and install portable Git
  else {
    $gitPath = Install-PortableGit
    Write-Log "Portable Git has been installed and will be used from: $gitPath"
  }

  # Verify git path exists before proceeding
  if (-not (Test-Path $gitPath)) {
    throw "Git executable not found at: $gitPath"
  }

  # --- Git Operations ---
  # Clone repo if missing
  if (-not (Test-Path $clonePath)) {
    Write-Log "Repository not found. Cloning to '$clonePath'..."
    & $gitPath clone $repoUrl $clonePath
    if ($LASTEXITCODE -ne 0) {
      throw "Git clone failed with exit code: $LASTEXITCODE"
    }
  } else {
    # Compare remote vs local version
    $remoteVersion = Get-RemoteVersion
    $localVersion = if (Test-Path $localVersionFile) { (Get-Content $localVersionFile -Raw).Trim() } else { "" }

    if ($remoteVersion -and ($remoteVersion -ne $localVersion)) {
        Write-Log "Version change detected (remote: '$remoteVersion', local: '$localVersion'). Updating repository..."
        Push-Location $clonePath
        try {
            & $gitPath fetch origin main
            if ($LASTEXITCODE -ne 0) {
              throw "Git fetch failed with exit code: $LASTEXITCODE"
            }
            & $gitPath reset --hard origin/main
            if ($LASTEXITCODE -ne 0) {
              throw "Git reset failed with exit code: $LASTEXITCODE"
            }
        } finally {
          Pop-Location
        }
    } else {
      Write-Log "Repository is up to date (remote: '$remoteVersion', local: '$localVersion')."
    }
  }

  # --- Continue with GIProxy.exe launch ---
  # Detect architecture and map to directory name
  $platform = ""
  switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
    "Arm64" { $platform = "arm64" }
    "X64"   { $platform = "amd64" }
    "X86"   { $platform = "amd32" }
    default { throw "Unsupported architecture: $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)" }
  }
  Write-Log "Detected platform: $platform"

  # Determine exe path
  $exePathPrimary = Join-Path $clonePath "win\$platform\Release\GIProxy.exe"
  $exePath = $exePathPrimary

  if (-not (Test-Path $exePath)) {
      Write-Log "Executable not found at primary path: $exePathPrimary. Trying alternate architectures..."
      $foundAlt = $false
      $architectures = @("amd64", "amd32", "arm64") | Where-Object { $_ -ne $platform }
      foreach ($altPlatform in $architectures) {
        $exePathAlt = Join-Path $clonePath "win\$altPlatform\Release\GIProxy.exe"
        if (Test-Path $exePathAlt) {
          $exePath = $exePathAlt
          Write-Log "Found executable at alternate path: $exePathAlt"
          $foundAlt = $true
          break
        }
      }
      if (-not $foundAlt) {
        throw "GIProxy.exe not found in any architecture path."
      }
  } else {
    Write-Log "Found executable: $exePath"
  }

  # Launch elevated using Shell.Application COM (ShellExecute 'runas').
  Write-Log "Launching elevated process using ShellExecute (COM) with argument: $exeArg"
  $shell = New-Object -ComObject Shell.Application

  # ShellExecute parameters: (File, Arguments, WorkingDirectory, Operation, ShowCmd)
  $workingDir = Split-Path $exePath -Parent
  # Ensure argument string is safe
  $argsSafe = $exeArg

  # Use ShellExecute to perform a 'runas' (elevation). This will show UAC prompt.
  $shell.ShellExecute($exePath, $argsSafe, $workingDir, "runas", 1)

  Write-Log "Command dispatched to elevated process (if UAC accepted, GIProxy will run)."
  # Do not wait here — ShellExecute returns immediately.
} catch {
  Write-Log "ERROR: $($_.Exception.Message)"
  exit 1
}