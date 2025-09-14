# --- Run the binary based on architecture ---
ARCH_TYPE=$(uname -m)
log_message "Detected architecture: $ARCH_TYPE"

case "$ARCH_TYPE" in
  # ARM64 (Android 64-bit)
  aarch64)
    log_message "Selecting arm64 binary."
    EXE_PATH="$CLONE_PATH/android/x64/GIProxy"
    ;;
  # x86 32-bit (bisa "x86" atau "i686")
  x86|i686)
    log_message "Selecting x86 binary."
    EXE_PATH="$CLONE_PATH/android/x86/GIProxy"
    ;;
  # x86_64 (64-bit desktop / emulator)
  x86_64|amd64)
    log_message "Selecting x64 binary."
    EXE_PATH="$CLONE_PATH/android/x64/GIProxy"
    ;;
  *)
    log_message "ERROR: Unsupported or unrecognized architecture '$ARCH_TYPE'."
    log_message "Please verify your system architecture or the availability of the binary."
    exit 1
    ;;
esac
