#!/bin/sh

if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  elif [ -x "/data/data/com.termux/files/usr/bin/bash" ]; then
    exec "/data/data/com.termux/files/usr/bin/bash" "$0" "$@"
  else
    echo "[ERROR] - Bash shell is required. Install it via 'pkg install bash'." >&2
    exit 1
  fi
fi

set -e
trap 'ret=$?; echo "[ERROR] - Unexpected error occurred (exit code $ret) at ${BASH_SOURCE[0]}:${BASH_LINENO[0]}" >&2; exit $ret' ERR

SKIP_UPDATE=false
FORCE_UPDATE=false
ARCHITECTURE="auto"

TERMUX_PREFIX="/data/data/com.termux/files/usr"
IS_TERMUX=false
if [[ -d "$TERMUX_PREFIX" ]]; then
  IS_TERMUX=true
fi

#configuration
REPO_URL="https://github.com/GIProxy/bin.git"
REPO_BRANCH="main"
INSTALL_DIR="GIProxy"
VERSION_FILE="version"

# Parse command line arguments
echo "Tips: use --help or -h for see options."
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-update)
      SKIP_UPDATE=true
      shift
      ;;
    --force-update)
      FORCE_UPDATE=true
      shift
      ;;
    --arch)
      if [[ -z "${2:-}" ]]; then
        echo "[ERROR] - --arch requires a value (x64, x86, arm64)" >&2
        exit 1
      fi
      ARCHITECTURE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  --skip-update    Skip repository update"
      echo "  --force-update   Force repository update"
      echo "  --arch ARCH      Set architecture (x64, x86, arm64, auto)"
      echo "  -h, --help       Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Function to detect system architecture
get_system_architecture() {
  local arch
  
  # Try multiple methods to detect architecture
  if command -v uname >/dev/null 2>&1; then
    arch=$(uname -m)
  elif [[ -n "$HOSTTYPE" ]]; then
    arch="$HOSTTYPE"
  else
    arch="unknown"
  fi
  
  case "$arch" in
    x86_64|amd64)
      echo "x64"
      ;;
    i386|i686|x86)
      echo "x86"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7l|armv6l|arm)
      echo "arm64"  # Default to arm64 for ARM on Android
      ;;
    *)
      echo "arm64"  # Default for Android/Termux
      ;;
  esac
}

# Function to check if git is installed
test_git_installed() {
  command -v git >/dev/null 2>&1
}

# Function to install git using pkg (Termux)
install_git() {
  echo "[WARNING] - Git not found. Installing Git using pkg..."
  
  # Check if we're in Termux
  if ! command -v pkg >/dev/null 2>&1; then
    echo "[ERROR] - pkg command not found. This script is designed for Termux (Android)."
    echo "[ERROR] - Please install git manually or run this script in Termux."
    exit 1
  fi
  
  # Update package list and install git
  echo "[INFO] - Updating package list..."
  if ! pkg update -y; then
    echo "[ERROR] - Failed to update package list"
    exit 1
  fi
  
  echo "[INFO] - Installing git..."
  if ! pkg install git -y; then
    echo "[ERROR] - Failed to install git"
    exit 1
  fi
  
  # Verify installation
  if test_git_installed; then
    echo "[SUCCESS] - Git installed successfully!"
  else
    echo "[ERROR] - Git installation failed - command not found after installation"
    exit 1
  fi
}

# Function to get git command
get_git_command() {
  if test_git_installed; then
    echo "git"
  else
    install_git
    echo "git"
  fi
}

# Function to get local version
get_local_version() {
  local version_path="$INSTALL_DIR/$VERSION_FILE"
  if [[ -f "$version_path" ]]; then
    cat "$version_path" | tr -d '\n\r'
  else
    echo ""
  fi
}

# Function to get remote version
get_remote_version() {
  local git_cmd="$1"
  
  local remote_version
  if remote_version=$($git_cmd ls-remote --heads "$REPO_URL" "$REPO_BRANCH" 2>/dev/null); then
    if [[ -n "$remote_version" ]]; then
      echo "$remote_version" | awk '{print substr($1,1,7)}'
      return 0
    fi
  fi
  
  echo "[WARNING] - Failed to get remote version"
}

# Function to initialize repository
initialize_repository() {
  local git_cmd="$1"
  
  echo "[INFO] - Cloning repository from $REPO_URL..."
  
  if $git_cmd clone --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"; then
    echo "[SUCCESS] - Repository cloned successfully!"
    return 0
  else
    echo "[ERROR] - Failed to clone repository"
    return 1
  fi
}

# Function to update repository
update_repository() {
  local git_cmd="$1"
  
  echo "[INFO] - Updating repository..."
  
  local original_dir="$PWD"
  cd "$INSTALL_DIR" || {
    echo "[ERROR] - Failed to change to repository directory"
    return 1
  }
  
  local success=true
  
  # Fetch latest changes
  if ! $git_cmd fetch origin "$REPO_BRANCH" >/dev/null 2>&1; then
    echo "[ERROR] - Git fetch failed"
    success=false
  fi
  
  if [[ "$success" == "true" ]]; then
    # Stash local changes to preserve user data
    echo "[INFO] - Preserving local changes..."
    local stashed=false
    if $git_cmd stash push -m "Auto-stash before update $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1; then
      stashed=true
    fi
    
    # Pull with rebase to avoid merge commits
    echo "[INFO] - Pulling latest changes..."
    if ! $git_cmd pull origin "$REPO_BRANCH" --rebase >/dev/null 2>&1; then
      echo "[WARNING] - Pull failed, attempting to resolve..."
      
      # Try to continue rebase
      if ! $git_cmd rebase --continue >/dev/null 2>&1; then
        # Abort rebase and try merge instead
        $git_cmd rebase --abort >/dev/null 2>&1
        $git_cmd pull origin "$REPO_BRANCH" --strategy-option=theirs >/dev/null 2>&1
      fi
    fi
    
    # Restore stashed changes
    if [[ "$stashed" == "true" ]]; then
        echo "[INFO] - Restoring local changes..."
        if ! $git_cmd stash pop >/dev/null 2>&1; then
          echo "[WARNING] - Could not automatically restore all changes. Check 'git stash list' manually."
        fi
    fi
    
    echo "[SUCCESS] - Repository updated successfully!"
  else
    # Try to recover
    $git_cmd rebase --abort >/dev/null 2>&1
    $git_cmd merge --abort >/dev/null 2>&1
  fi
  
  cd "$original_dir" || true
  
  if [[ "$success" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

# Function to get executable path
get_executable_path() {
  local arch="$1"
  
  # Map arm64 to x64 for Android since there's no arm64 directory
  local android_arch="$arch"
  if [[ "$arch" == "arm64" ]]; then
    android_arch="x64"
  fi
  
  # Android executables are directly in the arch directory (no Release/Debug subdirs)
  if [[ -f "$INSTALL_DIR/android/$android_arch/GIProxy" ]]; then
    echo "$INSTALL_DIR/android/$android_arch/GIProxy"
    return 0
  fi
  
  # Try alternative paths for different platforms
  if [[ -f "$INSTALL_DIR/linux/$arch/Release/GIProxy" ]]; then
    echo "$INSTALL_DIR/linux/$arch/Release/GIProxy"
    return 0
  elif [[ -f "$INSTALL_DIR/linux/$arch/Debug/GIProxy" ]]; then
    echo "$INSTALL_DIR/linux/$arch/Debug/GIProxy"
    return 0
  else
    echo "[ERROR] - Executable not found for $arch"
    echo "[ERROR] - Checked paths:"
    echo "-  $INSTALL_DIR/android/$android_arch/GIProxy"
    echo "-  $INSTALL_DIR/linux/$arch/Release/GIProxy"
    echo "-  $INSTALL_DIR/linux/$arch/Debug/GIProxy"
    return 1
  fi
}

# Function to start GIProxy
start_giproxy() {
  local arch="$1"
  local exe_path
  
  if ! exe_path=$(get_executable_path "$arch"); then
    echo "[ERROR] - Cannot start GIProxy: executable not found"
    exit 1
  fi
  
  if [[ ! -f "$exe_path" ]]; then
    echo "[ERROR] - Cannot start GIProxy: executable not found at $exe_path"
    exit 1
  fi
  
  # Make executable if not already
  chmod +x "$exe_path"
  
  local working_dir="$(dirname "$exe_path")"
  
  echo "[INFO] - Starting GIProxy..."
  echo "[INFO] - Executable: $exe_path"
  echo "[INFO] - Working Directory: $working_dir"
  
  local original_dir="$PWD"
  cd "$working_dir" || {
    echo "[ERROR] - Failed to change to working directory"
    exit 1
  }
  
  # Start the process
  if ! "$exe_path"; then
    local exit_code=$?
    echo "[ERROR] - Error running GIProxy (exit code $exit_code)"
    if [[ "$exit_code" -eq 126 ]]; then
      echo "[HINT] - Exec format error detected. Ensure the selected architecture matches your device."
      if [[ "$IS_TERMUX" == true && "$arch" != "x64" ]]; then
        echo "[HINT] - On Termux (aarch64 devices), use a proot-distro with x86_64 binaries or compile GIProxy for arm64." 
      fi
    fi
    cd "$original_dir" || true
    exit 1
  fi
  
  cd "$original_dir" || true
}

# Main function
main() {
  # Detect architecture
  if [[ "$ARCHITECTURE" == "auto" ]]; then
    ARCHITECTURE=$(get_system_architecture)
    echo "[INFO] - Detected architecture: $ARCHITECTURE"
  fi
  
  # Validate architecture
  case "$ARCHITECTURE" in
    x64|x86|arm64)
      ;;
    *)
      echo "[ERROR] - Unsupported architecture: $ARCHITECTURE"
      echo "[ERROR] - Supported architectures: x64, x86, arm64"
      exit 1
      ;;
  esac
  
  # Get Git command
  local git_cmd
  git_cmd=$(get_git_command)
  echo "[INFO] - Using Git: $git_cmd"
  
  # Check if repository exists
  local repo_exists=false
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    repo_exists=true
  fi
  
  if [[ "$repo_exists" == "false" ]]; then
    echo "[INFO] - Repository not found. Initializing..."
    
    if ! initialize_repository "$git_cmd"; then
      echo "[ERROR] - Failed to initialize repository"
      exit 1
    fi
  elif [[ "$SKIP_UPDATE" == "false" ]]; then
    # Check version
    local local_version
    local_version=$(get_local_version)
    local version_display
    if [[ -n "$local_version" ]]; then
      version_display="$local_version"
    else
      version_display="unknown"
    fi
    echo "[INFO] - Local version: $version_display"
    
    if [[ "$FORCE_UPDATE" == "true" ]]; then
      echo "[WARNING] - Force update requested"
      update_repository "$git_cmd"
    else
      # Always try to update to get latest changes
      echo "[INFO] - Checking for updates..."
      update_repository "$git_cmd"
      
      local new_version
      new_version=$(get_local_version)
      if [[ -n "$new_version" && "$new_version" != "$local_version" ]]; then
        echo "[SUCCESS] - Updated from version $local_version to $new_version"
      else
        echo "[SUCCESS] - Already up to date"
      fi
    fi
  else
    echo "[WARNING] - Skipping update check"
  fi
  
  # Start GIProxy
  echo ""
  start_giproxy "$ARCHITECTURE"
}

# Run main function
main "$@"
