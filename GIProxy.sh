#!/bin/bash

# Termux script to update GIProxy-bin and run the binary
#
# This script automatically installs required packages.

set -e

# --- Configuration ---
REPO_URL="https://github.com/GTPSHAX/GIProxy-bin.git"
REMOTE_VERSION_URL="https://raw.githubusercontent.com/GTPSHAX/GIProxy-bin/main/version"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CLONE_PATH="$SCRIPT_DIR/GIProxy-bin"
LOCAL_VERSION_FILE="$CLONE_PATH/version"
EXE_ARG=""

# --- Functions ---
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

get_remote_version() {
  # Use wget to fetch the remote version file
  wget -qO- "$REMOTE_VERSION_URL" 2>/dev/null || { log_message "Warning: Failed to fetch remote version."; return 1; }
}

# --- Main Script ---
log_message "Starting GIProxy update & run workflow for Termux."

# --- Check and Install Required Packages ---
REQUIRED_PKGS="git wget"
log_message "Checking for required packages: $REQUIRED_PKGS"

for pkg in $REQUIRED_PKGS; do
  if ! command -v "$pkg" &> /dev/null; then
    log_message "Package '$pkg' not found. Installing..."
    pkg install "$pkg" -y
    if [ $? -ne 0 ]; then
      log_message "ERROR: Failed to install '$pkg'. Please try running 'pkg install $pkg' manually."
      exit 1
    fi
  fi
done

log_message "All required packages are installed."

# --- Git Operations ---
if [ ! -d "$CLONE_PATH" ]; then
  log_message "Repository not found. Cloning to '$CLONE_PATH'..."
  git clone "$REPO_URL" "$CLONE_PATH" || { log_message "ERROR: Git clone failed."; exit 1; }
else
  # Compare remote vs local version
  REMOTE_VERSION=$(get_remote_version)
  LOCAL_VERSION=""
  if [ -f "$LOCAL_VERSION_FILE" ]; then
    LOCAL_VERSION=$(cat "$LOCAL_VERSION_FILE" | tr -d '\n' | tr -d '\r')
  fi

  if [ -n "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    log_message "Version change detected (remote: '$REMOTE_VERSION', local: '$LOCAL_VERSION'). Updating repository..."
    cd "$CLONE_PATH"
    git fetch origin main || { log_message "ERROR: Git fetch failed."; exit 1; }
    git reset --hard origin/main || { log_message "ERROR: Git reset failed."; exit 1; }
    cd "$SCRIPT_DIR"
  else
    log_message "Repository is up to date."
  fi
fi

# --- Run the binary based on architecture ---
ARCH_TYPE=$(uname -m)
log_message "Detected architecture: $ARCH_TYPE"

case "$ARCH_TYPE" in
  aarch64)
    log_message "Selecting arm64 binary."
    EXE_PATH="$CLONE_PATH/android/x64/GIProxy"
    ;;
  x86|i686)
    log_message "Selecting x86 binary."
    EXE_PATH="$CLONE_PATH/android/x86/GIProxy"
    ;;
  x86_64|amd64)
    log_message "Selecting x64 binary."
    EXE_PATH="$CLONE_PATH/android/x64/GIProxy"
    ;;
  *)
    log_message "ERROR: Unsupported or unrecognized architecture '$ARCH_TYPE'."
    exit 1
    ;;
esac

if [ ! -f "$EXE_PATH" ]; then
  log_message "ERROR: Binary not found at $EXE_PATH."
  exit 1
fi

chmod +x "$EXE_PATH"

BIN_DIR="$(dirname "$EXE_PATH")"
log_message "Launching GIProxy from $BIN_DIR with arg: $EXE_ARG"
env -C "$BIN_DIR" ./$(basename "$EXE_PATH") "$EXE_ARG"

log_message "Script finished."
exit 0
