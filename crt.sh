#!/bin/bash
#
# Pi CRT Toolkit - Blind Install Script
# Usage: curl -sL xenth.io/crt.sh | sudo bash
#
# Enables composite output for blind installs (no HDMI needed)
# then downloads and runs the full toolkit.
#
# Preserves your current driver (Legacy/FKMS/KMS) unless you change it.
#

set -e

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║    Pi CRT Toolkit - Blind Install          ║"
echo "║    xenth.io/crt.sh                         ║"
echo "╚════════════════════════════════════════════╝"
echo ""

# Must be root
if [[ $EUID -ne 0 ]]; then
    echo "Error: Run with sudo"
    echo "  curl -sL xenth.io/crt.sh | sudo bash"
    exit 1
fi

# Detect Pi model
if [[ -f /proc/device-tree/model ]]; then
    PI_MODEL=$(tr -d '\0' < /proc/device-tree/model)
    echo "Detected: $PI_MODEL"
    
    if [[ "$PI_MODEL" == *"Pi 5"* ]]; then
        echo "Error: Raspberry Pi 5 does not have composite output!"
        exit 1
    fi
else
    echo "Warning: Could not detect Pi model"
fi

# Detect OS
OS_CODENAME=$(grep VERSION_CODENAME /etc/os-release 2>/dev/null | cut -d= -f2 || echo "unknown")
echo "OS: $OS_CODENAME"

# Find config.txt location (Bookworm+ uses /boot/firmware/)
CONFIG="/boot/config.txt"
[[ -f "/boot/firmware/config.txt" ]] && CONFIG="/boot/firmware/config.txt"
echo "Config: $CONFIG"

# Detect current driver
CURRENT_DRIVER="unknown"
if grep -qE "^dtoverlay=vc4-fkms-v3d" "$CONFIG" 2>/dev/null; then
    CURRENT_DRIVER="fkms"
elif grep -qE "^dtoverlay=vc4-kms-v3d" "$CONFIG" 2>/dev/null; then
    CURRENT_DRIVER="kms"
elif command -v tvservice &>/dev/null && tvservice -s &>/dev/null; then
    CURRENT_DRIVER="legacy"
fi
echo "Driver: $CURRENT_DRIVER"

# Check if composite already enabled
COMPOSITE_ENABLED=false
case "$CURRENT_DRIVER" in
    kms)
        # KMS needs ,composite parameter
        if grep -qE "dtoverlay=vc4-kms-v3d,.*composite" "$CONFIG" 2>/dev/null; then
            COMPOSITE_ENABLED=true
        fi
        ;;
    fkms|legacy)
        # FKMS/Legacy needs enable_tvout=1
        if grep -q "^enable_tvout=1" "$CONFIG" 2>/dev/null; then
            COMPOSITE_ENABLED=true
        fi
        ;;
esac

echo ""

# Try tvservice for immediate composite (FKMS/Legacy only)
if command -v tvservice &>/dev/null; then
    echo "Enabling composite output immediately via tvservice..."
    tvservice -c "NTSC 4:3" 2>/dev/null || true
    fbset -depth 8 2>/dev/null && fbset -depth 16 2>/dev/null
    sleep 1
    echo "Composite should now be active!"
fi

# Enable composite in boot config if needed
if [[ "$COMPOSITE_ENABLED" == "false" ]]; then
    echo ""
    echo "Configuring composite output in boot config..."
    
    # Backup config
    cp "$CONFIG" "${CONFIG}.bak.$(date +%Y%m%d%H%M)" 2>/dev/null || true
    
    case "$OS_CODENAME" in
        trixie|bookworm)
            # Trixie/Bookworm: Add ,composite to KMS overlay
            if grep -qE "^dtoverlay=vc4-kms-v3d$" "$CONFIG"; then
                # Plain kms overlay - add composite
                sed -i 's/^dtoverlay=vc4-kms-v3d$/dtoverlay=vc4-kms-v3d,composite/' "$CONFIG"
                echo "Added ,composite to vc4-kms-v3d overlay"
            elif grep -qE "^dtoverlay=vc4-kms-v3d," "$CONFIG"; then
                # KMS with options - add composite if not present
                if ! grep -qE "composite" "$CONFIG"; then
                    sed -i 's/^dtoverlay=vc4-kms-v3d,/dtoverlay=vc4-kms-v3d,composite,/' "$CONFIG"
                    echo "Added composite to existing vc4-kms-v3d overlay"
                fi
            else
                # No KMS overlay - add full config
                echo "" >> "$CONFIG"
                echo "[pi4]" >> "$CONFIG"
                echo "dtoverlay=vc4-kms-v3d,composite" >> "$CONFIG"
                echo "hdmi_ignore_hotplug=1" >> "$CONFIG"
                echo "[all]" >> "$CONFIG"
                echo "Added composite KMS config"
            fi
            ;;
        *)
            # Older OS: Use enable_tvout
            if ! grep -q "^enable_tvout=1" "$CONFIG"; then
                echo "" >> "$CONFIG"
                echo "# CRT Toolkit - Composite Output" >> "$CONFIG"
                echo "enable_tvout=1" >> "$CONFIG"
                echo "hdmi_ignore_hotplug=1" >> "$CONFIG"
                echo "Added enable_tvout=1"
            fi
            ;;
    esac
    
    # Check if we need a reboot (no tvservice available)
    if ! command -v tvservice &>/dev/null; then
        echo ""
        echo "═══════════════════════════════════════════════"
        echo "  REBOOT REQUIRED"
        echo "═══════════════════════════════════════════════"
        echo ""
        echo "Composite output has been configured but requires"
        echo "a reboot to take effect (Full KMS driver)."
        echo ""
        echo "After reboot, run: sudo crt-toolkit"
        echo ""
        read -p "Reboot now? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "Rebooting in 3 seconds..."
            sleep 3
            reboot
        fi
        exit 0
    fi
fi

echo ""
echo "Downloading Pi CRT Toolkit..."
echo ""

# Install git if needed
if ! command -v git &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq git
fi

# Install libdrm-tests for modetest (KMS needs this)
if [[ "$CURRENT_DRIVER" == "kms" ]] && ! command -v modetest &>/dev/null; then
    echo "Installing DRM tools for KMS..."
    apt-get install -y -qq libdrm-tests 2>/dev/null || true
fi

# Download toolkit
INSTALL_DIR="/opt/crt-toolkit"
if [[ -d "$INSTALL_DIR" ]]; then
    cd "$INSTALL_DIR"
    git fetch origin 2>/dev/null
    git reset --hard origin/main 2>/dev/null
else
    git clone --depth 1 https://github.com/Xenthio/pi-crt-toolkit.git "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/crt-toolkit.sh"
chmod +x "$INSTALL_DIR/lib/"*.sh 2>/dev/null || true
ln -sf "$INSTALL_DIR/crt-toolkit.sh" /usr/local/bin/crt-toolkit

echo ""
echo "═══════════════════════════════════════════════"
echo "  Download complete!"
echo "═══════════════════════════════════════════════"
echo ""

# Launch the toolkit
exec "$INSTALL_DIR/crt-toolkit.sh"
