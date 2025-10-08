#!/bin/bash

# GIProxy Auto-Updater and Launcher
# Automatically installs Git if needed, clones/updates the GIProxy binary repository,
# and launches the appropriate executable for your system architecture.

# Default values
SKIP_UPDATE=false
FORCE_UPDATE=false
ARCHITECTURE="auto"

# Configuration
REPO_URL="https://github.com/GIProxy/bin.git"
REPO_BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR/GIProxy"
VERSION_FILE="version"

# Colors for output
COLOR_INFO='\033[0;36m'     # Cyan
COLOR_SUCCESS='\033[0;32m'  # Green
COLOR_WARNING='\033[0;33m'  # Yellow
COLOR_ERROR='\033[0;31m'    # Red
COLOR_RESET='\033[0m'       # Reset

# Parse command line arguments
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

# Function to output colored messages
write_color_output() {
    local message="$1"
    local type="${2:-INFO}"
    
    case "$type" in
        "SUCCESS")
            echo -e "${COLOR_SUCCESS}[SUCCESS]${COLOR_RESET} $message"
            ;;
        "WARNING")
            echo -e "${COLOR_WARNING}[WARNING]${COLOR_RESET} $message"
            ;;
        "ERROR")
            echo -e "${COLOR_ERROR}[ERROR]${COLOR_RESET} $message"
            ;;
        *)
            echo -e "${COLOR_INFO}[INFO]${COLOR_RESET} $message"
            ;;
    esac
}

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
    write_color_output "Git not found. Installing Git using pkg..." "INFO"
    
    # Check if we're in Termux
    if ! command -v pkg >/dev/null 2>&1; then
        write_color_output "pkg command not found. This script is designed for Termux (Android)." "ERROR"
        write_color_output "Please install git manually or run this script in Termux." "ERROR"
        exit 1
    fi
    
    # Update package list and install git
    write_color_output "Updating package list..." "INFO"
    if ! pkg update -y; then
        write_color_output "Failed to update package list" "ERROR"
        exit 1
    fi
    
    write_color_output "Installing git..." "INFO"
    if ! pkg install git -y; then
        write_color_output "Failed to install git" "ERROR"
        exit 1
    fi
    
    # Verify installation
    if test_git_installed; then
        write_color_output "Git installed successfully!" "SUCCESS"
    else
        write_color_output "Git installation failed - command not found after installation" "ERROR"
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
    
    write_color_output "Failed to get remote version" "WARNING"
    echo ""
}

# Function to initialize repository
initialize_repository() {
    local git_cmd="$1"
    
    write_color_output "Cloning repository from $REPO_URL..." "INFO"
    
    if $git_cmd clone --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"; then
        write_color_output "Repository cloned successfully!" "SUCCESS"
        return 0
    else
        write_color_output "Failed to clone repository" "ERROR"
        return 1
    fi
}

# Function to update repository
update_repository() {
    local git_cmd="$1"
    
    write_color_output "Updating repository..." "INFO"
    
    local original_dir="$PWD"
    cd "$INSTALL_DIR" || {
        write_color_output "Failed to change to repository directory" "ERROR"
        return 1
    }
    
    local success=true
    
    # Fetch latest changes
    if ! $git_cmd fetch origin "$REPO_BRANCH" >/dev/null 2>&1; then
        write_color_output "Git fetch failed" "ERROR"
        success=false
    fi
    
    if [[ "$success" == "true" ]]; then
        # Stash local changes to preserve user data
        write_color_output "Preserving local changes..." "INFO"
        local stashed=false
        if $git_cmd stash push -m "Auto-stash before update $(date '+%Y-%m-%d %H:%M:%S')" >/dev/null 2>&1; then
            stashed=true
        fi
        
        # Pull with rebase to avoid merge commits
        write_color_output "Pulling latest changes..." "INFO"
        if ! $git_cmd pull origin "$REPO_BRANCH" --rebase >/dev/null 2>&1; then
            write_color_output "Pull failed, attempting to resolve..." "WARNING"
            
            # Try to continue rebase
            if ! $git_cmd rebase --continue >/dev/null 2>&1; then
                # Abort rebase and try merge instead
                $git_cmd rebase --abort >/dev/null 2>&1
                $git_cmd pull origin "$REPO_BRANCH" --strategy-option=theirs >/dev/null 2>&1
            fi
        fi
        
        # Restore stashed changes
        if [[ "$stashed" == "true" ]]; then
            write_color_output "Restoring local changes..." "INFO"
            if ! $git_cmd stash pop >/dev/null 2>&1; then
                write_color_output "Could not automatically restore all changes. Check 'git stash list' manually." "WARNING"
            fi
        fi
        
        write_color_output "Repository updated successfully!" "SUCCESS"
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
        write_color_output "Mapping arm64 to x64 for Android compatibility" "INFO"
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
        write_color_output "Executable not found for $arch" "ERROR"
        write_color_output "Checked paths:" "ERROR"
        write_color_output "  $INSTALL_DIR/android/$android_arch/GIProxy" "ERROR"
        write_color_output "  $INSTALL_DIR/linux/$arch/Release/GIProxy" "ERROR"
        write_color_output "  $INSTALL_DIR/linux/$arch/Debug/GIProxy" "ERROR"
        return 1
    fi
}

# Function to start GIProxy
start_giproxy() {
    local arch="$1"
    local exe_path
    
    if ! exe_path=$(get_executable_path "$arch"); then
        write_color_output "Cannot start GIProxy: executable not found" "ERROR"
        exit 1
    fi
    
    if [[ ! -f "$exe_path" ]]; then
        write_color_output "Cannot start GIProxy: executable not found at $exe_path" "ERROR"
        exit 1
    fi
    
    # Make executable if not already
    chmod +x "$exe_path"
    
    local working_dir="$(dirname "$exe_path")"
    
    write_color_output "Starting GIProxy..." "INFO"
    write_color_output "Executable: $exe_path" "INFO"
    write_color_output "Working Directory: $working_dir" "INFO"
    write_color_output "" "INFO"
    echo -e "${COLOR_SUCCESS}================================${COLOR_RESET}"
    echo -e "${COLOR_SUCCESS}     GIProxy Starting...        ${COLOR_RESET}"
    echo -e "${COLOR_SUCCESS}================================${COLOR_RESET}"
    echo ""
    
    local original_dir="$PWD"
    cd "$working_dir" || {
        write_color_output "Failed to change to working directory" "ERROR"
        exit 1
    }
    
    # Start the process
    if ! "$exe_path"; then
        write_color_output "Error running GIProxy" "ERROR"
        cd "$original_dir" || true
        exit 1
    fi
    
    cd "$original_dir" || true
}

# Main function
main() {
    echo ""
    echo -e "${COLOR_INFO}========================================${COLOR_RESET}"
    echo -e "${COLOR_INFO}   GIProxy Auto-Updater & Launcher     ${COLOR_RESET}"
    echo -e "${COLOR_INFO}========================================${COLOR_RESET}"
    echo ""
    
    # Detect architecture
    if [[ "$ARCHITECTURE" == "auto" ]]; then
        ARCHITECTURE=$(get_system_architecture)
        write_color_output "Detected architecture: $ARCHITECTURE" "INFO"
    fi
    
    # Validate architecture
    case "$ARCHITECTURE" in
        x64|x86|arm64)
            ;;
        *)
            write_color_output "Unsupported architecture: $ARCHITECTURE" "ERROR"
            write_color_output "Supported architectures: x64, x86, arm64" "ERROR"
            exit 1
            ;;
    esac
    
    # Get Git command
    local git_cmd
    git_cmd=$(get_git_command)
    write_color_output "Using Git: $git_cmd" "INFO"
    
    # Check if repository exists
    local repo_exists=false
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        repo_exists=true
    fi
    
    if [[ "$repo_exists" == "false" ]]; then
        write_color_output "Repository not found. Initializing..." "INFO"
        
        if ! initialize_repository "$git_cmd"; then
            write_color_output "Failed to initialize repository" "ERROR"
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
        write_color_output "Local version: $version_display" "INFO"
        
        if [[ "$FORCE_UPDATE" == "true" ]]; then
            write_color_output "Force update requested" "WARNING"
            update_repository "$git_cmd"
        else
            # Always try to update to get latest changes
            write_color_output "Checking for updates..." "INFO"
            update_repository "$git_cmd"
            
            local new_version
            new_version=$(get_local_version)
            if [[ -n "$new_version" && "$new_version" != "$local_version" ]]; then
                write_color_output "Updated from version $local_version to $new_version" "SUCCESS"
            else
                write_color_output "Already up to date" "SUCCESS"
            fi
        fi
    else
        write_color_output "Skipping update check" "WARNING"
    fi
    
    # Start GIProxy
    echo ""
    start_giproxy "$ARCHITECTURE"
}

# Error handling
set -e
trap 'write_color_output "Unexpected error occurred" "ERROR"; exit 1' ERR

# Run main function
main "$@"
