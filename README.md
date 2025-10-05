# GIProxy - Growtopia Proxy

[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Android-lightgrey.svg)](https://github.com/GIProxy/bin)

> Unofficial Growtopia Proxy with auto-update functionality for Windows and Android (Termux)

## 🚀 Quick Start
> Don't forget to download installer script

### Windows

**PowerShell (Recommended):**
```powershell
.\GIProxy.ps1
```

**Batch File (Alternative):**
```cmd
GIProxy.bat
```

**First run creates a desktop shortcut automatically!**

### Android (Termux - Non-Root)

```bash
# Make script executable and run
chmod +x GIProxy.sh
./GIProxy.sh

# Git will be installed automatically if not present!
```

All launchers automatically:
- ✅ Detect your system architecture (x64, x86, arm64, armv7)
- ✅ **Install Git automatically** if not present (all platforms!)
- ✅ Clone the repository if it doesn't exist
- ✅ Check for updates and pull latest changes
- ✅ Preserve your local configuration files
- ✅ Auto-resolve conflicts during updates
- ✅ Launch the appropriate GIProxy executable

### Manual Installation

1. Download the appropriate executable for your architecture:
   - `win/x64/Release/GIProxy.exe` - For 64-bit Windows
   - `win/x86/Release/GIProxy.exe` - For 32-bit Windows
   - `win/arm64/Release/GIProxy.exe` - For ARM64 Windows

2. Run the executable from its directory:
   ```cmd
   cd win\x64\Release
   GIProxy.exe
   ```

## 📋 Launcher Options

### Windows (PowerShell)

```powershell
# Normal run with auto-update
.\GIProxy.ps1

# Skip update check (offline mode)
.\GIProxy.ps1 -SkipUpdate

# Force update even if version matches
.\GIProxy.ps1 -ForceUpdate

# Specify architecture manually
.\GIProxy.ps1 -Architecture x64

# Combine options
.\GIProxy.ps1 -Architecture arm64 -ForceUpdate
```

### Windows (Batch)

```cmd
REM Normal run with auto-update
GIProxy.bat

REM Skip update check
GIProxy.bat -SkipUpdate

REM Force update
GIProxy.bat -ForceUpdate

REM Specify architecture
GIProxy.bat -Architecture x64
```

### Android (Shell)

```bash
# Normal run with auto-update
./GIProxy.sh

# Skip update check (offline mode)
./GIProxy.sh -SkipUpdate

# Force update even if version matches
./GIProxy.sh -ForceUpdate

# Specify architecture manually
./GIProxy.sh -Architecture x64

# Combine options
./GIProxy.sh -Architecture arm64 -ForceUpdate
```

## ⚙️ Configuration

Edit `config.txt` to customize your proxy settings:

```ini
# Auto-detect real server (recommended)
realServerHost|auto
realServerPort|17004

# Proxy server settings
proxyServerHost|127.0.0.1
proxyServerPort|17091

# Debugging options
debug|1
deepDebug|0
writeDebug|0

# Discord Rich Presence
enableDiscordPresence|1
presenceDescription|Playing via GIProxy
presenceButton|Visit Server|https://your-url.com
```

**Note:** Your configuration changes are preserved during auto-updates!

## 🔧 Requirements

### Windows
- **OS:** Windows 7/8/10/11 (x64, x86, or ARM64)
- **Git:** Auto-installed by launcher if not present
- **PowerShell:** 5.1 or later (included in Windows 10+) - for `.ps1` launcher

### Android (Termux)
- **App:** Termux from F-Droid (not Play Store version)
- **Git:** Auto-installed by launcher if not present
- **Architecture:** ARM64 or ARMv7
- **Storage:** ~100MB free space for repository

## 📁 Directory Structure

```
bin/
├── GIProxy.ps1          # PowerShell launcher (Windows)
├── GIProxy.bat          # Batch launcher (Windows)
├── GIProxy.sh           # Shell launcher (Linux/macOS/Android)
├── config.txt           # User configuration
├── config.dev.txt       # Developer configuration
├── version              # Current version
├── items.dat            # Growtopia item database
├── hosts                # System hosts file backup
├── win/                 # Windows executables
│   ├── x64/
│   │   ├── Debug/
│   │   └── Release/     # (recommended)
│   ├── x86/
│   └── arm64/
├── linux/               # Linux executables
│   ├── x64/
│   ├── x86/
│   └── arm64/
├── macos/               # macOS executables
│   ├── x64/             # Intel
│   └── arm64/           # Apple Silicon
└── android/             # Android (Termux) executables
    ├── arm64/
    └── armv7/
```

## 🔄 Auto-Update System

The PowerShell launcher includes an intelligent auto-update system:

1. **Version Check:** Compares local version with remote repository
2. **Smart Pull:** Fetches latest changes with conflict resolution
3. **Data Preservation:** Stashes local changes before updating
4. **Conflict Resolution:** Automatically resolves merge conflicts
5. **Config Safety:** Never overwrites your custom configurations

### Update Process Flow

```
Check Repository → Fetch Updates → Stash Local Changes → 
Pull with Rebase → Restore Stashed Changes → Launch
```

## 🛠️ Troubleshooting

### Executable Not Found
- Ensure you're running the correct launcher for your OS
- Try running with `-Architecture x64` explicitly
- Check if executable exists in the appropriate platform folder
- Make sure the script has execute permissions (Linux/macOS/Android): `chmod +x GIProxy.sh`

### Update Failures
- **Windows:** Run `.\GIProxy.ps1 -ForceUpdate` or `GIProxy.bat -ForceUpdate`
- **Android:** Run `./GIProxy.sh -ForceUpdate`
- Manually delete `GIProxy/.git` folder and re-run
- Check your internet connection

### Git Issues
- **All Platforms:** The launcher automatically installs Git if not found
- **Windows:** Git Portable is downloaded and extracted automatically
- **Android/Termux:** Installs via `pkg install git` automatically
- **Manual Install:** If auto-install fails, install Git manually and re-run the launcher

### Configuration Lost
- Check `git stash list` in the GIProxy folder
- Your configs are stashed before updates
- Run `git stash pop` to restore manually

### Permission Denied (Android)
```bash
# Make the launcher executable
chmod +x GIProxy.sh

# Make the GIProxy binary executable
chmod +x GIProxy/linux/x64/Release/GIProxy  # or appropriate path
```

### Termux Specific Issues
- **Storage Access:** Run `termux-setup-storage` to grant storage permissions
- **Git Clone Fails:** Ensure you have stable internet connection
- **Executable Crashes:** Make sure you're using Termux from F-Droid, not Play Store
- **Architecture Mismatch:** Check your device architecture with `uname -m`

## 🔐 Security Notes

- The proxy intercepts game traffic for debugging purposes
- All external communications use E2EE encryption
- Your HWID is used for authentication with external services
- Configuration files may contain sensitive data - keep them private

## 📝 Development

### Developer Configuration

Edit `config.dev.txt` for development settings:

```ini
relay|https://localhost:17002
relayKey|your-api-key
auth|https://localhost:17000
authKey|your-api-key
websocket|wss://localhost:17001
```

### Debug Mode

Enable detailed logging in `config.txt`:

```ini
debug|1           # Enable debug logs
deepDebug|1       # Enable deep packet inspection
writeDebug|1      # Write logs to debug/ folder
```

Debug logs are saved to:
- `win/{arch}/{Debug|Release}/debug/` - Packet dumps
- `win/{arch}/{Debug|Release}/logs/` - General logs

## 📞 Support

- **Discord:** [Join our server](https://dsc.gg/free-growtopia-proxy)
- **Issues:** [GitHub Issues](https://github.com/GIProxy/bin/issues)
- **Wiki:** [Documentation](https://github.com/GIProxy/bin/wiki)

## ⚖️ License

This project is provided as-is for educational purposes. Use at your own risk.

## 🤝 Contributing

This is a binary distribution repository. For source code contributions, please visit the main GIProxy repository.

---

**Made with ❤️ by the GIProxy Team**