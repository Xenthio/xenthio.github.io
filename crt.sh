#!/bin/bash
#
# Pi CRT Toolkit - Blind Install Script
# Usage: curl -sL xenth.io/crt.sh | sudo bash
#
# Enables composite output for blind installs (no HDMI needed)
# then downloads and runs the full toolkit
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

# Find config.txt location
CONFIG="/boot/config.txt"
[[ -f "/boot/firmware/config.txt" ]] && CONFIG="/boot/firmware/config.txt"
echo "Config: $CONFIG"

# Check if composite already enabled
if grep -q "^enable_tvout=1" "$CONFIG" 2>/dev/null; then
    echo "Composite output already enabled in config"
    COMPOSITE_CONFIGURED=true
else
    COMPOSITE_CONFIGURED=false
fi

# Try tvservice first (works on legacy/fkms)
if command -v tvservice &>/dev/null; then
    echo ""
    echo "Enabling composite output immediately..."
    tvservice -c "NTSC 4:3" 2>/dev/null || true
    fbset -depth 8 2>/dev/null && fbset -depth 16 2>/dev/null
    sleep 1
    echo "Composite should now be active!"
fi

# Ensure composite is enabled in boot config
if [[ "$COMPOSITE_CONFIGURED" == "false" ]]; then
    echo ""
    echo "Adding composite output to boot config..."
    
    # Backup config
    cp "$CONFIG" "${CONFIG}.bak.$(date +%Y%m%d%H%M)" 2>/dev/null || true
    
    # Check for existing Pi4 section
    if grep -q "^\[pi4\]" "$CONFIG"; then
        # Add to existing [pi4] section
        sed -i '/^\[pi4\]/a enable_tvout=1\nsdtv_mode=0\nsdtv_aspect=1\nhdmi_ignore_hotplug=1' "$CONFIG"
    else
        # Add new section
        cat >> "$CONFIG" << 'EOF'

# Pi CRT Toolkit - Composite Output
[pi4]
enable_tvout=1
sdtv_mode=0
sdtv_aspect=1
hdmi_ignore_hotplug=1

[all]
EOF
    fi
    
    echo "Boot config updated!"
    
    # If tvservice wasn't available, we need a reboot
    if ! command -v tvservice &>/dev/null; then
        echo ""
        echo "═══════════════════════════════════════════════"
        echo "  REBOOT REQUIRED"
        echo "═══════════════════════════════════════════════"
        echo ""
        echo "tvservice is not available (full KMS driver)."
        echo "Composite output has been configured but requires"
        echo "a reboot to take effect."
        echo ""
        echo "After reboot, run this script again to continue"
        echo "installation, or run:"
        echo "  sudo crt-toolkit"
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
