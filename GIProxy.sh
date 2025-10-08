#!/bin/bash

# ========================================
# GIProxy Auto-Updater and Launcher (SH)
# ========================================
# Version: 2.0.0
# Author: GIProxy Team
# Optimized for Termux Android Environment

set -e

# Configuration
REPO_URL="https://github.com/GIProxy/bin.git"
REPO_BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="version"
SKIP_UPDATE=0
FORCE_UPDATE=0
FORCE_ARCH=""

# Check if we're already in the repository (version file exists)
if [ -f "$SCRIPT_DIR/$VERSION_FILE" ]; then
    INSTALL_DIR="$SCRIPT_DIR"
    IN_REPO=1
else
    INSTALL_DIR="$SCRIPT_DIR/GIProxy"
    IN_REPO=0
fi

# Get the directory where this script is located (bin folder)
BIN_DIR="$INSTALL_DIR"

# Colors for output
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

# Detect Android architecture for Termux
detect_android_arch() {
    local machine=$(uname -m)
    local arch=""
    
    if [ -n "$FORCE_ARCH" ]; then
        arch="$FORCE_ARCH"
    else
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
            armv7l|armv7)
                arch="armv7"
                ;;
            *)
                # Default to x64 if unknown
                arch="x64"
                ;;
        esac
    fi
    
    echo "$arch"
}

# Detect platform and architecture (legacy support for other platforms)
detect_platform() {
    local platform=""
    local arch=""
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        platform="linux"
    elif [[ "$OSTYPE" == "linux-android"* ]] || check_termux_environment; then
        platform="android"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        platform="macos"
    else
        platform="android"  # Default to android for Termux
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

# Check if running in Termux
check_termux_environment() {
    if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ] || [[ "$PREFIX" == *"termux"* ]]; then
        return 0
    fi
    return 1
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
    
    if [[ "$OSTYPE" == "linux-android"* ]] || check_termux_environment; then
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
        
        if check_termux_environment; then
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

# Fix Android binary permissions after update
fix_android_permissions() {
    log_info "Setting executable permissions for Android binaries..."
    
    # Set permissions for all Android architectures
    for arch_dir in "$INSTALL_DIR"/android/*/; do
        if [ -d "$arch_dir" ]; then
            local binary="$arch_dir/GIProxy"
            if [ -f "$binary" ]; then
                chmod +x "$binary" 2>/dev/null
                local arch_name=$(basename "$arch_dir")
                log_success "Set executable permission for android/$arch_name/GIProxy"
            fi
        fi
    done
}

# Check if GIProxy executable exists for detected architecture
find_giproxy_executable() {
    local arch="$1"
    local exe_path="$BIN_DIR/android/$arch/GIProxy"
    
    if [ -f "$exe_path" ]; then
        echo "$exe_path"
        return 0
    fi
    
    # Fallback: try other architectures
    for fallback_arch in x64 x86 arm64 armv7; do
        if [ "$fallback_arch" != "$arch" ]; then
            local fallback_path="$BIN_DIR/android/$fallback_arch/GIProxy"
            if [ -f "$fallback_path" ]; then
                log_warning "Using fallback architecture: $fallback_arch (detected: $arch)"
                echo "$fallback_path"
                return 0
            fi
        fi
    done
    
    return 1
}

# Get executable path (enhanced version supporting all platforms)
get_executable_path() {
    local platform="$1"
    local arch="$2"
    local exe_path=""
    local build_type=""
    
    # Determine build type and path based on platform
    if [ "$platform" == "android" ]; then
        # Android executables - use enhanced detection
        exe_path=$(find_giproxy_executable "$arch")
        if [ $? -eq 0 ]; then
            echo "$exe_path"
            return 0
        else
            log_error "Executable not found for Android $arch"
            log_error "Expected path: $INSTALL_DIR/android/$arch/GIProxy"
            return 1
        fi
    elif [ "$platform" == "linux" ]; then
        # Linux executables
        if [ -f "$INSTALL_DIR/linux/$arch/Release/GIProxy" ]; then
            build_type="Release"
        else
            build_type="Debug"
        fi
        exe_path="$INSTALL_DIR/linux/$arch/$build_type/GIProxy"
    elif [ "$platform" == "macos" ]; then
        # macOS executables
        if [ -f "$INSTALL_DIR/macos/$arch/Release/GIProxy" ]; then
            build_type="Release"
        else
            build_type="Debug"
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

# Check if running in Termux
check_termux_environment() {
    if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ] || [[ "$PREFIX" == *"termux"* ]]; then
        return 0
    fi
    return 1
}

# Start GIProxy (optimized for Termux Android with main thread execution)
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
    
    # For Termux Android optimization: use bin directory as working directory
    if [ "$platform" == "android" ] && check_termux_environment; then
        log_info "Termux Android detected - optimizing execution..."
        
        # Set working directory to bin folder
        log_info "Setting working directory to: $BIN_DIR"
        cd "$BIN_DIR"
        
        # Verify required files exist
        if [ ! -f "config.txt" ]; then
            log_warning "config.txt not found in bin directory"
        fi
        
        if [ ! -f "items.dat" ]; then
            log_warning "items.dat not found in bin directory"
        fi
        
        # Get relative path for execution
        local relative_path=$(realpath --relative-to="$BIN_DIR" "$exe_path")
        
        log_info "Starting GIProxy..."
        log_info "Executable: $exe_path"
        log_info "Relative Path: $relative_path"
        log_info "Working Dir: $BIN_DIR"
        log_info "Architecture: $arch"
        echo ""
        echo -e "${COLOR_SUCCESS}================================${COLOR_RESET}"
        echo -e "${COLOR_SUCCESS}     GIProxy is starting...      ${COLOR_RESET}"
        echo -e "${COLOR_SUCCESS}     (Termux Optimized)         ${COLOR_RESET}"
        echo -e "${COLOR_SUCCESS}================================${COLOR_RESET}"
        echo ""
        
        # Execute GIProxy in main thread with relative path
        exec "./$relative_path"
    else
        # Standard execution for other platforms
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
    fi
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
    
    # Check if running in Termux
    if check_termux_environment; then
        log_success "Termux environment detected"
    fi
    echo ""
    
    # Check Git installation (skip for Termux if not needed for updates)
    if [ $SKIP_UPDATE -eq 0 ]; then
        if ! check_git; then
            install_git
        fi
        
        log_info "Using Git: $(command -v git)"
        echo ""
    fi
    
    # Check if we're already in the repository or need to clone
    if [ $IN_REPO -eq 1 ]; then
        log_info "Running from repository directory"
        
        if [ $SKIP_UPDATE -eq 0 ]; then
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
                
                # Fix Android permissions after update
                if [ "$platform" == "android" ]; then
                    fix_android_permissions
                fi
            else
                log_info "Checking for updates..."
                update_repository
                
                local new_version=$(get_local_version)
                if [ -n "$new_version" ] && [ "$new_version" != "$local_version" ]; then
                    log_success "Updated from version $local_version to $new_version"
                    
                    # Fix Android permissions after update
                    if [ "$platform" == "android" ]; then
                        fix_android_permissions
                    fi
                else
                    log_success "Already up to date"
                fi
            fi
        else
            log_warning "Skipping update check"
        fi
    elif [ ! -d "$INSTALL_DIR/.git" ] && [ $SKIP_UPDATE -eq 0 ]; then
        log_info "Repository not found. Initializing..."
        if ! initialize_repository; then
            log_error "Failed to initialize repository"
            exit 1
        fi
        
        # Fix Android permissions after initial clone
        if [ "$platform" == "android" ]; then
            fix_android_permissions
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
            
            # Fix Android permissions after update
            if [ "$platform" == "android" ]; then
                fix_android_permissions
            fi
        else
            log_info "Checking for updates..."
            update_repository
            
            local new_version=$(get_local_version)
            if [ -n "$new_version" ] && [ "$new_version" != "$local_version" ]; then
                log_success "Updated from version $local_version to $new_version"
                
                # Fix Android permissions after update
                if [ "$platform" == "android" ]; then
                    fix_android_permissions
                fi
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

# Trap signals to ensure clean exit
trap 'echo ""; log_info "Script interrupted"; exit 130' INT
trap 'echo ""; log_info "Script terminated"; exit 143' TERM

# Run main function
main "$@"
}
