#!/bin/bash

# ========================================
# GIProxy Auto-Updater and Launcher (SH)
# ========================================
# Version: 1.0.0
# Author: GIProxy Team

set -e

# Configuration
REPO_URL="https://github.com/GIProxy/bin.git"
REPO_BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$SCRIPT_DIR/GIProxy"
VERSION_FILE="version"
SKIP_UPDATE=0
FORCE_UPDATE=0
FORCE_ARCH=""

# Colors
COLOR_INFO="\033[0;36m"
COLOR_SUCCESS="\033[0;32m"
COLOR_WARNING="\033[0;33m"
COLOR_ERROR="\033[0;31m"
COLOR_RESET="\033[0m"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -SkipUpdate|--skip-update)
            SKIP_UPDATE=1
            shift
            ;;
        -ForceUpdate|--force-update)
            FORCE_UPDATE=1
            shift
            ;;
        -Architecture|--architecture)
            FORCE_ARCH="$2"
            shift 2
            ;;
        *)
            echo -e "${COLOR_ERROR}[ERROR] Unknown option: $1${COLOR_RESET}"
            exit 1
            ;;
    esac
done

# Helper functions
log_info() {
    echo -e "${COLOR_INFO}[INFO] $1${COLOR_RESET}"
}

log_success() {
    echo -e "${COLOR_SUCCESS}[SUCCESS] $1${COLOR_RESET}"
}

log_warning() {
    echo -e "${COLOR_WARNING}[WARNING] $1${COLOR_RESET}"
}

log_error() {
    echo -e "${COLOR_ERROR}[ERROR] $1${COLOR_RESET}"
}

# Detect platform and architecture
detect_platform() {
    local platform=""
    local arch=""
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        platform="linux"
    elif [[ "$OSTYPE" == "linux-android"* ]]; then
        platform="android"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        platform="macos"
    else
        platform="unknown"
    fi
    
    # Detect architecture
    if [ -n "$FORCE_ARCH" ]; then
        arch="$FORCE_ARCH"
    else
        local machine=$(uname -m)
        case $machine in
            x86_64|amd64)
                arch="x64"
                ;;
            i386|i686)
                arch="x86"
                ;;
            aarch64|arm64)
                arch="arm64"
                ;;
            armv7l)
                arch="armv7"
                ;;
            *)
                arch="x64"
                ;;
        esac
    fi
    
    echo "$platform:$arch"
}

# Check if Git is installed
check_git() {
    if command -v git &> /dev/null; then
        return 0
    fi
    return 1
}

# Install Git
install_git() {
    log_warning "Git is not installed. Attempting automatic installation..."
    echo ""
    
    local install_success=0
    
    if [[ "$OSTYPE" == "linux-android"* ]]; then
        # Termux
        log_info "Installing Git via Termux package manager..."
        if pkg install -y git &> /dev/null; then
            install_success=1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux distributions
        if command -v apt-get &> /dev/null; then
            log_info "Installing Git via apt-get..."
            if sudo apt-get update &> /dev/null && sudo apt-get install -y git &> /dev/null; then
                install_success=1
            fi
        elif command -v dnf &> /dev/null; then
            log_info "Installing Git via dnf..."
            if sudo dnf install -y git &> /dev/null; then
                install_success=1
            fi
        elif command -v pacman &> /dev/null; then
            log_info "Installing Git via pacman..."
            if sudo pacman -S --noconfirm git &> /dev/null; then
                install_success=1
            fi
        elif command -v yum &> /dev/null; then
            log_info "Installing Git via yum..."
            if sudo yum install -y git &> /dev/null; then
                install_success=1
            fi
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            log_info "Installing Git via Homebrew..."
            if brew install git &> /dev/null; then
                install_success=1
            fi
        else
            log_info "Installing Git via Xcode Command Line Tools..."
            if xcode-select --install &> /dev/null; then
                log_warning "Xcode tools installation started. Please complete the installation and run this script again."
                exit 0
            fi
        fi
    fi
    
    if [ $install_success -eq 1 ]; then
        log_success "Git installed successfully!"
        echo ""
        return 0
    else
        log_error "Failed to install Git automatically!"
        echo ""
        echo "Please install Git manually using one of the following commands:"
        echo ""
        
        if [[ "$OSTYPE" == "linux-android"* ]]; then
            echo "  Termux:     pkg install git"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "  Ubuntu/Debian:  sudo apt-get install git"
            echo "  Fedora:         sudo dnf install git"
            echo "  Arch:           sudo pacman -S git"
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  macOS (Homebrew):  brew install git"
            echo "  macOS (Xcode):     xcode-select --install"
        fi
        
        echo ""
        exit 1
    fi
}

# Get local version
get_local_version() {
    local version_file="$INSTALL_DIR/$VERSION_FILE"
    if [ -f "$version_file" ]; then
        cat "$version_file" | tr -d '[:space:]'
    else
        echo ""
    fi
}

# Initialize repository
initialize_repository() {
    log_info "Cloning repository from $REPO_URL..."
    
    if git clone --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"; then
        log_success "Repository cloned successfully!"
        return 0
    else
        log_error "Failed to clone repository"
        return 1
    fi
}

# Update repository
update_repository() {
    log_info "Updating repository..."
    
    cd "$INSTALL_DIR"
    
    # Fetch latest changes
    if ! git fetch origin "$REPO_BRANCH" 2>&1 | grep -v "^$"; then
        log_error "Git fetch failed"
        cd "$SCRIPT_DIR"
        return 1
    fi
    
    # Stash local changes
    log_info "Preserving local changes..."
    git stash push -m "Auto-stash before update $(date)" &> /dev/null
    local stashed=$?
    
    # Pull with rebase
    log_info "Pulling latest changes..."
    if ! git pull origin "$REPO_BRANCH" --rebase &> /dev/null; then
        log_warning "Pull failed, attempting to resolve..."
        git rebase --abort &> /dev/null
        git pull origin "$REPO_BRANCH" --strategy-option=theirs &> /dev/null
    fi
    
    # Restore stashed changes
    if [ $stashed -eq 0 ]; then
        log_info "Restoring local changes..."
        if ! git stash pop &> /dev/null; then
            log_warning "Could not automatically restore all changes. Check 'git stash list' manually."
        fi
    fi
    
    log_success "Repository updated successfully!"
    cd "$SCRIPT_DIR"
    return 0
}

# Get executable path
get_executable_path() {
    local platform="$1"
    local arch="$2"
    local exe_path=""
    local build_type=""
    
    # Determine build type and path based on platform
    if [ "$platform" == "android" ]; then
        # Android executables
        if [ -f "$INSTALL_DIR/android/$arch/GIProxy" ]; then
            exe_path="$INSTALL_DIR/android/$arch/GIProxy"
        else
            log_error "Executable not found for Android $arch"
            log_error "Expected path: $INSTALL_DIR/android/$arch/GIProxy"
            return 1
        fi
    elif [ "$platform" == "linux" ]; then
        # Linux executables
        if [ -f "$INSTALL_DIR/linux/$arch/Debug/GIProxy" ]; then
            build_type="Debug"
        else
            build_type="Release"
        fi
        exe_path="$INSTALL_DIR/linux/$arch/$build_type/GIProxy"
    elif [ "$platform" == "macos" ]; then
        # macOS executables
        if [ -f "$INSTALL_DIR/macos/$arch/Debug/GIProxy" ]; then
            build_type="Debug"
        else
            build_type="Release"
        fi
        exe_path="$INSTALL_DIR/macos/$arch/$build_type/GIProxy"
    else
        log_error "Unsupported platform: $platform"
        return 1
    fi
    
    if [ -f "$exe_path" ]; then
        echo "$exe_path"
        return 0
    else
        log_error "Executable not found for $platform $arch ($build_type)"
        log_error "Expected path: $exe_path"
        return 1
    fi
}

# Start GIProxy
start_giproxy() {
    local platform="$1"
    local arch="$2"
    
    local exe_path=$(get_executable_path "$platform" "$arch")
    if [ $? -ne 0 ]; then
        log_error "Cannot start GIProxy: executable not found"
        exit 1
    fi
    
    # Make executable if not already
    chmod +x "$exe_path" 2>/dev/null
    
    local working_dir=$(dirname "$exe_path")
    
    log_info "Starting GIProxy..."
    log_info "Executable: $exe_path"
    log_info "Working Directory: $working_dir"
    echo ""
    echo -e "${COLOR_SUCCESS}================================${COLOR_RESET}"
    echo -e "${COLOR_SUCCESS}     GIProxy Starting...        ${COLOR_RESET}"
    echo -e "${COLOR_SUCCESS}================================${COLOR_RESET}"
    echo ""
    
    cd "$working_dir"
    "$exe_path"
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo ""
        log_error "GIProxy exited with error code $exit_code"
    fi
    
    cd "$SCRIPT_DIR"
    return $exit_code
}

# Main execution
main() {
    echo ""
    echo -e "${COLOR_INFO}========================================${COLOR_RESET}"
    echo -e "${COLOR_INFO}   GIProxy Auto-Updater & Launcher     ${COLOR_RESET}"
    echo -e "${COLOR_INFO}========================================${COLOR_RESET}"
    echo ""
    
    # Detect platform and architecture
    local platform_info=$(detect_platform)
    local platform="${platform_info%%:*}"
    local arch="${platform_info##*:}"
    
    log_info "Platform: $platform"
    log_info "Architecture: $arch"
    echo ""
    
    # Check Git installation
    if ! check_git; then
        install_git
    fi
    
    log_info "Using Git: $(which git)"
    echo ""
    
    # Check if repository exists
    if [ ! -d "$INSTALL_DIR/.git" ]; then
        log_info "Repository not found. Initializing..."
        if ! initialize_repository; then
            log_error "Failed to initialize repository"
            exit 1
        fi
    elif [ $SKIP_UPDATE -eq 0 ]; then
        # Check version
        local local_version=$(get_local_version)
        if [ -z "$local_version" ]; then
            log_info "Local version: unknown"
        else
            log_info "Local version: $local_version"
        fi
        
        if [ $FORCE_UPDATE -eq 1 ]; then
            log_warning "Force update requested"
            update_repository
        else
            log_info "Checking for updates..."
            update_repository
            
            local new_version=$(get_local_version)
            if [ -n "$new_version" ] && [ "$new_version" != "$local_version" ]; then
                log_success "Updated from version $local_version to $new_version"
            else
                log_success "Already up to date"
            fi
        fi
    else
        log_warning "Skipping update check"
    fi
    
    # Start GIProxy
    echo ""
    start_giproxy "$platform" "$arch"
}

# Run main function
main "$@"
