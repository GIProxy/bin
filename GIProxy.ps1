<#
.SYNOPSIS
Update GIProxy-bin and run GIProxy.exe elevated using ShellExecute (COM).

.DESCRIPTION
- Clones repo if missing, or updates it only when remote version differs.
- Detects OS architecture (x64/x86/arm64) to pick the correct executable.
- Properly detects existing portable Git to avoid re-downloading.
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
    return (Invoke-RestMethod -Uri $remoteVersionUrl -UseBasicParsing).Trim()
  } catch {
    Write-Log "Warning: Failed to fetch remote version: $($_.Exception.Message)"
    return $null
  }
}

function Install-PortableGit {
  Write-Log "Git not found. Downloading and installing portable Git..."
  # NOTE: update these URLs if you want a newer PortableGit release.
  $is64 = [Environment]::Is64BitOperatingSystem
  $archLabel = if ($is64) { "64-bit" } else { "32-bit" }

  # Official Git for Windows portable self-extracting links (example versions)
  $gitPortableUrl = if ($is64) {
    "https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/PortableGit-2.44.0-64-bit.7z.exe"
  } else {
    "https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/PortableGit-2.44.0-32-bit.7z.exe"
  }

  # There is no official arm64 PortableGit in many releases; if running on ARM64, try 64-bit x64 as fallback.
  if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -eq "Arm64") {
    Write-Log "Running on Arm64. Portable Git ARM builds may not exist; will try 64-bit portable Git as fallback."
    $gitPortableUrl = "https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/PortableGit-2.44.0-64-bit.7z.exe"
  }

  try {
    $downloadPath = Join-Path $scriptDir "PortableGit.7z.exe"

    if (-not (Test-Path $portableGitDir)) {
      New-Item -Path $portableGitDir -ItemType Directory | Out-Null
    }

    Write-Log "Downloading portable Git ($archLabel) from $gitPortableUrl..."
    Invoke-WebRequest -Uri $gitPortableUrl -OutFile $downloadPath -UseBasicParsing

    Write-Log "Extracting portable Git to $portableGitDir..."
    # Self-extracting 7z exe supports /S /D= extraction arguments in many builds
    & $downloadPath /S /D=$portableGitDir

    if (Test-Path $downloadPath) {
      Remove-Item $downloadPath -Force
    }

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

  # --- Git Detection Logic ---
  $gitPath = $null

  # 1) Check if portable Git already exists
  if (Test-Path $portableGitExePath) {
    $gitPath = $portableGitExePath
    Write-Log "Using existing portable Git from: $gitPath"
  }
  # 2) Check system git (on PATH)
  elseif (Get-Command git -ErrorAction SilentlyContinue) {
    $gitPath = (Get-Command git).Source
    Write-Log "Using system-wide Git from: $gitPath"
  }
  # 3) Try to find git in common Program Files locations (Windows installers)
  else {
    $possiblePaths = @(
      "$env:ProgramFiles\Git\cmd\git.exe",
      "$env:ProgramFiles(x86)\Git\cmd\git.exe",
      "$env:ProgramW6432\Git\cmd\git.exe"
    )
    foreach ($p in $possiblePaths) {
      if (Test-Path $p) {
        $gitPath = $p
        Write-Log "Found Git at: $gitPath"
        break
      }
    }
  }

  # 4) If still not found, download portable Git
  if (-not $gitPath) {
    $gitPath = Install-PortableGit
    Write-Log "Portable Git has been installed and will be used from: $gitPath"
  }

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

  # --- Determine platform directory name (support both x64/amd64 and x86/amd32) ---
  $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  Write-Log "Runtime OSArchitecture: $osArch"

  # canonical prefered names we will try first: x64, x86, arm64
  switch ($osArch) {
    "Arm64" { $primaryNames = @("arm64") }
    "X64"   { $primaryNames = @("x64","amd64") }
    "X86"   { $primaryNames = @("x86","amd32") }
    default { $primaryNames = @("x64","amd64","x86","amd32","arm64") }
  }

  Write-Log ("Preferred platform folder names to try: {0}" -f ($primaryNames -join ", "))

  # Build candidate paths to try (primary first, then other common alternatives)
  $candidateDirs = @()
  foreach ($name in $primaryNames) {
    $candidateDirs += Join-Path $clonePath "win\$name\Release"
    $candidateDirs += Join-Path $clonePath "win\$name" # sometimes no Release folder
  }

  # Also add common alternate names if not present already
  $fallbackNames = @("amd64","amd32","x64","x86","arm64") | Where-Object { $primaryNames -notcontains $_ }
  foreach ($name in $fallbackNames) {
    $candidateDirs += Join-Path $clonePath "win\$name\Release"
    $candidateDirs += Join-Path $clonePath "win\$name"
  }

  # Normalize unique candidate dirs
  $candidateDirs = $candidateDirs | Select-Object -Unique

  $exePath = $null
  foreach ($dir in $candidateDirs) {
    $tryExe = Join-Path $dir "GIProxy.exe"
    if (Test-Path $tryExe) {
      $exePath = $tryExe
      Write-Log "Found executable at: $exePath"
      break
    } else {
      Write-Log "Not found at: $tryExe"
    }
  }

  if (-not $exePath) {
    throw "GIProxy.exe not found in any expected architecture path. Checked: `n$($candidateDirs -join "`n")"
  }

  # Launch elevated using Shell.Application COM (ShellExecute 'runas').
  Write-Log "Launching elevated process using ShellExecute (COM) with argument: $exeArg"
  $shell = New-Object -ComObject Shell.Application

  $workingDir = Split-Path $exePath -Parent
  $argsSafe = $exeArg

  $shell.ShellExecute($exePath, $argsSafe, $workingDir, "runas", 1)

  Write-Log "Command dispatched to elevated process (if UAC accepted, GIProxy will run)."
} catch {
  Write-Log "ERROR: $($_.Exception.Message)"
  exit 1
}
