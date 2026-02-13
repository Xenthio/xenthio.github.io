#!/bin/bash
#
# Pi CRT Toolkit - Blind Install Script
# Usage: curl -sL xenth.io/crt.sh | sudo bash
#
# This script enables composite output FIRST (for blind installs)
# then downloads and runs the full toolkit
#

# Enable composite output immediately (for blind install)
enable_composite_now() {
    # Check if tvservice exists
    if ! command -v tvservice &>/dev/null; then
        echo "tvservice not found - composite may not be available"
        return 1
    fi
    
    # Switch to 480i NTSC immediately
    echo "Enabling composite output (480i)..."
    tvservice -c "NTSC 4:3" 2>/dev/null
    
    # Refresh framebuffer
    fbset -depth 8 2>/dev/null
    fbset -depth 16 2>/dev/null
    
    # Give display time to sync
    sleep 2
    
    echo "Composite output enabled!"
}

# Ensure composite is enabled in boot config for next reboot
enable_composite_boot() {
    local config="/boot/config.txt"
    [[ -f "/boot/firmware/config.txt" ]] && config="/boot/firmware/config.txt"
    
    # Check if enable_tvout already set
    if ! grep -q "^enable_tvout=1" "$config" 2>/dev/null; then
        echo "Adding enable_tvout=1 to $config..."
        echo "" >> "$config"
        echo "# Added by CRT Toolkit blind install" >> "$config"
        echo "enable_tvout=1" >> "$config"
        echo "hdmi_ignore_hotplug=1" >> "$config"
    fi
}

# Main
main() {
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
    
    # Enable composite NOW so you can see what's happening
    enable_composite_now
    
    # Ensure it's enabled for boot too
    enable_composite_boot
    
    echo ""
    echo "Downloading Pi CRT Toolkit..."
    echo ""
    
    # Download and run the main installer
    curl -sSL https://raw.githubusercontent.com/Xenthio/pi-crt-toolkit/main/install.sh | bash
}

main "$@"
